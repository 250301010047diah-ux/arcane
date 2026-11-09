import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;


import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'art.dart';
import 'audio.dart';
import 'data.dart';

final _rng = math.Random();
String coinFmt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

double rnd() => _rng.nextDouble();
double _hypot(double x, double y) => math.sqrt(x * x + y * y);

// ---------------- Input ----------------

class GameInput {
  final Set<String> _down = {};
  final Set<String> _pressed = {};
  double joyX = 0;
  VoidCallback? onEngage;
  bool _engaged = false;

  void _engage() {
    if (_engaged) return;
    _engaged = true;
    onEngage?.call();
  }

  void press(String action) {
    _engage();
    if (!_down.contains(action)) _pressed.add(action);
    _down.add(action);
  }

  void release(String action) => _down.remove(action);

  bool isDown(String action) => _down.contains(action);

  double moveAxis() {
    if (joyX != 0) return joyX;
    return (_down.contains('right') ? 1.0 : 0.0) - (_down.contains('left') ? 1.0 : 0.0);
  }

  bool consume(String action) => _pressed.remove(action);

  void setJoystick(double x) {
    _engage();
    joyX = x;
  }

  void clear() {
    _down.clear();
    _pressed.clear();
    joyX = 0;
  }
}

// ---------------- Entities ----------------

class Player {
  double x, y, vx = 0, vy = 0, facing = 1;
  int jumps = 0;
  double dashTimer = 0, dashCooldown = 0, invulnerable = 0, hurtFlash = 0, shotFlash = 0;
  final double animSeed = rnd() * 5;
  int hp = 3;
  double worldTime = 0;
  double skillOneCooldown = 0, skillTwoCooldown = 0, ultimateCooldown = 0;
  double skillOneMax = 1, skillTwoMax = 1, ultimateMax = 1;
  double castTimer = 0, castElapsed = 0, landTimer = 0, dustTimer = 0, shootCooldown = 0;
  String castAnimation = 'idle';
  Player(this.x, this.y);
}

class Bullet {
  double x, y, vx, vy, radius, damage, life;
  int pierce;
  final Set<int> hitIds = {};
  bool homing, bounce, forceFire, forceIce;
  Bullet({
    required this.x, required this.y, required this.vx, required this.vy, required this.radius,
    required this.damage, required this.pierce, required this.life,
    this.homing = false, this.bounce = false, this.forceFire = false, this.forceIce = false,
  });
}

class Enemy {
  final int id, type, mode;
  final bool elite, mini, immune;
  double x, y, vx, vy, baseY, hp, maxHp, size, radius;
  double age = 0, shootCd, attackTimer = 0, burn = 0, burnTick = 0.5, slow = 0, hitFlash = 0;
  bool pendingAttack = false;
  final double animSeed = rnd() * 4;
  final double facing;
  Enemy({
    required this.id, required this.type, required this.mode, required this.elite, required this.mini,
    required this.x, required this.y, required this.vx, required this.vy, required this.baseY,
    required this.hp, required this.size, required this.shootCd, required this.facing, this.immune = false,
  })  : maxHp = hp,
        radius = size * 0.28;
}

class EnemyShot {
  final String kind; // orb | laser | zone
  double x, y, vx, vy, radius, delay, age = 0, life, width, activeDuration, top;
  Color color;
  bool lightning, struck = false;
  EnemyShot({
    required this.kind, required this.x, this.y = 0, this.vx = 0, this.vy = 0, this.radius = 8,
    this.color = const Color(0xFFFF55CB), this.delay = 0, required this.life, this.width = 0,
    this.activeDuration = 0, this.top = 0, this.lightning = false,
  });
}

class Pickup {
  final String? kind; // 'coin' or null
  final String id, name;
  final String icon;
  final int value;
  double x, y, vy, size;
  final double animSeed = rnd() * 6;
  Pickup({this.kind, required this.id, required this.name, this.icon = '', this.value = 0,
      required this.x, required this.y, required this.vy, required this.size});
}

class Effect {
  final String key, animation;
  final double x, y, size, duration;
  double age = 0;
  Effect(this.key, this.animation, this.x, this.y, this.size, this.duration);
}

class Particle {
  double x, y, vx, vy, life;
  final double maxLife, size;
  final Color color;
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color) : maxLife = life;
}

class Ring {
  final double x, y, radius, maxLife;
  final Color color;
  double life;
  Ring(this.x, this.y, this.radius, this.color, this.life) : maxLife = life;
}

class Boss {
  final int id;
  final String name;
  double x, y, size, hp, maxHp, patternTimer = 1.35, telegraph = 0, attackAnim = 0, animTime = 0, alpha = 1, hitFlash = 0;
  bool pendingAttack = false;
  String animation = 'idle';
  double get radius => size * 0.35;
  Boss(this.id, this.name, this.x, this.y, this.size, this.hp) : maxHp = hp;
}

class Power {
  double gatling = 0, boots = 0;
  int shield = 0;
}

class Bounds {
  final double width, height, left, right, floorY;
  const Bounds(this.width, this.height, this.left, this.right, this.floorY);
}

class GameState {
  String phase = 'loadout';
  int realm, selectedSkin;
  double score = 0;
  int runCoins = 0, kills = 0, realmStage = 0;
  double worldTime = 0, screenFlash = 0, timeSlow = 0, cloneTimer = 0, counterTimer = 0;
  double floorY, waveTime, spawnTimer = 0.5, shake = 0, bossDefeatTimer = 0;
  final Player player;
  final List<Bullet> bullets = [];
  final List<EnemyShot> enemyBullets = [];
  final List<Enemy> enemies = [];
  final List<Pickup> pickups = [];
  final List<Effect> effects = [];
  final List<Particle> particles = [];
  final List<Ring> rings = [];
  Boss? boss;
  final Map<String, int> buffLevels = makeBuffState();
  final Power power = Power();
  GameState(this.realm, this.selectedSkin, this.floorY, this.waveTime, this.player);
}

// ---------------- Save ----------------

class SaveData {
  double bestScore = 0;
  int bestRealm = 0, wins = 0, coins = 0, selectedSkin = 0, selectedRealm = 0;
  List<int> unlockedSkins = [0];
  bool tutorialSeen = false, allAreas = false, infiniteCoins = false;
  double music = 1, sfx = 1;

  Map<String, dynamic> toJson() => {
        'version': 2, 'bestScore': bestScore, 'bestRealm': bestRealm, 'wins': wins, 'coins': coins,
        'unlockedSkins': unlockedSkins, 'selectedSkin': selectedSkin, 'selectedRealm': selectedRealm,
        'tutorialSeen': tutorialSeen, 'allAreas': allAreas, 'infiniteCoins': infiniteCoins, 'settings': {'music': music, 'sfx': sfx},
      };

  static double _unit(dynamic v, double fallback) => v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : fallback;

  static SaveData fromJson(Map j) {
    final s = SaveData();
    if (j['version'] != 1 && j['version'] != 2) return s;
    num n(dynamic v) => v is num ? v : 0;
    s.bestScore = n(j['bestScore']).toDouble();
    s.bestRealm = n(j['bestRealm']).toInt();
    s.wins = n(j['wins']).toInt();
    s.coins = math.max(0, n(j['coins']).toInt());
    final list = j['unlockedSkins'];
    s.unlockedSkins = list is List
        ? {0, ...list.whereType<num>().map((e) => e.toInt()).where((e) => e >= 0 && e < 20)}.toList()
        : [0];
    s.unlockedSkins.sort();
    s.selectedSkin = n(j['selectedSkin']).toInt().clamp(0, 19);
    s.selectedRealm = n(j['selectedRealm']).toInt().clamp(0, 9);
    s.tutorialSeen = j['tutorialSeen'] == true;
    s.allAreas = j['allAreas'] == true;
    s.infiniteCoins = j['infiniteCoins'] == true;
    final settings = j['settings'];
    if (settings is Map) {
      s.music = _unit(settings['music'], 1);
      s.sfx = _unit(settings['sfx'], 1);
    }
    return s;
  }
}

// ---------------- UI-facing state ----------------

enum OverlayKind { none, loadout, camp, gameOver, victory }

enum ModalKind { none, pause, tutorial, volume, confirm }

class ConfirmData {
  final String title, text, confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  ConfirmData(this.title, this.text, this.confirmLabel, this.onConfirm, this.onCancel);
}

// ---------------- Engine ----------------

class GameEngine extends ChangeNotifier {
  GameEngine();

  final ArtLibrary art = ArtLibrary();
  final Balance balance = Balance();
  final GameInput input = GameInput();
  late ArcaneAudio audio;
  SaveData saved = SaveData();
  late GameState state;
  int _nextId = 1;

  // Viewport (set by the widget).
  double width = 0, height = 0;

  // UI state.
  bool booted = false;
  bool bootFailed = false;
  String? loadingMessage = 'Menyelaraskan rune…';
  String? toastMessage;
  Timer? _toastTimer;
  int toastSerial = 0;
  OverlayKind overlay = OverlayKind.none;
  bool menuRefresh = false;
  List<Buff> campChoices = [];
  ModalKind modal = ModalKind.none;
  int tutorialPage = 0;
  bool tutorialFirst = false;
  VoidCallback? _modalOnClose;
  ConfirmData? confirmData;

  bool get isModalOpen => modal != ModalKind.none;
  bool get isPlaying => booted && (state.phase == 'wave' || state.phase == 'boss');
  bool canAfford(int price) => saved.infiniteCoins || saved.coins >= price;
  String get coinText => saved.infiniteCoins ? '999+' : coinFmt(saved.coins);
  bool areaUnlocked(int index) => saved.allAreas || index <= math.min(9, saved.bestRealm);

  Bounds getBounds() {
    final controlsReserve = math.max(126.0, math.min(182.0, height * 0.23));
    final side = math.max(22.0, width * 0.06);
    return Bounds(width, height, side, width - side, height - controlsReserve);
  }

  void haptic([int strength = 1]) {
    try {
      strength >= 3 ? HapticFeedback.heavyImpact() : strength == 2 ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    } catch (_) {}
  }

  GameState freshState() {
    final b = getBounds();
    return GameState(saved.selectedRealm.clamp(0, 9), saved.selectedSkin.clamp(0, 19), b.floorY, balance.waveDuration,
        Player(b.width * 0.5, b.floorY));
  }

  // ---------- UI helpers ----------

  void toast(String message, [double duration = 1.7]) {
    toastMessage = message;
    toastSerial++;
    _toastTimer?.cancel();
    _toastTimer = Timer(Duration(milliseconds: (duration * 1000).round()), () {
      toastMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void setLoading(bool visible, [String message = 'Menyelaraskan rune…']) {
    loadingMessage = visible ? message : null;
    notifyListeners();
  }

  void _openModal(ModalKind kind, [VoidCallback? onClose]) {
    modal = kind;
    _modalOnClose = onClose;
    notifyListeners();
  }

  void closeModal() {
    if (modal == ModalKind.none) return;
    modal = ModalKind.none;
    confirmData = null;
    final cb = _modalOnClose;
    _modalOnClose = null;
    notifyListeners();
    cb?.call();
  }

  void hideOverlay() {
    overlay = OverlayKind.none;
    notifyListeners();
  }

  // ---------- Effects ----------

  void emitParticles(double x, double y, Color color, [int baseCount = 7]) {
    final count = math.max(2, (baseCount * balance.effectsIntensity).round());
    for (var i = 0; i < count; i++) {
      final angle = rnd() * math.pi * 2;
      final speed = 35 + rnd() * 120;
      final life = 0.25 + rnd() * 0.45;
      state.particles.add(Particle(x, y, math.cos(angle) * speed, math.sin(angle) * speed, life, 2 + rnd() * 4, color));
    }
  }

  void addRing(double x, double y, double radius, Color color, [double duration = 0.32]) =>
      state.rings.add(Ring(x, y, radius, color, duration));

  void addEffect(String key, String animation, double x, double y, [double size = 72, double duration = 0.5]) =>
      state.effects.add(Effect(key, animation, x, y, size, duration));

  ({double x, double y, double radius}) playerBody() => (x: state.player.x, y: state.player.y - 25, radius: 14);

  static bool circleHit(double ax, double ay, double ar, double bx, double by, double br, [double padding = 0]) {
    final dx = ax - bx, dy = ay - by;
    final r = ar + br + padding;
    return dx * dx + dy * dy <= r * r;
  }

  // ---------- Player shots & skills ----------

  void spawnShot() {
    final p = state.player;
    final movingAngle = p.vx.abs() > 28 ? p.vx.sign * 0.22 : 0.0;
    final split = state.buffLevels['split']!;
    final offsets = split >= 2 ? [-0.36, -0.18, 0.0, 0.18, 0.36] : split == 1 ? [-0.22, 0.0, 0.22] : [0.0];
    const speed = 620.0;
    final heavy = state.buffLevels['heavy']!;
    final skinPower = skins[state.selectedSkin].power;
    final cloneOffsets = state.cloneTimer > 0 ? [-0.12, 0.12] : <double>[];
    for (final offset in [...offsets, ...cloneOffsets]) {
      final angle = movingAngle + offset;
      state.bullets.add(Bullet(
        x: p.x + p.facing * 8, y: p.y - 44,
        vx: math.sin(angle) * speed, vy: -math.cos(angle) * speed,
        radius: 5.5 + heavy * 1.8, damage: (1 + heavy * 0.5) * skinPower,
        pierce: state.buffLevels['piercing']!, life: 1.8,
      ));
    }
    p.shotFlash = 0.14;
    final muzzleX = p.x + (movingAngle != 0 ? movingAngle.sign * 24 : 0);
    addEffect('WEAPON_EFFECTS', 'muzzle_flash', muzzleX, p.y - 45, 34, 0.22);
    audio.sfx('shoot');
  }

  void spawnSkillVolley(int count, double arc, double damage,
      {double speed = 690, double radius = 7, int pierce = 3, double life = 2.2, bool homing = false, bool bounce = false, bool fire = false, bool ice = false}) {
    final p = state.player;
    for (var i = 0; i < count; i++) {
      final ratio = count == 1 ? 0.5 : i / (count - 1);
      final angle = (ratio - 0.5) * arc;
      state.bullets.add(Bullet(
        x: p.x, y: p.y - 45, vx: math.sin(angle) * speed, vy: -math.cos(angle) * speed,
        radius: radius, damage: damage, pierce: pierce, life: life,
        homing: homing, bounce: bounce, forceFire: fire, forceIce: ice,
      ));
    }
  }

  void damageAllEnemies(double amount, {double slow = 0, double burn = 0}) {
    for (final enemy in [...state.enemies]) {
      if (!enemy.immune) enemy.hp -= amount;
      if (slow > 0) enemy.slow = math.max(enemy.slow, slow);
      if (burn > 0) enemy.burn = math.max(enemy.burn, burn);
      if (enemy.hp <= 0) killEnemy(enemy);
    }
  }

  void castSkill(String slot) {
    final p = state.player;
    final skin = skins[state.selectedSkin];
    final index = state.selectedSkin;
    final power = skin.power;
    if (slot == 'one') {
      if (p.skillOneCooldown > 0) return;
      p.skillOneCooldown = math.max(3.4, 6 - index * 0.07);
      p.skillOneMax = p.skillOneCooldown;
      p.castAnimation = 'skill_one';
      p.castTimer = 0.62;
      p.castElapsed = 0;
      final count = math.min(24, 7 + (index * 0.7).floor());
      spawnSkillVolley(count, 0.7 + index * 0.025, (1.5 + index * 0.12) * power,
          pierce: 2 + index ~/ 5,
          radius: 6 + index * 0.12,
          fire: const [1, 10, 11, 15].contains(index),
          ice: const [2, 11].contains(index),
          homing: const [8, 15].contains(index),
          bounce: index == 14);
      if (const [2, 4, 17].contains(index)) damageAllEnemies(0.8 * power, slow: 2.8);
      if (const [3, 6, 18].contains(index)) {
        damageAllEnemies(1.2 * power);
        addEffect('DEFENSE_EFFECTS', 'chain_lightning', width * 0.5, height * 0.4, width * 0.82, 0.5);
      }
      if (const [7, 10, 13, 19].contains(index)) damageAllEnemies((1.4 + index * 0.08) * power, burn: index == 10 ? 2.5 : 0);
      toast(skin.skillOne);
      audio.sfx('skill1');
      haptic(1);
    } else if (slot == 'two') {
      if (p.skillTwoCooldown > 0) return;
      p.skillTwoCooldown = math.max(5.5, 10 - index * 0.12);
      p.skillTwoMax = p.skillTwoCooldown;
      p.castAnimation = 'skill_two';
      p.castTimer = 0.82;
      p.castElapsed = 0;
      if (const [0, 5, 13, 16].contains(index)) state.power.shield = math.max(state.power.shield, 2 + index ~/ 8);
      if (const [1, 3, 9, 10, 12, 14].contains(index)) {
        final b = getBounds();
        p.x = p.facing > 0 ? b.right : b.left;
        p.invulnerable = math.max(p.invulnerable, 0.8);
        damageAllEnemies(2.2 * power);
      }
      if (const [2, 4, 8, 15].contains(index)) {
        state.timeSlow = 3.5 + index * 0.08;
        state.enemyBullets.clear();
        damageAllEnemies(1.2 * power, slow: 4);
      }
      if (const [6, 18, 19].contains(index)) state.cloneTimer = 6 + index * 0.16;
      if (const [7, 11, 19].contains(index)) state.power.gatling = math.max(state.power.gatling, 7 + index * 0.12);
      if (index == 17) {
        state.counterTimer = 5;
        state.power.shield = math.max(state.power.shield, 1);
      }
      if (index >= 14) p.hp = math.min(3, p.hp + 1);
      addEffect('DEFENSE_EFFECTS', 'nova_wave', p.x, p.y - 35, 130 + index * 4.0, 0.65);
      toast(skin.skillTwo);
      audio.sfx('skill2');
      haptic(2);
    } else {
      if (p.ultimateCooldown > 0) return;
      p.ultimateCooldown = math.max(14, 25 - index * 0.35);
      p.ultimateMax = p.ultimateCooldown;
      p.castAnimation = 'ultimate';
      p.castTimer = 1.2;
      p.castElapsed = 0;
      p.invulnerable = 1.5;
      state.screenFlash = 0.9;
      state.enemyBullets.clear();
      final damage = (10 + index * 2.1) * power;
      damageAllEnemies(damage, slow: 4, burn: 3);
      final boss = state.boss;
      if (boss != null) boss.hp -= boss.maxHp * (0.12 + index * 0.009) + damage;
      if (index >= 12) state.power.shield = math.max(state.power.shield, 2);
      if (index >= 17) state.cloneTimer = math.max(state.cloneTimer, 10);
      addEffect('DEFENSE_EFFECTS', 'nova_wave', width * 0.5, height * 0.42, math.max(width, height) * 1.15, 1.1);
      emitParticles(p.x, p.y - 40, skin.color, 45 + index * 2);
      toast(skin.ultimate, 2.2);
      audio.sfx('ultimate');
      haptic(3);
    }
  }

  // ---------- Enemies ----------

  Enemy spawnEnemy([int? typeArg, bool mini = false]) {
    final type = typeArg ?? (rnd() < 0.54 ? 0 : 1);
    final b = getBounds();
    final realm = state.realm;
    final speedScale = 1 + realm * 0.055;
    final mode = type % 2;
    final elite = type >= 2;
    Enemy enemy;
    if (mode == 0) {
      final size = (mini ? 34 : 54 + math.min(realm, 5) * 2) * 0.7;
      final hp = (mini ? 1 : 2 + realm ~/ 3) * (elite ? 2.2 : 1.0);
      enemy = Enemy(
        id: _nextId++, type: type, mode: mode, elite: elite, mini: mini,
        x: b.left + rnd() * (b.right - b.left), y: -size * 0.5,
        vx: mini ? (rnd() < 0.5 ? -1 : 1) * 115.0 : 0,
        vy: balance.enemySpeed * speedScale * (realm == 4 ? 0.58 : 1),
        baseY: 0, hp: hp, size: size, shootCd: 1.3, facing: -1, immune: realm == 6,
      );
    } else {
      final fromLeft = rnd() < 0.5;
      final size = (58 + math.min(realm, 5) * 2) * 0.7;
      final y = b.height * (0.22 + rnd() * 0.28);
      final hp = (3 + realm ~/ 3) * (elite ? 2.2 : 1.0);
      enemy = Enemy(
        id: _nextId++, type: type, mode: mode, elite: elite, mini: false,
        x: fromLeft ? -size : b.width + size, y: y, baseY: y,
        vx: (fromLeft ? 1 : -1) * balance.enemySpeed * (1.05 + realm * 0.045), vy: 0,
        hp: hp, size: size, shootCd: 0.8 + rnd() * 1.2, facing: fromLeft ? -1 : 1,
      );
    }
    state.enemies.add(enemy);
    return enemy;
  }

  ({double vx, double vy}) aimedVelocity(double fx, double fy, double speed, [double spread = 0]) {
    final t = playerBody();
    final angle = math.atan2(t.y - fy, t.x - fx) + spread;
    return (vx: math.cos(angle) * speed, vy: math.sin(angle) * speed);
  }

  void addOrb(double x, double y, double vx, double vy, [double radius = 8, Color color = const Color(0xFFFF55CB), double delay = 0, double life = 5]) =>
      state.enemyBullets.add(EnemyShot(kind: 'orb', x: x, y: y, vx: vx, vy: vy, radius: radius, color: color, delay: delay, life: life));

  void addLaser(double x, [double width = 42, double delay = 0.72, double activeDuration = 0.55, double top = 0]) =>
      state.enemyBullets.add(EnemyShot(kind: 'laser', x: x, width: width, delay: delay, activeDuration: activeDuration, top: top,
          life: delay + activeDuration, lightning: state.realm == 8));

  void addZone(double x, [double width = 70, double delay = 0.72, double activeDuration = 0.5]) =>
      state.enemyBullets.add(EnemyShot(kind: 'zone', x: x, width: width, delay: delay, activeDuration: activeDuration, life: delay + activeDuration));

  void executeEnemyAttack(Enemy enemy) {
    audio.sfx('enemy_shoot');
    final realm = state.realm;
    final speed = 155.0 + realm * 8;
    if (realm == 8 && enemy.mode == 1) {
      addLaser(enemy.x, 36, 0.62, 0.42, enemy.y);
      return;
    }
    if (realm == 4 && enemy.mode == 1) {
      enemy.vx *= 1.85;
      return;
    }
    if (realm == 5 && enemy.mode == 1) {
      enemy.vx *= -0.7;
      final v = aimedVelocity(enemy.x, enemy.y, speed);
      addOrb(enemy.x, enemy.y, v.vx, v.vy, 9, hex('#b5f7ff'));
      return;
    }
    if (realm == 3 && enemy.mode == 1) {
      for (final spread in [-0.28, 0.28]) {
        final v = aimedVelocity(enemy.x, enemy.y, speed, spread);
        addOrb(enemy.x, enemy.y, v.vx, v.vy, 6, hex('#ffd568'));
      }
      return;
    }
    final v = aimedVelocity(enemy.x, enemy.y, realm == 6 ? speed * 1.35 : speed);
    addOrb(enemy.x, enemy.y, v.vx, v.vy, realm == 6 ? 10 : 8, realm == 0 ? hex('#8dff57') : realms[realm].colors[1]);
  }

  void handleGroundImpact(Enemy enemy) {
    final realm = state.realm;
    if (realm == 3) {
      for (var i = 0; i < 8; i++) {
        final angle = math.pi * 2 * i / 8;
        addOrb(enemy.x, state.floorY - 8, math.cos(angle) * 145, math.sin(angle) * 145, 7, hex('#ffbe45'));
      }
    } else if (realm == 7) {
      addOrb(enemy.x, state.floorY - 10, -210, -55, 8, hex('#a9f2ff'));
      addOrb(enemy.x, state.floorY - 10, 210, -55, 8, hex('#a9f2ff'));
    } else if (realm == 6) {
      addZone(enemy.x, 72, 0.12, 0.34);
    } else {
      emitParticles(enemy.x, state.floorY - 8, realms[realm].colors[0], 5);
    }
  }

  void dropPickup(Enemy enemy) {
    if (rnd() > 0.13 || state.pickups.where((p) => p.kind != 'coin').length >= 2) return;
    final data = powerups[_rng.nextInt(powerups.length)];
    state.pickups.add(Pickup(id: data.id, icon: data.icon, name: data.name, x: enemy.x, y: enemy.y, vy: 74, size: 45));
  }

  void dropCoin(Enemy enemy) {
    final value = 1 + state.realm ~/ 3 + (enemy.elite ? 2 : 0);
    state.pickups.add(Pickup(kind: 'coin', id: 'coin', name: 'Arcane Coin', value: value, x: enemy.x, y: enemy.y, vy: 64, size: 27));
  }

  void killEnemy(Enemy enemy, [bool allowDrop = true]) {
    if (!state.enemies.remove(enemy)) return;
    state.score += 100 * (state.realm + 1);
    state.kills += 1;
    final color = realms[state.realm].colors[0];
    emitParticles(enemy.x, enemy.y, color, 9);
    addEffect('WEAPON_EFFECTS', 'impact_burst', enemy.x, enemy.y, enemy.size * 1.5, 0.45);
    addRing(enemy.x, enemy.y, enemy.size * (enemy.elite ? 1.5 : 1.1), color);
    state.shake = math.max(state.shake, enemy.elite ? 0.22 : 0.12);
    audio.sfx('enemy_die');
    if (allowDrop) {
      dropCoin(enemy);
      dropPickup(enemy);
    }
    if (state.realm == 0 && enemy.type == 0 && !enemy.mini) {
      spawnEnemy(0, true).x = enemy.x - 14;
      spawnEnemy(0, true).x = enemy.x + 14;
    }
    if (state.buffLevels['vampiric']! > 0 && state.kills % 50 == 0) {
      state.player.hp = math.min(3, state.player.hp + 1);
      toast('Vampiric Chamber · +1 HP');
    }
  }

  void damageEnemy(Enemy enemy, double damage, Bullet bullet) {
    if (enemy.immune) {
      emitParticles(bullet.x, bullet.y, hex('#ff744a'), 4);
      return;
    }
    enemy.hp -= damage;
    enemy.hitFlash = 0.14;
    audio.sfx('enemy_hit');
    if (state.buffLevels['fire']! > 0 || bullet.forceFire) enemy.burn = 2.3;
    if (state.buffLevels['ice']! > 0 || bullet.forceIce) enemy.slow = 1.8 + math.max(1, state.buffLevels['ice']!) * 0.55;
    if (state.realm == 8 && enemy.mode == 0) enemy.size = math.min(76, enemy.size + 2);
    if (state.buffLevels['lightning']! > 0) chainLightning(enemy, state.buffLevels['lightning']!);
    if (enemy.hp <= 0) killEnemy(enemy);
  }

  void chainLightning(Enemy origin, int count) {
    var current = origin;
    final used = {origin.id};
    for (var jump = 0; jump < count; jump++) {
      final candidates = state.enemies.where((e) => !used.contains(e.id) && !e.immune).toList()
        ..sort((a, b) => _hypot(a.x - current.x, a.y - current.y).compareTo(_hypot(b.x - current.x, b.y - current.y)));
      if (candidates.isEmpty) break;
      final target = candidates.first;
      final dist = _hypot(target.x - current.x, target.y - current.y);
      if (dist > 180) break;
      used.add(target.id);
      target.hp -= 0.65;
      addEffect('DEFENSE_EFFECTS', 'chain_lightning', (current.x + target.x) / 2, (current.y + target.y) / 2, math.max(54, dist), 0.28);
      if (target.hp <= 0) killEnemy(target);
      current = target;
    }
  }

  void collectPickup(Pickup pickup) {
    audio.sfx(pickup.kind == 'coin' ? 'coin' : pickup.id == 'nova' ? 'nova' : 'powerup');
    haptic(1);
    if (pickup.kind == 'coin') {
      saved.coins += pickup.value;
      state.runCoins += pickup.value;
      persist();
      return;
    }
    if (pickup.id == 'gatling') state.power.gatling = 10;
    if (pickup.id == 'boots') state.power.boots = 10;
    if (pickup.id == 'shield') state.power.shield = 1;
    if (pickup.id == 'nova') {
      addEffect('DEFENSE_EFFECTS', 'nova_wave', state.player.x, state.player.y - 50, math.max(width, height) * 0.72, 0.72);
      for (final e in [...state.enemies]) {
        killEnemy(e, false);
      }
      final boss = state.boss;
      if (boss != null) boss.hp -= boss.maxHp * 0.1;
      haptic(2);
    }
    toast(pickup.name);
  }

  void hurtPlayer() {
    final p = state.player;
    if (p.invulnerable > 0 || p.dashTimer > 0 || state.phase == 'gameover') return;
    if (state.counterTimer > 0) {
      state.counterTimer = 0;
      state.enemyBullets.clear();
      damageAllEnemies(8 * skins[state.selectedSkin].power);
      state.boss?.hp -= 12 * skins[state.selectedSkin].power;
      addEffect('DEFENSE_EFFECTS', 'nova_wave', p.x, p.y - 35, 180, 0.65);
      p.invulnerable = 0.7;
      audio.sfx('counter');
      return;
    }
    if (state.power.shield > 0) {
      state.power.shield -= 1;
      p.invulnerable = 0.5;
      addEffect('DEFENSE_EFFECTS', 'nova_wave', p.x, p.y - 36, 95, 0.42);
      audio.sfx('shield_break');
      haptic(1);
      toast('Aegis pecah');
      return;
    }
    p.hp -= 1;
    p.invulnerable = 1.1;
    p.hurtFlash = 0.55;
    emitParticles(p.x, p.y - 35, hex('#ff557a'), 12);
    audio.sfx('player_hurt');
    haptic(2);
    if (p.hp <= 0) gameOver();
  }

  void updateEnemies(double dt) {
    final b = getBounds();
    for (var i = state.enemies.length - 1; i >= 0; i--) {
      // hurtPlayer() can kill several enemies mid-loop (counter skill).
      if (i >= state.enemies.length) continue;
      final enemy = state.enemies[i];
      enemy.age += dt;
      enemy.attackTimer = math.max(0, enemy.attackTimer - dt);
      enemy.slow = math.max(0, enemy.slow - dt);
      final slowFactor = enemy.slow > 0 ? 0.52 : 1.0;
      if (enemy.burn > 0) {
        enemy.burn -= dt;
        enemy.burnTick -= dt;
        if (enemy.burnTick <= 0) {
          enemy.burnTick = 0.5;
          enemy.hp -= 0.25 + state.buffLevels['fire']! * 0.18;
          if (enemy.hp <= 0) {
            killEnemy(enemy);
            continue;
          }
        }
      }
      if (enemy.mode == 0) {
        if (enemy.mini) {
          enemy.x += enemy.vx * dt * slowFactor;
          enemy.y = state.floorY - 18 + math.sin(enemy.age * 9) * 3;
          if (enemy.x < b.left || enemy.x > b.right) enemy.vx *= -1;
          if (enemy.age > 8) {
            emitParticles(enemy.x, enemy.y, realms[state.realm].colors[0], 4);
            state.enemies.remove(enemy);
            continue;
          }
        } else {
          if (state.realm == 1 && enemy.age < 0.8) enemy.x += (state.player.x - enemy.x) * dt * 1.1;
          enemy.y += enemy.vy * dt * slowFactor;
          if (state.realm == 8) enemy.vy *= 1.0007;
        }
      } else {
        enemy.x += enemy.vx * dt * slowFactor;
        final wave = state.realm == 1 ? math.sin(enemy.age * 3) * 70 : math.sin(enemy.age * 2.7 + enemy.animSeed) * 24;
        enemy.y = enemy.baseY + wave;
        enemy.shootCd -= dt * slowFactor;
        if (enemy.shootCd <= 0 && !enemy.pendingAttack) {
          enemy.shootCd = math.max(0.75, 2.05 - state.realm * 0.07) + rnd() * 0.7;
          enemy.attackTimer = 0.48;
          enemy.pendingAttack = true;
        }
        if (enemy.pendingAttack && enemy.attackTimer <= 0.2) {
          enemy.pendingAttack = false;
          executeEnemyAttack(enemy);
        }
      }

      final body = playerBody();
      if (circleHit(body.x, body.y, body.radius, enemy.x, enemy.y, enemy.radius, -3)) {
        hurtPlayer();
        if (!enemy.immune) killEnemy(enemy, false);
        continue;
      }
      if (enemy.mode == 0 && !enemy.mini && enemy.y >= state.floorY - 16) {
        handleGroundImpact(enemy);
        state.enemies.remove(enemy);
        continue;
      }
      if (enemy.mode == 1 && (enemy.x < -enemy.size * 2 || enemy.x > b.width + enemy.size * 2)) {
        state.enemies.remove(enemy);
      }
    }
  }

  void updatePlayerBullets(double dt) {
    final b = getBounds();
    for (var i = state.bullets.length - 1; i >= 0; i--) {
      if (i >= state.bullets.length) continue;
      final bullet = state.bullets[i];
      if (bullet.homing && state.enemies.isNotEmpty) {
        Enemy? target;
        var best = double.infinity;
        for (final e in state.enemies) {
          final d = _hypot(e.x - bullet.x, e.y - bullet.y);
          if (d < best) {
            best = d;
            target = e;
          }
        }
        final angle = math.atan2(target!.y - bullet.y, target.x - bullet.x);
        final speed = _hypot(bullet.vx, bullet.vy);
        final k = math.min(1.0, dt * 4);
        bullet.vx += (math.cos(angle) * speed - bullet.vx) * k;
        bullet.vy += (math.sin(angle) * speed - bullet.vy) * k;
      }
      bullet.x += bullet.vx * dt;
      bullet.y += bullet.vy * dt;
      if (bullet.bounce && (bullet.x < b.left || bullet.x > b.right)) {
        bullet.vx *= -1;
        bullet.x = bullet.x.clamp(b.left, b.right);
      }
      bullet.life -= dt;
      var removed = false;
      for (final enemy in [...state.enemies]) {
        if (bullet.hitIds.contains(enemy.id) || !circleHit(bullet.x, bullet.y, bullet.radius, enemy.x, enemy.y, enemy.radius)) continue;
        bullet.hitIds.add(enemy.id);
        damageEnemy(enemy, bullet.damage, bullet);
        addEffect('WEAPON_EFFECTS', 'impact_burst', bullet.x, bullet.y, 52 + bullet.radius * 2, 0.3);
        bullet.pierce -= 1;
        if (bullet.pierce < 0) {
          state.bullets.remove(bullet);
          removed = true;
          break;
        }
      }
      if (removed) continue;
      final boss = state.boss;
      if (boss != null && circleHit(bullet.x, bullet.y, bullet.radius, boss.x, boss.y, boss.radius, boss.size * 0.2)) {
        boss.hp -= bullet.damage;
        boss.hitFlash = 0.1;
        audio.sfx('boss_hit');
        addEffect('WEAPON_EFFECTS', 'impact_burst', bullet.x, bullet.y, 58, 0.3);
        emitParticles(bullet.x, bullet.y, realms[state.realm].colors[0], 3);
        state.bullets.remove(bullet);
        continue;
      }
      if (bullet.life <= 0 || bullet.y < -50 || bullet.x < -50 || bullet.x > b.width + 50) state.bullets.remove(bullet);
    }
  }

  void updateEnemyBullets(double dt) {
    final body = playerBody();
    final b = getBounds();
    for (var i = state.enemyBullets.length - 1; i >= 0; i--) {
      // hurtPlayer() can clear enemyBullets mid-loop.
      if (i >= state.enemyBullets.length) continue;
      final bullet = state.enemyBullets[i];
      bullet.age += dt;
      final active = bullet.age >= bullet.delay;
      if (active && bullet.kind == 'orb') {
        bullet.x += bullet.vx * dt;
        bullet.y += bullet.vy * dt;
        if (circleHit(body.x, body.y, body.radius, bullet.x, bullet.y, bullet.radius)) {
          hurtPlayer();
          state.enemyBullets.remove(bullet);
          continue;
        }
      } else if (active && bullet.kind == 'laser') {
        if (!bullet.struck) {
          bullet.struck = true;
          audio.sfx(bullet.lightning ? 'lightning' : 'laser');
          if (bullet.lightning) state.shake = math.max(state.shake, 0.18);
        }
        if (body.x > bullet.x - bullet.width / 2 && body.x < bullet.x + bullet.width / 2 && body.y > bullet.top && body.y <= state.floorY + 8) {
          hurtPlayer();
        }
      } else if (active && bullet.kind == 'zone') {
        final inside = body.x > bullet.x - bullet.width / 2 && body.x < bullet.x + bullet.width / 2;
        if (inside && body.y > state.floorY - 48) hurtPlayer();
      }
      if (bullet.age >= bullet.life || bullet.x < -100 || bullet.x > b.width + 100 || bullet.y > b.height + 100) {
        state.enemyBullets.remove(bullet);
      }
    }
  }

  void updatePickups(double dt) {
    final body = playerBody();
    for (var i = state.pickups.length - 1; i >= 0; i--) {
      final pickup = state.pickups[i];
      if (pickup.kind == 'coin') {
        final distance = _hypot(body.x - pickup.x, body.y - pickup.y);
        if (distance < 150) pickup.x += (body.x - pickup.x) * dt * 4.5;
      }
      pickup.y += pickup.vy * dt;
      if (circleHit(body.x, body.y, body.radius, pickup.x, pickup.y, pickup.size * 0.3)) {
        state.pickups.removeAt(i);
        collectPickup(pickup);
      } else if (pickup.y > state.floorY + 25) {
        state.pickups.removeAt(i);
      }
    }
  }

  void updateFeedback(double dt) {
    for (final e in state.effects) {
      e.age += dt;
    }
    state.effects.removeWhere((e) => e.age >= e.duration);
    for (final p in state.particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 95 * dt;
    }
    state.particles.removeWhere((p) => p.life <= 0);
    for (final r in state.rings) {
      r.life -= dt;
    }
    state.rings.removeWhere((r) => r.life <= 0);
    for (final e in state.enemies) {
      e.hitFlash = math.max(0, e.hitFlash - dt);
    }
    final boss = state.boss;
    if (boss != null) boss.hitFlash = math.max(0, boss.hitFlash - dt);
    state.shake = math.max(0, state.shake - dt);
  }

  void updateWave(double dt) {
    state.waveTime = math.max(0, state.waveTime - dt);
    final pressure = 1 - state.waveTime / balance.waveDuration;
    state.realmStage = pressure >= 0.42 ? 1 : 0;
    state.spawnTimer -= dt;
    if (state.waveTime > 0 && state.spawnTimer <= 0) {
      var enemyType = rnd() < 0.54 ? 0 : 1;
      if (pressure > 0.72 && rnd() < 0.62) {
        enemyType = 4 + (rnd() < 0.5 ? 0 : 1);
      } else if (pressure > 0.38 && rnd() < math.min(0.58, 0.18 + pressure * 0.42)) {
        enemyType = 2 + (rnd() < 0.5 ? 0 : 1);
      }
      spawnEnemy(enemyType);
      state.spawnTimer = math.max(0.45, balance.spawnInterval - state.realm * 0.035 - pressure * 0.28);
    }
    if (state.waveTime <= 0 && state.enemies.isEmpty) beginBoss();
  }

  void beginBoss() {
    final b = getBounds();
    final maxHp = ((165 + state.realm * 28) * balance.bossHealthScale).roundToDouble();
    state.phase = 'boss';
    state.realmStage = 1;
    state.enemyBullets.clear();
    state.boss = Boss(_nextId++, realms[state.realm].boss, b.width * 0.5, b.height * 0.22,
        math.max(190, math.min(b.width * 0.78, b.height * 0.42)), maxHp);
    toast('BOSS · ${state.boss!.name}', 2.2);
    audio.sfx('boss_appear');
    haptic(3);
  }

  void radialBurst(Boss boss, int count, double speed, Color color) {
    for (var i = 0; i < count; i++) {
      final angle = math.pi * 2 * i / count + state.worldTime * 0.35;
      addOrb(boss.x, boss.y, math.cos(angle) * speed, math.sin(angle) * speed, 7, color);
    }
  }

  void bossPattern() {
    final boss = state.boss!;
    final b = getBounds();
    final pattern = realms[state.realm].pattern;
    double randX() => b.left + rnd() * (b.right - b.left);
    switch (pattern) {
      case 'treant':
        for (var i = 0; i < 5; i++) {
          addOrb(randX(), -15 - i * 18.0, 0, 175, 11, hex('#8dff57'), i * 0.08);
        }
        addZone(state.player.x, 64, 0.62, 0.45);
      case 'golem':
        addLaser(state.player.x, 44, 0.72, 0.55);
        addLaser(b.width * (rnd() < 0.5 ? 0.25 : 0.75), 38, 0.92, 0.48);
      case 'necro':
        for (var i = 0; i < 9; i++) {
          addOrb(randX(), -20 - i * 16.0, 0, 190 + rnd() * 40, 7, hex('#c67bff'), rnd() * 0.45);
        }
      case 'automaton':
        for (final spread in [-0.4, -0.2, 0.0, 0.2, 0.4]) {
          final v = aimedVelocity(boss.x, boss.y, 215, spread);
          addOrb(boss.x, boss.y, v.vx, v.vy, 9, hex('#ffd15a'));
        }
      case 'kraken':
        final ratios = [0.22, 0.5, 0.78];
        for (var i = 0; i < 3; i++) {
          addZone(b.width * ratios[i], b.width * 0.16, 0.55 + i * 0.18, 0.5);
        }
      case 'griffin':
        for (var i = -1; i <= 1; i++) {
          addOrb(boss.x + i * 70, boss.y, i * 35.0, 135, 16, hex('#d7fbff'), i * 0.08 + 0.15);
        }
      case 'phoenix':
        radialBurst(boss, 12, 150, hex('#ff7041'));
        for (var i = 0; i < 4; i++) {
          addOrb(randX(), -20, 0, 210, 9, hex('#ff425e'), i * 0.1);
        }
      case 'lich':
        state.bullets.removeRange(0, (state.bullets.length * 0.55).floor());
        for (final spread in [-0.38, -0.19, 0.0, 0.19, 0.38]) {
          final v = aimedVelocity(boss.x, boss.y, 180, spread);
          addOrb(boss.x, boss.y, v.vx, v.vy, 10, hex('#a9f2ff'), 0.22);
        }
      case 'worm':
        final side = rnd() < 0.5 ? 0.28 : 0.72;
        addLaser(b.width * side, b.width * 0.22, 0.78, 0.7);
        addLaser(b.width * (1 - side), b.width * 0.13, 1.05, 0.55);
      default:
        final ratio = boss.hp / boss.maxHp;
        radialBurst(boss, ratio > 0.66 ? 10 : ratio > 0.33 ? 14 : 18, ratio > 0.33 ? 170 : 210, hex('#ff3f81'));
        if (ratio <= 0.66) addLaser(state.player.x, ratio > 0.33 ? 46 : 62, 0.7, 0.58);
        if (ratio <= 0.33) {
          addZone(b.width * 0.25, b.width * 0.22, 0.8, 0.55);
          addZone(b.width * 0.75, b.width * 0.22, 1.0, 0.55);
        }
    }
    audio.sfx('boss_attack');
  }

  void updateBoss(double dt) {
    final boss = state.boss;
    if (boss == null) return;
    boss.animTime += dt;
    boss.x = width * 0.5 + math.sin(state.worldTime * 0.7) * width * 0.16;
    boss.attackAnim = math.max(0, boss.attackAnim - dt);
    if (boss.telegraph > 0) {
      boss.telegraph -= dt;
      boss.animation = 'telegraph';
      if (boss.telegraph <= 0 && boss.pendingAttack) {
        boss.pendingAttack = false;
        boss.attackAnim = 0.55;
        bossPattern();
      }
    } else if (boss.attackAnim > 0) {
      boss.animation = 'attack';
    } else {
      boss.animation = 'idle';
      boss.patternTimer -= dt;
      if (boss.patternTimer <= 0) {
        final ratio = boss.hp / boss.maxHp;
        boss.telegraph = ratio < 0.34 ? 0.48 : 0.65;
        boss.pendingAttack = true;
        boss.patternTimer = math.max(1.35, 2.45 - state.realm * 0.055 - (1 - ratio) * 0.5);
      }
    }
    if (boss.hp <= 0) defeatBoss();
  }

  void defeatBoss() {
    final boss = state.boss;
    if (boss == null || state.phase == 'bossDefeat') return;
    state.phase = 'bossDefeat';
    boss.animation = 'defeat';
    boss.animTime = 0;
    state.bossDefeatTimer = 1.55;
    state.enemyBullets.clear();
    state.bullets.clear();
    state.score += 1500 * (state.realm + 1);
    emitParticles(boss.x, boss.y, realms[state.realm].colors[0], 35);
    audio.sfx('boss_defeat');
    haptic(3);
    saved.bestRealm = math.max(saved.bestRealm, state.realm + 1);
    persist();
  }

  Future<void>? _nextRealmLoad;

  void finishBossDefeat() {
    if (state.realm == realms.length - 1) {
      victory();
      return;
    }
    state.phase = 'camp';
    state.boss = null;
    state.player.hp = math.min(3, state.player.hp + 1);
    campChoices = pickBuffChoices(state.buffLevels);
    _nextRealmLoad = art.loadRealm(state.realm + 1);
    overlay = OverlayKind.camp;
    notifyListeners();
  }

  void pickBuff(Buff buff) {
    state.buffLevels[buff.id] = math.min(buff.max, (state.buffLevels[buff.id] ?? 0) + 1);
    audio.sfx('buff_select');
    haptic(1);
    hideOverlay();
    setLoading(true, 'Membuka portal realm…');
    final load = _nextRealmLoad ?? art.loadRealm(state.realm + 1);
    load.then((_) => enterRealm(state.realm + 1)).catchError((_) {
      setLoading(false);
      toast('Portal gagal terbuka — coba pilih lagi');
      overlay = OverlayKind.camp;
      notifyListeners();
    });
  }

  void updatePower(double dt) {
    state.power.gatling = math.max(0, state.power.gatling - dt);
    state.power.boots = math.max(0, state.power.boots - dt);
    state.timeSlow = math.max(0, state.timeSlow - dt);
    state.cloneTimer = math.max(0, state.cloneTimer - dt);
    state.counterTimer = math.max(0, state.counterTimer - dt);
    state.screenFlash = math.max(0, state.screenFlash - dt * 1.8);
  }

  /// Port of physics.js stepPlayer.
  ({bool jumped, bool dashed, bool landed}) stepPlayer(double dt, Bounds bounds) {
    final p = state.player;
    final realmIndex = state.realm;
    final onIce = realmIndex == 7, inWater = realmIndex == 4, inWind = realmIndex == 5;
    final speedBoost = state.power.boots > 0 ? 1.35 : 1.0;
    final maxSpeed = balance.playerSpeed * speedBoost;
    final direction = input.moveAxis();
    final accel = onIce ? maxSpeed * 4 : maxSpeed * 10;
    final friction = onIce ? 0.975 : 0.82;
    if (direction != 0) {
      p.vx += direction * accel * dt;
      p.facing = direction.sign;
    } else {
      p.vx *= math.pow(friction, dt * 60).toDouble();
    }
    if (inWind) p.vx += math.sin(p.worldTime * 0.8) * 48 * dt;
    final speedCap = direction != 0 ? maxSpeed * direction.abs() : maxSpeed;
    p.vx = p.vx.clamp(-speedCap, speedCap);

    var jumped = false;
    if (input.consume('jump') && p.jumps < 2) {
      p.vy = -balance.jumpPower * (inWater ? 1.12 : 1) * (state.power.boots > 0 ? 1.18 : 1);
      p.jumps += 1;
      jumped = true;
    }
    var dashed = false;
    if (input.consume('dash') && p.dashCooldown <= 0) {
      final dashDirection = direction != 0 ? direction : (p.facing != 0 ? p.facing : 1);
      p.dashTimer = 0.18;
      p.dashCooldown = 1.35;
      p.vx = dashDirection * maxSpeed * 2.45;
      p.invulnerable = math.max(p.invulnerable, 0.24);
      dashed = true;
    }
    if (p.dashTimer > 0) {
      p.dashTimer -= dt;
      p.vy *= 0.82;
    } else {
      p.vy += balance.gravity * (inWater ? 0.72 : 1) * dt;
    }
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.x = p.x.clamp(bounds.left, bounds.right);
    var landed = false;
    if (p.y >= bounds.floorY) {
      landed = p.vy > 80;
      p.y = bounds.floorY;
      p.vy = 0;
      p.jumps = 0;
    }
    p.dashCooldown = math.max(0, p.dashCooldown - dt);
    p.invulnerable = math.max(0, p.invulnerable - dt);
    return (jumped: jumped, dashed: dashed, landed: landed);
  }

  void updateActive(double dt) {
    final b = getBounds();
    final p = state.player;
    final wasGrounded = p.jumps == 0 && p.vy == 0;
    state.floorY = b.floorY;
    if (wasGrounded) p.y = state.floorY;
    p.worldTime = state.worldTime;
    final m = stepPlayer(dt, b);
    if (m.jumped) {
      audio.sfx(p.jumps == 2 ? 'double_jump' : 'jump');
      if (p.jumps == 2) addEffect('DEFENSE_EFFECTS', 'double_jump_ring', p.x, p.y + 8, 72, 0.38);
    }
    if (m.dashed) {
      audio.sfx('dash');
      haptic(1);
    }
    if (m.landed) {
      p.landTimer = 0.14;
      emitParticles(p.x, state.floorY - 2, hex('#cfe3ff'), 4);
    }
    p.landTimer = math.max(0, p.landTimer - dt);
    if (p.jumps == 0 && p.vx.abs() > 120) {
      p.dustTimer -= dt;
      if (p.dustTimer <= 0) {
        p.dustTimer = 0.16;
        emitParticles(p.x - p.facing * 10, state.floorY - 2, hex('#cfe3ff'), 2);
      }
    }
    p.hurtFlash = math.max(0, p.hurtFlash - dt);
    p.shotFlash = math.max(0, p.shotFlash - dt);
    if (p.castTimer > 0) p.castElapsed += dt;
    p.castTimer = math.max(0, p.castTimer - dt);
    p.skillOneCooldown = math.max(0, p.skillOneCooldown - dt);
    p.skillTwoCooldown = math.max(0, p.skillTwoCooldown - dt);
    p.ultimateCooldown = math.max(0, p.ultimateCooldown - dt);
    if (input.consume('skill1')) castSkill('one');
    if (input.consume('skill2')) castSkill('two');
    if (input.consume('ultimate')) castSkill('ultimate');
    p.shootCooldown = math.max(0, p.shootCooldown - dt);
    if (input.isDown('fire') && p.shootCooldown <= 0) {
      final heavyPenalty = 1 + state.buffLevels['heavy']! * 0.12;
      p.shootCooldown = state.power.gatling > 0 ? 0.07 : balance.fireInterval * heavyPenalty;
      spawnShot();
    }
    final threatDt = dt * (state.timeSlow > 0 ? 0.34 : 1);
    updateEnemies(threatDt);
    updatePlayerBullets(dt);
    updateEnemyBullets(threatDt);
    updatePickups(dt);
    updatePower(dt);
    updateFeedback(dt);
  }

  void enterRealm(int index) {
    state.realm = index;
    state.phase = 'wave';
    state.realmStage = 0;
    state.waveTime = balance.waveDuration;
    state.spawnTimer = 0.45;
    state.enemies.clear();
    state.enemyBullets.clear();
    state.bullets.clear();
    state.pickups.clear();
    state.boss = null;
    final p = state.player;
    p.x = width * 0.5;
    p.y = getBounds().floorY;
    p.vx = 0;
    p.vy = 0;
    p.jumps = 0;
    input.clear();
    audio.setRealm(index);
    audio.sfx('realm_start');
    setLoading(false);
    toast('REALM ${index + 1} · ${realms[index].short}', 2.1);
    if (index < realms.length - 1) art.loadRealm(index + 1).catchError((_) {});
  }

  // ---------- Menu actions ----------

  void openLoadout() {
    menuRefresh = overlay == OverlayKind.loadout;
    state.phase = 'loadout';
    overlay = OverlayKind.loadout;
    notifyListeners();
  }

  void cheat() {
    saved.coins = math.max(saved.coins, 999);
    saved.allAreas = true;
    saved.infiniteCoins = true;
    persist();
    audio.sfx('buy');
    openLoadout();
    toast('Koin tak terbatas & semua area terbuka');
  }

  void selectSkin(int index) {
    audio.sfx('ui_click');
    var done = false;
    Timer(const Duration(milliseconds: 150), () {
      if (!done) setLoading(true, 'Menyiapkan skin…');
    });
    art.loadSkinPreview(index).then((_) {
      done = true;
      setLoading(false);
      state.selectedSkin = index;
      saved.selectedSkin = index;
      final count = skins.length;
      final prev = (index + count - 1) % count;
      final next = (index + 1) % count;
      art.retainSkins([index, prev, next]);
      openLoadout();
      Timer(const Duration(milliseconds: 250), () {
        if (state.phase != 'loadout') return;
        for (final n in [next, prev]) {
          art.loadSkinPreview(n).catchError((_) {});
        }
      });
    }).catchError((_) {
      done = true;
      setLoading(false);
    });
  }

  void selectArea(int index) {
    if (!areaUnlocked(index)) return;
    audio.sfx('ui_click');
    state.realm = index;
    saved.selectedRealm = index;
    openLoadout();
    art.loadRealm(index).then((_) {
      if (state.phase == 'loadout' && state.realm == index) openLoadout();
    }).catchError((_) {});
  }

  void buySkin(int index) {
    final skin = skins[index];
    if (saved.unlockedSkins.contains(index) || !canAfford(skin.price)) return;
    if (!saved.infiniteCoins) saved.coins -= skin.price;
    saved.unlockedSkins = [...saved.unlockedSkins, index]..sort();
    persist();
    audio.sfx('buy');
    haptic(1);
    openLoadout();
  }

  void startRun() {
    audio.unlock();
    audio.sfx('ui_click');
    saved.selectedSkin = state.selectedSkin;
    saved.selectedRealm = state.realm;
    hideOverlay();
    setLoading(true, 'Membuka portal realm…');
    Future.wait([art.loadSkin(state.selectedSkin), art.loadRealm(state.realm)]).then((_) {
      persist();
      enterRealm(state.realm);
      if (state.realm == 0 || !saved.tutorialSeen) openTutorial(true);
    }).catchError((_) { setLoading(false); });
  }

  void resetRun() {
    audio.sfx('ui_click');
    hideOverlay();
    input.clear();
    state = freshState();
    setLoading(false);
    openLoadout();
  }

  void applySoundSettings() => audio.setMix(saved.music, saved.sfx);

  bool get muted => saved.music <= 0 && saved.sfx <= 0;

  void openTutorial(bool first, [VoidCallback? onDone]) {
    tutorialPage = 0;
    tutorialFirst = first;
    _openModal(ModalKind.tutorial, () {
      input.clear();
      if (!saved.tutorialSeen) {
        saved.tutorialSeen = true;
        persist();
      }
      onDone?.call();
    });
  }

  void tutorialGo(int page) {
    tutorialPage = page;
    notifyListeners();
  }

  void openPause() {
    if (!isPlaying || isModalOpen) return;
    input.clear();
    audio.sfx('ui_click');
    _openModal(ModalKind.pause, () => input.clear());
  }

  void pauseHelp() {
    // Swap the pause modal for the tutorial; come back to pause afterwards.
    _modalOnClose = null;
    modal = ModalKind.none;
    openTutorial(false, openPause);
  }

  void pauseMenu() {
    _modalOnClose = null;
    modal = ModalKind.none;
    confirm('Kembali ke main menu?', 'Run ini akan berakhir. Koin yang sudah dikumpulkan tetap tersimpan.', 'KELUAR', quitToMenu, openPause);
  }

  void quitToMenu() {
    saved.bestScore = math.max(saved.bestScore, state.score.floorToDouble());
    persist();
    resetRun();
  }

  void openVolume() {
    _openModal(ModalKind.volume, () {
      applySoundSettings();
      input.clear();
      persist();
    });
  }

  void setVolumeMix(double music, double sfx) {
    saved.music = music;
    saved.sfx = sfx;
    applySoundSettings();
    notifyListeners();
  }

  void confirm(String title, String text, String label, VoidCallback onConfirm, [VoidCallback? onCancel]) {
    var confirmed = false;
    confirmData = ConfirmData(title, text, label, () {
      confirmed = true;
      closeModal();
      onConfirm();
    }, onCancel);
    _openModal(ModalKind.confirm, () {
      if (!confirmed) onCancel?.call();
    });
  }

  void resetProgress() {
    confirm('Reset progres?', 'Semua koin, Gun-Mage yang dibeli, dan skor terbaik akan dihapus. Tindakan ini tidak bisa dibatalkan.', 'RESET', () {
      final keep = saved;
      saved = SaveData()
        ..tutorialSeen = keep.tutorialSeen
        ..music = keep.music
        ..sfx = keep.sfx;
      state = freshState();
      persist();
      audio.sfx('ui_click');
      setLoading(true, 'Mereset progres…');
      Future.wait([art.loadSkin(0), art.loadRealm(0)]).catchError((_) => <void>[]).then((_) {
        setLoading(false);
        openLoadout();
        toast('Progres direset');
      });
    });
  }

  SharedPreferences? _prefs;
  static const _saveKey = 'archer.gameState';

  Future<void> persist() async {
    if (booted) saved.bestScore = math.max(saved.bestScore, state.score.floorToDouble());
    try {
      await _prefs?.setString(_saveKey, jsonEncode(saved.toJson()));
    } catch (_) {}
  }

  void gameOver() {
    if (state.phase == 'gameover') return;
    state.phase = 'gameover';
    state.player.vx = 0;
    state.player.vy = 0;
    state.enemyBullets.clear();
    state.bullets.clear();
    saved.bestScore = math.max(saved.bestScore, state.score.floorToDouble());
    saved.bestRealm = math.max(saved.bestRealm, state.realm + 1);
    persist();
    audio.sfx('lose');
    overlay = OverlayKind.gameOver;
    notifyListeners();
  }

  void victory() {
    state.phase = 'victory';
    state.boss = null;
    state.enemyBullets.clear();
    saved.wins += 1;
    saved.bestRealm = 10;
    saved.bestScore = math.max(saved.bestScore, state.score.floorToDouble());
    persist();
    audio.sfx('win');
    overlay = OverlayKind.victory;
    notifyListeners();
  }

  /// App leaving the foreground: save and pause the run.
  void saveNow() {
    persist();
    openPause();
  }

  // ---------- Loop ----------

  void update(double dt) {
    if (!booted) return;
    if (isModalOpen) return;
    state.worldTime += dt;
    if (state.phase == 'wave' || state.phase == 'boss') updateActive(dt);
    if (state.phase == 'wave') updateWave(dt);
    if (state.phase == 'boss') updateBoss(dt * (state.timeSlow > 0 ? 0.45 : 1));
    if (state.phase == 'bossDefeat') {
      updateFeedback(dt);
      final boss = state.boss!;
      boss.animTime = math.min(0.49, boss.animTime + dt);
      boss.alpha = (state.bossDefeatTimer / 0.6).clamp(0.0, 1.0);
      state.bossDefeatTimer -= dt;
      if (state.bossDefeatTimer <= 0) finishBossDefeat();
    }
    audio.update(dt);
  }

  Future<void> boot() async {
    try {
      audio = ArcaneAudio(balance.musicVolume);
      final results = await Future.wait<Object?>([
        audio.init().catchError((_) {}),
        SharedPreferences.getInstance().then<Object?>((p) => p).catchError((_) => null),
        art.loadInitial(),
      ]);
      _prefs = results[1] as SharedPreferences?;
      final raw = _prefs?.getString(_saveKey);
      if (raw != null) {
        try {
          saved = SaveData.fromJson(jsonDecode(raw) as Map);
        } catch (_) {}
      }
      applySoundSettings();
      if (!areaUnlocked(saved.selectedRealm)) saved.selectedRealm = 0;
      await Future.wait([art.loadSkin(saved.selectedSkin), art.loadRealm(saved.selectedRealm)]);
      state = freshState();
      input.onEngage = audio.unlock;
      booted = true;
      setLoading(false);
      openLoadout();
      art.loadRealm(1).catchError((_) {});
    } catch (e, st) {
      debugPrint('Boot gagal: $e\n$st');
      bootFailed = true;
      setLoading(true, 'Rune gagal dimuat · muat ulang game');
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    if (booted) audio.destroy();
    super.dispose();
  }
}

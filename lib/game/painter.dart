import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'art.dart';
import 'data.dart';
import 'engine.dart';

final _rand = math.Random();

/// Deterministic per tick so a bolt holds its shape for one crackle frame.
double Function() seededRandom(int seed) {
  var value = seed & 0xFFFFFFFF;
  if (value == 0) value = 1;
  return () {
    value = (value * 1664525 + 1013904223) & 0xFFFFFFFF;
    return value / 4294967296;
  };
}

List<Offset> boltPoints(double Function() rand, double x, double top, double bottom, double spread) {
  final steps = math.max(5, ((bottom - top) / 28).round());
  final points = [Offset(x, top)];
  for (var i = 1; i <= steps; i++) {
    final sway = i == steps ? spread * 0.2 : spread;
    points.add(Offset(x + (rand() - 0.5) * sway, top + (bottom - top) * i / steps));
  }
  return points;
}

Color rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0));

class GamePainter extends CustomPainter {
  GamePainter(this.engine, Listenable repaint) : super(repaint: repaint);
  final GameEngine engine;

  ArtLibrary get art => engine.art;

  @override
  void paint(Canvas canvas, Size size) {
    if (!engine.booted) return;
    final state = engine.state;
    if (state.phase == 'loadout') return;
    final width = size.width, height = size.height;
    final time = state.worldTime;
    final realm = realms[state.realm];
    final id = pad2(state.realm + 1);
    canvas.drawRect(Offset.zero & size, Paint()..color = hex('#07101e'));
    final bgKey = state.realmStage > 0 ? 'REALM_BG_EXT_$id' : 'REALM_BG_$id';
    drawBackdrop(canvas, art.get(bgKey) ?? art.get('REALM_BG_$id'), width, height);
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height),
              [rgba(3, 8, 22, .34), rgba(3, 8, 22, .08), rgba(2, 5, 16, .68)], [0, 0.68, 1]));

    canvas.save();
    if (state.shake > 0) {
      final amount = math.min(5.0, state.shake * 24);
      canvas.translate((_rand.nextDouble() - 0.5) * amount, (_rand.nextDouble() - 0.5) * amount);
    }
    drawFloor(canvas, art, realm.floor, state.floorY, width, math.max(50, height * 0.085));
    _drawWarnings(canvas, state, time);
    _drawPickups(canvas, state, time);
    _drawEnemyProjectiles(canvas, state);
    _drawPlayerBullets(canvas, state, time);
    _drawEnemies(canvas, state, time, id);
    _drawBoss(canvas, state, id, width, height);
    _drawEffects(canvas, state);
    _drawRings(canvas, state);
    _drawPlayer(canvas, state, time, width, height);
    _drawParticles(canvas, state);
    canvas.restore();
    if (state.screenFlash > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = rgba(210, 245, 255, math.min(0.72, state.screenFlash)));
    }
  }

  void _drawPlayer(Canvas c, GameState state, double time, double width, double height) {
    final p = state.player;
    final targetHeight = math.max(48.0, math.min(74.0, math.min(height * 0.102, width * 0.168)));
    final skin = skins[state.selectedSkin];
    var key = skin.key;
    var animation = 'idle';
    var drawHeight = targetHeight;
    var animTime = time + p.animSeed;
    if (state.phase == 'gameover') {
      key = skin.finishKey;
      animation = 'death';
      drawHeight *= 1.18;
    } else if (state.phase == 'victory') {
      key = skin.finishKey;
      animation = 'victory';
      drawHeight *= 1.2;
    } else if (state.phase == 'camp') {
      key = skin.finishKey;
      animation = 'camp_idle';
      drawHeight *= 1.14;
    } else if (p.castTimer > 0) {
      animation = p.castAnimation;
      drawHeight *= animation == 'ultimate' ? 1.85 : 1.35;
      animTime = p.castElapsed;
    } else if (p.dashTimer > 0) {
      key = skin.combatKey;
      animation = 'dash';
      animTime = (0.18 - p.dashTimer) / 0.18 * 0.49;
    } else if (p.hurtFlash > 0) {
      key = skin.combatKey;
      animation = 'hurt';
      animTime = (0.55 - p.hurtFlash) / 0.55 * 0.49;
    } else if (p.shotFlash > 0) {
      key = skin.combatKey;
      animation = p.vx.abs() > 28 ? 'fire_diagonal' : 'fire_up';
      animTime = (0.14 - p.shotFlash) / 0.14 * 0.49;
    }
    final alpha = p.invulnerable > 0 && (time * 18).floor() % 2 == 1 ? 0.42 : 1.0;

    final playing = state.phase == 'wave' || state.phase == 'boss';
    final airHeight = math.max(0.0, state.floorY - p.y);
    final airborne = airHeight > 1;
    final speedRatio = math.min(1.0, p.vx.abs() / 265);
    var bob = 0.0, lean = 0.0, scaleX = 1.0, scaleY = 1.0;
    if (playing && p.castTimer <= 0 && p.dashTimer <= 0) {
      if (airborne) {
        final stretch = (-p.vy / 600).clamp(-0.6, 1.0);
        scaleY = 1 + 0.08 * stretch;
        scaleX = 1 - 0.05 * stretch;
        lean = p.facing * 0.07 * speedRatio;
      } else if (speedRatio > 0.08) {
        final stride = time * (9 + 6 * speedRatio);
        bob = -math.sin(stride).abs() * targetHeight * 0.07 * speedRatio;
        lean = p.facing * 0.1 * speedRatio;
        scaleY = 1 + math.sin(stride * 2) * 0.035 * speedRatio;
        scaleX = 1 - (scaleY - 1) * 0.6;
        if (animation == 'idle') animTime = time * (1 + 1.4 * speedRatio) + p.animSeed;
      } else {
        scaleY = 1 + math.sin(time * 2.4 + p.animSeed) * 0.012;
      }
      if (p.landTimer > 0) {
        final squash = p.landTimer / 0.14;
        scaleY *= 1 - 0.14 * squash;
        scaleX *= 1 + 0.1 * squash;
      }
    }

    final shadowScale = math.max(0.35, 1 - airHeight / 220);
    c.drawOval(
        Rect.fromCenter(center: Offset(p.x, state.floorY + 1), width: targetHeight * 0.6 * shadowScale, height: targetHeight * 0.14 * shadowScale),
        Paint()..color = rgba(0, 0, 0, 0.32 * shadowScale));

    if (p.dashTimer > 0) {
      drawAnimatedCell(c, art, 'DEFENSE_EFFECTS', 'dash_afterimage', time, p.x - targetHeight * 0.9, p.y - targetHeight * 0.68,
          targetHeight * 1.8, targetHeight * 0.7, 0.7);
    }
    c.save();
    c.translate(p.x, p.y + bob);
    c.rotate(lean);
    c.scale(scaleX, scaleY);
    drawAnchored(c, art, key, animation, animTime, 0, 0, drawHeight, flip: p.facing < 0, alpha: alpha);
    c.restore();
    if (state.power.shield > 0) _drawShield(c, p.x, p.y - targetHeight * 0.48, targetHeight * 0.62, time);
  }

  void _drawShield(Canvas c, double x, double y, double radius, double time) {
    final r = radius * (1 + math.sin(time * 5) * 0.025);
    // Canvas radial gradient started at radius*0.55; emulate with stops.
    c.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(Offset(x, y), radius, [
            rgba(49, 232, 255, 0), rgba(49, 232, 255, 0), rgba(49, 232, 255, .08), rgba(49, 232, 255, .52), rgba(205, 68, 255, .12),
          ], [0, 0.55, 0.55 + 0.45 * 0.72, 0.55 + 0.45 * 0.92, 1]));
  }

  void _drawEnemies(Canvas c, GameState state, double time, String id) {
    final realm = realms[state.realm];
    for (final e in state.enemies) {
      final reinforce = e.type >= 4;
      final elite = e.type >= 2 && e.type < 4;
      final family = e.type % 2;
      final attacking = e.attackTimer > 0;
      final animation = reinforce
          ? 'reinforce_${family == 0 ? 'a' : 'b'}_${attacking ? 'attack' : 'move'}'
          : elite
              ? 'elite_${family == 0 ? 'a' : 'b'}_${attacking ? 'attack' : 'move'}'
              : (attacking ? realm.enemyAnims[e.type][1] : realm.enemyAnims[e.type][0]);
      final sheetKey = reinforce ? 'REALM_REINFORCEMENTS_$id' : elite ? 'REALM_ELITES_$id' : 'REALM_ENEMIES_$id';
      final flash = math.min(1.0, e.hitFlash / 0.14);
      final jitter = flash > 0 ? (_rand.nextDouble() - 0.5) * e.size * 0.08 : 0.0;
      final ax = e.x + jitter, ay = e.y + e.size * 0.42;
      drawAnchored(c, art, sheetKey, animation, time + e.animSeed, ax, ay, e.size, flip: e.facing > 0);
      if (flash > 0) {
        drawAnchored(c, art, sheetKey, animation, time + e.animSeed, ax, ay, e.size, flip: e.facing > 0, alpha: flash * 0.85, mode: BlendMode.plus);
      }
      if (e.burn > 0) {
        drawAnimatedCell(c, art, 'BUFF_EFFECTS', 'fire_burn', time, e.x - e.size * 0.36, e.y - e.size * 0.35, e.size * 0.72, e.size * 0.72, 0.76);
      }
      if (e.slow > 0) {
        drawAnimatedCell(c, art, 'BUFF_EFFECTS', 'ice_shatter', time, e.x - e.size * 0.34, e.y - e.size * 0.32, e.size * 0.68, e.size * 0.68, 0.55);
      }
    }
  }

  void _drawBoss(Canvas c, GameState state, String id, double width, double height) {
    final boss = state.boss;
    if (boss == null) return;
    final h = math.max(220.0, math.min(width * 0.92, height * 0.48));
    drawAnchored(c, art, 'REALM_BOSS_$id', boss.animation, boss.animTime, boss.x, boss.y + h * 0.48, h, alpha: boss.alpha);
    final flash = math.min(1.0, boss.hitFlash / 0.1);
    if (flash > 0) {
      drawAnchored(c, art, 'REALM_BOSS_$id', boss.animation, boss.animTime, boss.x, boss.y + h * 0.48, h,
          alpha: flash * 0.55 * 0.85, mode: BlendMode.plus);
    }
  }

  void _drawRings(Canvas c, GameState state) {
    for (final ring in state.rings) {
      final progress = 1 - ring.life / ring.maxLife;
      c.drawCircle(
          Offset(ring.x, ring.y),
          ring.radius * (0.25 + progress * 0.75),
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, 6 * (1 - progress))
            ..color = ring.color.withValues(alpha: math.max(0, 1 - progress)));
    }
  }

  void _drawPlayerBullets(Canvas c, GameState state, double time) {
    for (final b in state.bullets) {
      c.save();
      c.translate(b.x, b.y);
      c.rotate(math.atan2(b.vy, b.vx) + math.pi / 2);
      final length = b.radius * 4.2;
      drawAnimatedCell(c, art, 'WEAPON_EFFECTS', 'cyan_bolt', time, -b.radius * 1.45, -length * 0.5, b.radius * 2.9, length);
      c.restore();
    }
  }

  void _drawEnemyProjectiles(Canvas c, GameState state) {
    for (final b in state.enemyBullets) {
      if (b.kind != 'orb') continue;
      final active = b.age >= b.delay;
      final r = b.radius * 1.8;
      c.drawCircle(
          Offset(b.x, b.y),
          r,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(Offset(b.x, b.y), r,
                [active ? hex('#ffffff') : hex('#ffe48d'), b.color, rgba(255, 45, 177, 0)], [0, 0.25, 1]));
    }
  }

  static final _dash = [8.0, 8.0];

  void _dashedRect(Canvas c, Rect r, Paint paint) {
    final path = Path()..addRect(r);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        c.drawPath(metric.extractPath(d, math.min(d + _dash[0], metric.length)), paint);
        d += _dash[0] + _dash[1];
      }
    }
  }

  void _drawWarnings(Canvas c, GameState state, double time) {
    for (final b in state.enemyBullets) {
      if (b.kind != 'laser' && b.kind != 'zone') continue;
      final active = b.age >= b.delay;
      if (b.lightning) {
        _drawLightning(c, b, state.floorY, time, active);
        continue;
      }
      if (b.kind == 'laser') {
        final rect = Rect.fromLTWH(b.x - b.width / 2, b.top, b.width, state.floorY - b.top);
        c.drawRect(rect, Paint()..color = active ? rgba(255, 70, 176, .7) : rgba(255, 224, 112, .15));
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 3 : 2
          ..color = active ? hex('#ffffff') : hex('#ffd96a');
        active ? c.drawRect(rect, stroke) : _dashedRect(c, rect, stroke);
      } else {
        c.drawRect(Rect.fromLTWH(b.x - b.width / 2, state.floorY - 16, b.width, 18),
            Paint()..color = active ? rgba(255, 75, 89, .6) : rgba(255, 207, 87, .16));
        c.drawRect(
            Rect.fromLTWH(b.x - b.width / 2, state.floorY - 17, b.width, 18),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = active ? hex('#ffffff') : hex('#ffd05a'));
      }
    }
  }

  void _strokeBolt(Canvas c, List<Offset> points, double width, Color color) {
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    c.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  void _drawLightning(Canvas c, EnemyShot b, double floorY, double time, bool active) {
    final top = b.top;
    final half = b.width / 2;
    final tick = (time * 24).floor();
    final add = Paint()..blendMode = BlendMode.plus;
    if (!active) {
      final charge = math.min(1.0, b.age / math.max(0.01, b.delay));
      final pulse = 0.5 + math.sin(time * 26) * 0.5;
      c.drawRect(Rect.fromLTWH(b.x - half, top, b.width, floorY - top), Paint()
        ..blendMode = BlendMode.plus
        ..color = rgba(206, 85, 255, 0.05 + charge * 0.08));
      _ellipseGlow(c, Offset(b.x, floorY - 4), half + 18, 16, Offset(b.x, floorY), half + 18,
          [rgba(235, 220, 255, 0.35 + charge * 0.4), rgba(206, 85, 255, 0.2 + pulse * 0.25 * charge), rgba(206, 85, 255, 0)], [0, 0.45, 1]);
      if (charge > 0.35 && tick % 3 == 0) {
        final rand = seededRandom(tick * 7919 + (b.x * 13).round());
        final crackle = boltPoints(rand, b.x, top, top + 40 + charge * 70, half * 0.8 + 10);
        _strokeBolt(c, crackle, 3, rgba(206, 85, 255, 0.35 * charge));
        _strokeBolt(c, crackle, 1.2, rgba(220, 250, 255, 0.6 * charge));
      }
      return;
    }
    final elapsed = b.age - b.delay;
    final fadeStart = b.activeDuration * 0.6;
    final alpha = elapsed < fadeStart ? 1.0 : math.max(0.0, 1 - (elapsed - fadeStart) / (b.activeDuration - fadeStart));
    if (elapsed < 0.1) {
      final strength = (0.1 - elapsed) * 6;
      final glowHalf = half + 24;
      c.drawRect(
          Rect.fromLTWH(b.x - glowHalf, top, glowHalf * 2, floorY - top),
          add
            ..shader = ui.Gradient.linear(Offset(b.x - glowHalf, 0), Offset(b.x + glowHalf, 0),
                [rgba(139, 118, 255, 0), rgba(235, 245, 255, strength), rgba(139, 118, 255, 0)], [0, 0.5, 1]));
    }
    final bolts = (b.width / 22).round().clamp(2, 6);
    final rand = seededRandom(tick * 7919 + (b.x * 13).round());
    for (var i = 0; i < bolts; i++) {
      final center = b.x + (i / (bolts - 1) - 0.5) * b.width * 0.7;
      final points = boltPoints(rand, center, top, floorY, math.max(18, half * 0.9));
      _strokeBolt(c, points, 10, rgba(139, 118, 255, 0.28 * alpha));
      _strokeBolt(c, points, 4.5, rgba(41, 230, 255, 0.65 * alpha));
      _strokeBolt(c, points, 1.8, rgba(255, 255, 255, 0.95 * alpha));
      for (var f = 0; f < 2; f++) {
        final from = points[1 + (rand() * (points.length - 2)).floor()];
        final dir = rand() < 0.5 ? -1 : 1;
        final fork = [from];
        for (var s = 1; s <= 3; s++) {
          fork.add(Offset(from.dx + dir * s * (10 + rand() * 12), from.dy + s * (14 + rand() * 10)));
        }
        _strokeBolt(c, fork, 4, rgba(206, 85, 255, 0.4 * alpha));
        _strokeBolt(c, fork, 1.2, rgba(230, 250, 255, 0.85 * alpha));
      }
    }
    final flicker = 0.75 + rand() * 0.25;
    _ellipseGlow(c, Offset(b.x, floorY - 6), half + 34, 26, Offset(b.x, floorY), half + 34,
        [rgba(255, 255, 255, 0.9 * alpha * flicker), rgba(41, 230, 255, 0.55 * alpha * flicker), rgba(139, 118, 255, 0)], [0, 0.35, 1]);
  }

  void _ellipseGlow(Canvas c, Offset center, double rx, double ry, Offset gradCenter, double gradR, List<Color> colors, List<double> stops) {
    c.drawOval(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(gradCenter, gradR, colors, stops));
  }

  void _drawPickups(Canvas c, GameState state, double time) {
    for (final p in state.pickups) {
      final bob = math.sin(time * 6 + p.animSeed) * 4;
      if (p.kind == 'coin') {
        final entry = art.get('COIN_SHEET');
        final frame = findFrame(entry, 'coin_${1 + (time * 10 + p.animSeed).floor() % 5}');
        drawFrameInCell(c, entry, frame, p.x - p.size / 2, p.y - p.size / 2 + bob, p.size, p.size);
      } else {
        drawAtlas(c, art, 'UI_ICON_ATLAS', p.icon, p.x - p.size / 2, p.y - p.size / 2 + bob, p.size, p.size);
      }
    }
  }

  void _drawEffects(Canvas c, GameState state) {
    for (final e in state.effects) {
      final progress = math.min(1.0, e.age / e.duration);
      final alpha = math.max(0.0, 1 - progress);
      drawAnimatedCell(c, art, e.key, e.animation, math.min(0.49, progress * 0.5), e.x - e.size / 2, e.y - e.size / 2, e.size, e.size, alpha);
    }
  }

  void _drawParticles(Canvas c, GameState state) {
    final paint = Paint()..blendMode = BlendMode.plus;
    for (final p in state.particles) {
      paint.color = p.color.withValues(alpha: math.max(0, p.life / p.maxLife));
      c.drawRect(Rect.fromLTWH(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Paints one atlas icon (HP crystal, buff icons...).
class IconPainter extends CustomPainter {
  IconPainter(this.art, this.sheet, this.name, {this.alpha = 1});
  final ArtLibrary art;
  final String sheet, name;
  final double alpha;
  @override
  void paint(Canvas canvas, Size size) {
    final entry = art.get(sheet);
    drawFrameInCell(canvas, entry, findFrame(entry, name), 0, 0, size.width, size.height, alpha);
  }

  @override
  bool shouldRepaint(covariant IconPainter old) => old.name != name || old.alpha != alpha || old.sheet != sheet;
}

/// Menu preview: the skin's idle loop, fitted to the box.
class SkinPreviewPainter extends CustomPainter {
  SkinPreviewPainter(this.art, this.skinKey, this.time) : super();
  final ArtLibrary art;
  final String skinKey;
  final double time;
  @override
  void paint(Canvas canvas, Size size) {
    drawAnimatedFit(canvas, art, skinKey, 'idle', time, 4, 4, size.width - 8, size.height - 12);
  }

  @override
  bool shouldRepaint(covariant SkinPreviewPainter old) => (old.time * 10).floor() != (time * 10).floor() || old.skinKey != skinKey;
}

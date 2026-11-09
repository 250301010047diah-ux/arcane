import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

const _sfxFiles = [
  'shoot', 'jump', 'double_jump', 'dash',
  'enemy_hit', 'enemy_die', 'enemy_shoot',
  'player_hurt', 'shield_break', 'counter',
  'coin', 'powerup', 'nova',
  'skill1', 'skill2', 'ultimate',
  'laser', 'lightning',
  'boss_appear', 'boss_attack', 'boss_hit', 'boss_defeat',
  'realm_start', 'buff_select', 'ui_click', 'buy', 'win', 'lose',
];

// bgm1: realm 1-3, bgm2: realm 4-6, bgm3: realm 7-10.
String _bgmForRealm(int index) => index <= 2 ? 'bgm1' : index <= 5 ? 'bgm2' : 'bgm3';

// Minimum seconds between repeats so rapid fire doesn't stack into noise.
const _sfxCooldown = {'shoot': 0.06, 'enemy_hit': 0.05, 'enemy_die': 0.03, 'enemy_shoot': 0.08, 'boss_hit': 0.07, 'coin': 0.04};
// Sounds that fire rapidly get more simultaneous voices.
const _voices = {'shoot': 4, 'enemy_hit': 4, 'enemy_die': 4, 'enemy_shoot': 3, 'boss_hit': 3, 'coin': 3};

const _sfxLevel = 0.85;
double _musicLevel(double volume) => (volume * 2.2).clamp(0.0, 1.0);

class ArcaneAudio {
  ArcaneAudio(this._volume);

  final _cache = AudioCache(prefix: '');
  final Map<String, AudioPool> _pools = {};
  final Map<String, double> _lastPlayed = {};
  final AudioPlayer _music = AudioPlayer();
  final Stopwatch _clock = Stopwatch()..start();
  double _volume;
  double _musicMix = 1, _sfxMix = 1;
  int _realm = 0;
  String? _musicName;
  bool _wantMusic = false;
  bool _suspended = false;
  bool _destroyed = false;

  Future<void> init() async {
    // Do not let each SFX steal Android audio focus from the BGM (that left
    // the music silent after leaving and re-entering the app).
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
    } catch (_) {}
    await _music.setReleaseMode(ReleaseMode.loop);
    _music.audioCache = _cache;
    await _applyMusicVolume();
    // Load in the background so a slow or missing file never blocks boot.
    unawaited(Future.wait(_sfxFiles.map((name) async {
      try {
        _pools[name] = await AudioPool.create(
          source: AssetSource('android-assets/audio/$name.mp3'),
          maxPlayers: _voices[name] ?? 2,
          audioCache: _cache,
        );
      } catch (e) {
        debugPrint('[audio] gagal memuat $name: $e');
      }
    })));
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void unlock() {}

  void setRealm(int value) => _realm = value;

  void setVolume(double value) {
    _volume = value;
    _applyMusicVolume();
  }

  void setMix(double music, double sfx) {
    _musicMix = music.clamp(0.0, 1.0);
    _sfxMix = sfx.clamp(0.0, 1.0);
    _applyMusicVolume();
  }

  Future<void> _applyMusicVolume() async {
    try {
      await _music.setVolume(_musicLevel(_volume) * _musicMix);
    } catch (_) {}
  }

  void sfx(String name) {
    if (_destroyed || _suspended || _sfxMix <= 0) return;
    final now = _now;
    if (now - (_lastPlayed[name] ?? -1e9) < (_sfxCooldown[name] ?? 0)) return;
    _lastPlayed[name] = now;
    final pool = _pools[name];
    if (pool == null) return;
    unawaited(pool.start(volume: _sfxLevel * _sfxMix).then((_) {}, onError: (_) {}));
  }

  /// Called every frame: keep the realm's BGM playing.
  void update(double dt) {
    if (_destroyed || _suspended) return;
    _wantMusic = true;
    final wanted = _bgmForRealm(_realm);
    if (_musicName == wanted) return;
    _musicName = wanted;
    unawaited(() async {
      try {
        await _music.stop();
        await _music.play(AssetSource('android-assets/audio/$wanted.mp3'), volume: _musicLevel(_volume) * _musicMix);
      } catch (e) {
        debugPrint('[audio] bgm $wanted gagal: $e');
      }
    }());
  }

  /// App went to background.
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    unawaited(_music.pause().catchError((_) {}));
  }

  void resume() {
    if (!_suspended) return;
    _suspended = false;
    // Restart the BGM from scratch: a plain resume() can stay silent on Android.
    if (_wantMusic) _musicName = null;
  }

  Future<void> destroy() async {
    _destroyed = true;
    await _music.dispose();
    for (final p in _pools.values) {
      await p.dispose();
    }
  }
}

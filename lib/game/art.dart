import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'data.dart';

class Frame {
  final String name;
  final Rect crop; // content ?? source
  final Offset? anchor;
  final double? surfaceY;
  Frame(this.name, this.crop, this.anchor, this.surfaceY);

  static Rect _rect(Map r) =>
      Rect.fromLTWH((r['x'] as num).toDouble(), (r['y'] as num).toDouble(), (r['w'] as num).toDouble(), (r['h'] as num).toDouble());

  factory Frame.fromJson(Map j) {
    final crop = _rect((j['content'] ?? j['source']) as Map);
    final a = j['anchor'] as Map?;
    return Frame(
      j['name'] as String,
      crop,
      a == null ? null : Offset((a['x'] as num).toDouble(), (a['y'] as num).toDouble()),
      (j['surfaceY'] as num?)?.toDouble(),
    );
  }

  Offset get anchorOrFoot => anchor ?? Offset(crop.left + crop.width / 2, crop.bottom);
}

class SheetEntry {
  final ui.Image image;
  final Map<String, Frame> frames;
  final Map<String, List<Frame>> animations;
  final Map<String, double> _maxHeight = {};
  SheetEntry(this.image, this.frames, this.animations);

  double maxHeight(String anim) => _maxHeight.putIfAbsent(anim, () {
        final list = animations[anim] ?? const [];
        return list.fold<double>(0, (m, f) => math.max(m, f.crop.height));
      });
}

const _sheetPrefixes = [
  'PLAYER_', 'WEAPON_EFFECTS', 'BUFF_EFFECTS', 'DEFENSE_EFFECTS', 'UI_ICON_ATLAS', 'REALM_FLOORS', 'COIN_SHEET',
  'REALM_ENEMIES_', 'REALM_ELITES_', 'REALM_REINFORCEMENTS_', 'REALM_BOSS_', 'SKIN_',
];

bool _isSheet(String key) => _sheetPrefixes.any(key.startsWith);

class ArtLibrary {
  final Map<String, SheetEntry> _entries = {};
  final Map<String, Future<SheetEntry>> _pending = {};

  String _fileBase(String key) => key.toLowerCase() + (_isSheet(key) ? '-transparent' : '');

  Future<SheetEntry> load(String key) {
    final existing = _entries[key];
    if (existing != null) return Future.value(existing);
    return _pending.putIfAbsent(key, () async {
      try {
        final base = _fileBase(key);
        final bytes = await rootBundle.load('android-assets/images/$base.webp');
        final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
        final image = (await codec.getNextFrame()).image;
        final frames = <String, Frame>{};
        final animations = <String, List<Frame>>{};
        if (_isSheet(key)) {
          final data = jsonDecode(await rootBundle.loadString('android-assets/json/$base.frames.json')) as Map;
          for (final f in (data['frames'] as List? ?? const [])) {
            final frame = Frame.fromJson(f as Map);
            frames[frame.name] = frame;
          }
          for (final a in (data['animations'] as List? ?? const [])) {
            animations[(a as Map)['name'] as String] = [for (final f in a['frames'] as List) Frame.fromJson(f as Map)];
          }
        }
        final entry = SheetEntry(image, frames, animations);
        _entries[key] = entry;
        return entry;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<void> loadInitial() async {
    const core = [
      'PLAYER_LOCOMOTION', 'PLAYER_COMBAT', 'PLAYER_FINISH', 'WEAPON_EFFECTS',
      'BUFF_EFFECTS', 'DEFENSE_EFFECTS', 'UI_ICON_ATLAS', 'REALM_FLOORS', 'COIN_SHEET', 'SKIN_01_SHEET',
    ];
    await Future.wait([...core.map(load), loadRealm(0)]);
  }

  Future<void> loadRealm(int index) {
    final id = pad2(index + 1);
    return Future.wait([
      for (final k in ['REALM_BG_', 'REALM_BG_EXT_', 'REALM_ENEMIES_', 'REALM_ELITES_', 'REALM_REINFORCEMENTS_', 'REALM_BOSS_']) load('$k$id'),
    ]);
  }

  Future<void> loadSkin(int index) {
    final id = pad2(index + 1);
    return Future.wait([load('SKIN_${id}_SHEET'), load('SKIN_${id}_COMBAT'), load('SKIN_${id}_FINISH')]);
  }

  Future<void> loadSkinPreview(int index) => load('SKIN_${pad2(index + 1)}_SHEET');

  bool has(String key) => _entries.containsKey(key);

  /// Drop decoded skin sheets that are not kept, to save memory while browsing.
  void retainSkins(List<int> indexes) {
    final keep = indexes.map((i) => pad2(i + 1)).toSet();
    final re = RegExp(r'^SKIN_(\d\d)_');
    _entries.removeWhere((key, value) {
      final m = re.firstMatch(key);
      if (m != null && !keep.contains(m.group(1))) {
        value.image.dispose();
        return true;
      }
      return false;
    });
  }

  SheetEntry? get(String key) => _entries[key];
}

// ---------- Drawing helpers (ports of assets.js) ----------

final Paint _imgPaint = Paint()..filterQuality = FilterQuality.medium;

Paint _alphaPaint(double alpha, [BlendMode mode = BlendMode.srcOver]) => Paint()
  ..filterQuality = FilterQuality.medium
  ..blendMode = mode
  ..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));

List<Frame> findAnimation(SheetEntry? entry, String name) => entry?.animations[name] ?? const [];
Frame? findFrame(SheetEntry? entry, String name) => entry?.frames[name];

void drawFrameInCell(Canvas c, SheetEntry? entry, Frame? frame, double x, double y, double w, double h,
    [double alpha = 1, BlendMode mode = BlendMode.srcOver]) {
  if (entry == null || frame == null || alpha <= 0) return;
  final crop = frame.crop;
  final scale = math.min(w / crop.width, h / crop.height);
  final dw = crop.width * scale, dh = crop.height * scale;
  c.drawImageRect(entry.image, crop, Rect.fromLTWH(x + (w - dw) / 2, y + (h - dh) / 2, dw, dh),
      alpha >= 1 && mode == BlendMode.srcOver ? _imgPaint : _alphaPaint(alpha, mode));
}

void drawAtlas(Canvas c, ArtLibrary art, String key, String name, double x, double y, double w, double h, [double alpha = 1]) {
  final entry = art.get(key);
  drawFrameInCell(c, entry, findFrame(entry, name), x, y, w, h, alpha);
}

int _frameIndex(double time, int length) => ((math.max(0, time) * 10).floor()) % length;

void drawAnimatedCell(Canvas c, ArtLibrary art, String key, String animation, double time, double x, double y, double w, double h,
    [double alpha = 1]) {
  final entry = art.get(key);
  final frames = findAnimation(entry, animation);
  if (frames.isEmpty) return;
  // JS used Math.floor(time*10) % len (time is never negative here).
  drawFrameInCell(c, entry, frames[_frameIndex(time, frames.length)], x, y, w, h, alpha);
}

void drawAnchored(Canvas c, ArtLibrary art, String key, String animation, double time, double ax, double ay, double targetHeight,
    {bool flip = false, double alpha = 1, BlendMode mode = BlendMode.srcOver}) {
  final entry = art.get(key);
  final frames = findAnimation(entry, animation);
  if (entry == null || frames.isEmpty || alpha <= 0) return;
  final frame = frames[_frameIndex(time, frames.length)];
  final crop = frame.crop;
  final scale = targetHeight / entry.maxHeight(animation);
  final anchor = frame.anchor ?? frame.anchorOrFoot;
  final dx = -(anchor.dx - crop.left) * scale;
  final dy = -(anchor.dy - crop.top) * scale;
  c.save();
  c.translate(ax, ay);
  if (flip) c.scale(-1, 1);
  c.drawImageRect(entry.image, crop, Rect.fromLTWH(dx, dy, crop.width * scale, crop.height * scale),
      alpha >= 1 && mode == BlendMode.srcOver ? _imgPaint : _alphaPaint(alpha, mode));
  c.restore();
}

/// Fit a whole animation into a box with one scale and a shared foot anchor.
void drawAnimatedFit(Canvas c, ArtLibrary art, String key, String animation, double time, double x, double y, double w, double h) {
  final entry = art.get(key);
  final frames = findAnimation(entry, animation);
  if (entry == null || frames.isEmpty) return;
  var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
  for (final f in frames) {
    final a = f.anchorOrFoot;
    minX = math.min(minX, f.crop.left - a.dx);
    maxX = math.max(maxX, f.crop.right - a.dx);
    minY = math.min(minY, f.crop.top - a.dy);
    maxY = math.max(maxY, f.crop.bottom - a.dy);
  }
  final scale = math.min(w / (maxX - minX), h / (maxY - minY));
  final ox = x + (w - (maxX - minX) * scale) / 2 - minX * scale;
  final oy = y + h - maxY * scale;
  final f = frames[_frameIndex(time, frames.length)];
  final a = f.anchorOrFoot;
  c.drawImageRect(entry.image, f.crop,
      Rect.fromLTWH(ox + (f.crop.left - a.dx) * scale, oy + (f.crop.top - a.dy) * scale, f.crop.width * scale, f.crop.height * scale), _imgPaint);
}

void drawFloor(Canvas c, ArtLibrary art, String frameName, double floorY, double width, double targetHeight) {
  final entry = art.get('REALM_FLOORS');
  final frame = findFrame(entry, frameName);
  if (entry == null || frame == null) return;
  final crop = frame.crop;
  final scale = targetHeight / crop.height;
  final tileW = crop.width * scale;
  final drawY = floorY - ((frame.surfaceY ?? crop.top) - crop.top) * scale;
  for (var x = -tileW * 0.25; x < width + tileW; x += tileW * 0.92) {
    c.drawImageRect(entry.image, crop, Rect.fromLTWH(x, drawY, tileW, crop.height * scale), _imgPaint);
  }
}

void drawBackdrop(Canvas c, SheetEntry? entry, double width, double height) {
  if (entry == null) return;
  final img = entry.image;
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final scale = math.max(width / iw, height / ih);
  final dw = iw * scale, dh = ih * scale;
  c.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), Rect.fromLTWH((width - dw) / 2, (height - dh) / 2, dw, dh), _imgPaint);
}

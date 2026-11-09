import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data.dart';
import 'engine.dart';
import 'painter.dart';

// ---------- Style helpers ----------

TextStyle chakra(double size, {Color color = Colors.white, FontWeight weight = FontWeight.w700, double? spacing, double? height, List<Shadow>? shadows}) =>
    GoogleFonts.chakraPetch(fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing, height: height, shadows: shadows);

TextStyle inter(double size, {Color color = const Color(0xFFF6FBFF), FontWeight weight = FontWeight.w400, double? height}) =>
    GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight, height: height);

double clampD(double min, double v, double max) => v < min ? min : (v > max ? max : v);

Color mix(Color a, double t, Color b) => Color.lerp(b, a, t)!; // color-mix(a t%, b)

String fmt(num value) {
  final s = value.floor().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return (value < 0 ? '-' : '') + buf.toString();
}

const _panelBorder = Color.fromRGBO(119, 224, 255, .42);
const _badgeGradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color.fromRGBO(12, 27, 55, .92), Color.fromRGBO(6, 12, 28, .92)]);

/// Root of the game: canvas + HUD + controls + overlays + modals.
class GameShell extends StatefulWidget {
  const GameShell({super.key, required this.engine, required this.frame});
  final GameEngine engine;
  final ValueNotifier<int> frame;
  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final _focus = FocusNode();
  bool _splashDone = false;
  final _splashStart = DateTime.now();

  GameEngine get e => widget.engine;

  static final _keyActions = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.arrowLeft: 'left', LogicalKeyboardKey.keyA: 'left',
    LogicalKeyboardKey.arrowRight: 'right', LogicalKeyboardKey.keyD: 'right',
    LogicalKeyboardKey.space: 'jump', LogicalKeyboardKey.arrowUp: 'jump', LogicalKeyboardKey.keyW: 'jump',
    LogicalKeyboardKey.shiftLeft: 'dash', LogicalKeyboardKey.shiftRight: 'dash', LogicalKeyboardKey.keyK: 'dash',
    LogicalKeyboardKey.keyJ: 'fire',
    LogicalKeyboardKey.keyU: 'skill1', LogicalKeyboardKey.keyI: 'skill2', LogicalKeyboardKey.keyO: 'ultimate',
  };

  @override
  void initState() {
    super.initState();
    e.addListener(_onEngine);
  }

  void _onEngine() {
    if (!mounted) return;
    if ((e.booted || e.bootFailed) && !_splashDone) {
      final wait = 1400 - DateTime.now().difference(_splashStart).inMilliseconds;
      Future.delayed(Duration(milliseconds: math.max(0, wait)), () {
        if (mounted) setState(() => _splashDone = true);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    e.removeListener(_onEngine);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    final confirmKey = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space;
    if (e.isModalOpen) {
      if (!isDown) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.escape) {
        e.closeModal();
      } else if (confirmKey) {
        _modalPrimary();
      }
      return KeyEventResult.handled;
    }
    if (e.overlay == OverlayKind.none) {
      final isPause = key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP;
      if (isPause && e.isPlaying) {
        if (isDown) e.openPause();
        return KeyEventResult.handled;
      }
      final action = _keyActions[key];
      if (action == null) return KeyEventResult.ignored;
      if (isDown) e.input.press(action);
      if (event is KeyUpEvent) e.input.release(action);
      return KeyEventResult.handled;
    }
    if (!isDown || isRepeat) return KeyEventResult.handled;
    if (confirmKey) {
      switch (e.overlay) {
        case OverlayKind.loadout:
          e.startRun();
        case OverlayKind.gameOver || OverlayKind.victory:
          e.resetRun();
        default:
      }
      return KeyEventResult.handled;
    }
    if (e.overlay == OverlayKind.loadout && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      final d = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      e.selectSkin((e.state.selectedSkin + d + skins.length) % skins.length);
      return KeyEventResult.handled;
    }
    final label = key.keyLabel;
    if (label.length == 1 && RegExp(r'\d').hasMatch(label)) {
      final index = (int.parse(label) + 9) % 10;
      if (e.overlay == OverlayKind.camp && index < e.campChoices.length) e.pickBuff(e.campChoices[index]);
      if (e.overlay == OverlayKind.loadout) e.selectArea(index);
    }
    return KeyEventResult.handled;
  }

  void _modalPrimary() {
    switch (e.modal) {
      case ModalKind.tutorial:
        if (e.tutorialPage == tutorialPages.length - 1) {
          e.closeModal();
        } else {
          e.tutorialGo(e.tutorialPage + 1);
        }
      default:
        e.closeModal(); // pause: resume, volume: done, confirm: cancel
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, c) {
        e.width = c.maxWidth;
        e.height = c.maxHeight;
        final shortH = c.maxHeight <= 560;
        final narrow = c.maxWidth <= 390;
        final overlayShown = e.overlay != OverlayKind.none;
        final playing = e.booted && e.isPlaying;
        final pad = clampD(6, math.min(c.maxWidth, c.maxHeight) * 0.018, 12);
        return ColoredBox(
          color: hex('#07101e'),
          child: Stack(fit: StackFit.expand, children: [
            if (e.booted) RepaintBoundary(child: CustomPaint(painter: GamePainter(e, widget.frame), size: Size.infinite)),
            if (e.booted && e.state.phase != 'loadout')
              Positioned(left: 0, right: 0, top: 0, child: Hud(engine: e, frame: widget.frame, shortH: shortH, narrow: narrow, pad: pad)),
            if (e.toastMessage != null)
              Positioned(left: 0, right: 0, top: c.maxHeight * (shortH ? 0.18 : 0.19), child: Center(child: _Toast(e.toastMessage!, e.toastSerial, c.maxWidth))),
            if (e.booted) Positioned(left: 0, right: 0, bottom: 0, child: Controls(engine: e, frame: widget.frame, shortH: shortH, width: c.maxWidth)),
            if (e.booted && overlayShown) Positioned.fill(child: OverlayLayer(engine: e, shortH: shortH)),
            if (e.booted)
              Positioned(
                top: overlayShown ? pad : pad + 96,
                right: pad,
                child: Column(children: [
                  if (playing) ...[ToolButton(icon: const _PauseIcon(), onTap: () => !e.isModalOpen ? e.openPause() : null), const SizedBox(height: 8)],
                  ToolButton(icon: _SoundIcon(muted: e.muted), muted: e.muted, onTap: () => !e.isModalOpen ? e.openVolume() : null),
                  const SizedBox(height: 8),
                  ToolButton(icon: Text('?', style: chakra(18, color: hex('#79f3ff'))), onTap: () => !e.isModalOpen ? e.openTutorial(false) : null),
                ]),
              ),
            if (e.isModalOpen) Positioned.fill(child: ModalLayer(engine: e, shortH: shortH)),
            if (e.loadingMessage != null && (_splashDone || e.bootFailed)) Positioned.fill(child: _Loading(e.loadingMessage!, c)),
            if (!_splashDone) Positioned.fill(child: _Splash(c)),
          ]),
        );
      }),
    );
  }
}

// ---------- HUD ----------

class Hud extends StatelessWidget {
  const Hud({super.key, required this.engine, required this.frame, required this.shortH, required this.narrow, required this.pad});
  final GameEngine engine;
  final ValueNotifier<int> frame;
  final bool shortH, narrow;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cq = w / 100;
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (context, _, _) {
          final s = engine.state;
          final boss = s.boss;
          final badgeFont = clampD(12, 3.4 * cq, 17);
          final timer = s.phase == 'wave' ? '${s.waveTime.ceil()}' : s.phase == 'boss' ? 'BOSS' : '—';
          Widget badge(Widget child, {Color color = const Color(0xFF79F3FF), double? minWidth}) => Container(
                constraints: BoxConstraints(minWidth: minWidth ?? 0),
                padding: EdgeInsets.symmetric(horizontal: badgeFont * (narrow ? .4 : .55), vertical: badgeFont * .34),
                decoration: BoxDecoration(gradient: _badgeGradient, border: Border.all(color: _panelBorder), borderRadius: BorderRadius.circular(999)),
                child: DefaultTextStyle(style: chakra(badgeFont, color: color, weight: FontWeight.w400, height: 1), child: child),
              );
          final activeBuffs = buffs.where((b) => (s.buffLevels[b.id] ?? 0) > 0).take(5).toList();
          final powerText = s.power.gatling > 0 ? 'GATLING' : s.power.boots > 0 ? 'PEGASUS' : s.power.shield > 0 ? 'AEGIS' : '';
          return Container(
            padding: EdgeInsets.all(pad),
            decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color.fromRGBO(3, 7, 18, .88), Color.fromRGBO(3, 7, 18, .15), Colors.transparent])),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                for (var i = 0; i < 3; i++)
                  Opacity(
                    opacity: i >= s.player.hp ? 0.22 : 1,
                    child: SizedBox(width: clampD(18, 5 * cq, 26), height: clampD(18, 5 * cq, 26),
                        child: CustomPaint(painter: IconPainter(engine.art, 'UI_ICON_ATLAS', 'hp_crystal'))),
                  ),
                SizedBox(width: clampD(5, 1.2 * cq, 10)),
                badge(Text('✦ ${fmt(s.score)}')),
                SizedBox(width: clampD(5, 1.2 * cq, 10)),
                badge(Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!narrow) SizedBox(width: 18, height: 18, child: CustomPaint(painter: IconPainter(engine.art, 'COIN_SHEET', 'coin_1'))),
                  SizedBox(width: badgeFont * .35),
                  Text(engine.coinText),
                ]), color: hex('#ffe27b')),
                SizedBox(width: narrow ? 4 : clampD(6, 1.7 * cq, 12)),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(gradient: _badgeGradient, border: Border.all(color: _panelBorder), borderRadius: BorderRadius.circular(10)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('REALM ${s.realm + 1}/10', style: chakra(clampD(9, 2.4 * cq, 12), color: hex('#73e9ff'), weight: FontWeight.w400), maxLines: 1),
                      if (!shortH)
                        Text(realms[s.realm].short,
                            style: chakra(clampD(11, 3.2 * cq, 16)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
                SizedBox(width: narrow ? 4 : clampD(6, 1.7 * cq, 12)),
                badge(Center(widthFactor: 1, child: Text(timer)), color: hex('#ffe27b'), minWidth: badgeFont * 3.2),
              ]),
              if (boss != null)
                Container(
                  width: math.min(w * 0.88, 520),
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
                  decoration: BoxDecoration(gradient: _badgeGradient, border: Border.all(color: const Color.fromRGBO(255, 95, 145, .64)), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(boss.name, style: chakra(clampD(10, 2.8 * cq, 14), color: hex('#ffd2df'))),
                      Text(s.realm == 9 ? 'FASE ${boss.hp / boss.maxHp > 0.66 ? 1 : boss.hp / boss.maxHp > 0.33 ? 2 : 3}' : '',
                          style: chakra(clampD(10, 2.8 * cq, 14), color: hex('#ffe27b'))),
                    ]),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        height: clampD(6, MediaQuery.sizeOf(context).height * 0.015, 10),
                        color: hex('#22091a'),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (boss.hp / boss.maxHp).clamp(0.0, 1.0),
                          child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [hex('#ff3d78'), hex('#ffba5a')]))),
                        ),
                      ),
                    ),
                  ]),
                ),
              if (!shortH && (activeBuffs.isNotEmpty || powerText.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final b in activeBuffs)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(gradient: _badgeGradient, border: Border.all(color: _panelBorder), borderRadius: BorderRadius.circular(999)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 18, height: 18, child: CustomPaint(painter: IconPainter(engine.art, 'UI_ICON_ATLAS', b.icon))),
                          Text(' ${s.buffLevels[b.id]}', style: inter(clampD(9, 2.5 * cq, 12), color: hex('#b9f7ff'))),
                        ]),
                      ),
                    if (powerText.isNotEmpty) Text(' $powerText', style: chakra(clampD(9, 2.4 * cq, 12), color: hex('#ffe27b'))),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast(this.message, this.serial, this.width);
  final String message;
  final int serial;
  final double width;
  @override
  Widget build(BuildContext context) {
    final size = clampD(12, 3.5 * width / 100, 18);
    return IgnorePointer(
      child: Container(
        constraints: BoxConstraints(maxWidth: math.min(width * 0.88, 520)),
        padding: EdgeInsets.symmetric(horizontal: size * .95, vertical: size * .55),
        decoration: BoxDecoration(
            color: const Color.fromRGBO(3, 10, 25, .9),
            border: Border.all(color: const Color.fromRGBO(255, 211, 88, .72)),
            borderRadius: BorderRadius.circular(999)),
        child: Text(message, textAlign: TextAlign.center, style: chakra(size, color: hex('#fff5bd'), weight: FontWeight.w600)),
      ),
    );
  }
}

// ---------- Tool buttons ----------

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.onTap, this.muted = false});
  final Widget icon;
  final VoidCallback onTap;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color.fromRGBO(12, 27, 55, .9), Color.fromRGBO(6, 12, 28, .9)]),
          border: Border.all(color: muted ? const Color.fromRGBO(255, 127, 158, .6) : const Color.fromRGBO(119, 224, 255, .55)),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .35), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: icon,
      ),
    );
  }
}

class _PauseIcon extends StatelessWidget {
  const _PauseIcon();
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 20, height: 20, child: CustomPaint(painter: _PathPainter((c, s, p) {
        c.drawRect(Rect.fromLTWH(s * 7 / 24, s * 5 / 24, s * 3.5 / 24, s * 14 / 24), p);
        c.drawRect(Rect.fromLTWH(s * 13.5 / 24, s * 5 / 24, s * 3.5 / 24, s * 14 / 24), p);
      }, hex('#79f3ff'))));
}

class _SoundIcon extends StatelessWidget {
  const _SoundIcon({required this.muted});
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final color = muted ? hex('#ff7f9e') : hex('#79f3ff');
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _PathPainter((c, s, p) {
        final k = s / 24;
        c.drawPath(Path()
          ..moveTo(4 * k, 9 * k)..lineTo(8 * k, 9 * k)..lineTo(13 * k, 5 * k)..lineTo(13 * k, 19 * k)..lineTo(8 * k, 15 * k)..lineTo(4 * k, 15 * k)..close(), p);
        final stroke = Paint()
          ..color = p.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * k
          ..strokeCap = StrokeCap.round;
        if (muted) {
          c.drawLine(Offset(16.5 * k, 9.5 * k), Offset(21.5 * k, 14.5 * k), stroke);
          c.drawLine(Offset(21.5 * k, 9.5 * k), Offset(16.5 * k, 14.5 * k), stroke);
        } else {
          c.drawArc(Rect.fromCircle(center: Offset(16 * k, 12 * k), radius: 3.5 * k), -math.pi / 2.6, math.pi / 1.3, false, stroke);
          c.drawArc(Rect.fromCircle(center: Offset(14.5 * k, 12 * k), radius: 6 * k), -math.pi / 2.6, math.pi / 1.3, false, stroke);
        }
      }, color)),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.draw, this.color);
  final void Function(Canvas c, double size, Paint paint) draw;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size.width, Paint()..color = color);
  @override
  bool shouldRepaint(covariant _PathPainter old) => old.color != color;
}

// ---------- Controls ----------

class Controls extends StatelessWidget {
  const Controls({super.key, required this.engine, required this.frame, required this.shortH, required this.width});
  final GameEngine engine;
  final ValueNotifier<int> frame;
  final bool shortH;
  final double width;

  @override
  Widget build(BuildContext context) {
    final k = shortH ? 0.62 : 0.86;
    final joySize = shortH ? 96.0 : clampD(104, width * 0.28, 132);
    return Container(
      padding: shortH ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) : const EdgeInsets.all(20),
      decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, stops: [0, 0.68, 1],
              colors: [Color.fromRGBO(2, 6, 18, .96), Color.fromRGBO(2, 6, 18, .5), Colors.transparent])),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Joystick(input: engine.input, size: joySize),
        ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (context, _, _) {
            final p = engine.state.player;
            double r(double v, double m) => (v / m).clamp(0.0, 1.0);
            return SizedBox(
              width: 208 * k,
              height: 188 * k,
              child: Stack(clipBehavior: Clip.none, children: [
                ActionButton(input: engine.input, action: 'skill1', color: hex('#b97aff'), size: 50, x: 30, y: 28, k: k, label: 'S1', icon: _Icons.bolt, cooldown: r(p.skillOneCooldown, p.skillOneMax), pulse: true, showLabel: !shortH),
                ActionButton(input: engine.input, action: 'skill2', color: hex('#7f8cff'), size: 50, x: 92, y: 6, k: k, label: 'S2', icon: _Icons.shield, cooldown: r(p.skillTwoCooldown, p.skillTwoMax), pulse: true, showLabel: !shortH),
                ActionButton(input: engine.input, action: 'ultimate', color: hex('#ffcf3f'), size: 60, x: 148, y: 16, k: k, label: 'ULT', icon: _Icons.star, cooldown: r(p.ultimateCooldown, p.ultimateMax), pulse: true, pulseSeconds: 1.2, showLabel: !shortH),
                ActionButton(input: engine.input, action: 'dash', color: hex('#a96cff'), size: 50, x: 0, y: 84, k: k, label: 'DASH', icon: _Icons.dash, cooldown: r(p.dashCooldown, 1.35), showLabel: !shortH),
                ActionButton(input: engine.input, action: 'jump', color: hex('#3fe0ff'), size: 62, x: 46, y: 122, k: k, label: 'JUMP', icon: _Icons.jump, showLabel: !shortH),
                ActionButton(input: engine.input, action: 'fire', color: hex('#ff8a3d'), size: 84, x: 124, y: 104, k: k, label: 'FIRE', icon: _Icons.fire, iconScale: .46, outerRing: true, showLabel: !shortH),
              ]),
            );
          },
        ),
      ]),
    );
  }
}

class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.input, required this.size});
  final GameInput input;
  final double size;
  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  int? _pointer;
  Offset _knob = Offset.zero;
  static const _deadzone = 0.18;

  void _track(Offset local) {
    final radius = widget.size / 2;
    final reach = radius * 0.56;
    var d = local - Offset(radius, radius);
    if (d.distance > reach) d = d * (reach / d.distance);
    final x = d.dx / reach;
    final joy = x.abs() < _deadzone ? 0.0 : x.sign * (x.abs() - _deadzone) / (1 - _deadzone);
    widget.input.setJoystick(joy);
    setState(() => _knob = d);
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    widget.input.joyX = 0;
    setState(() => _knob = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final held = _pointer != null;
    return Listener(
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _track(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _track(e.localPosition);
      },
      onPointerUp: _end,
      onPointerCancel: _end,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color.fromRGBO(101, 232, 255, .6), width: 2),
          gradient: const RadialGradient(stops: [0, 0.7], colors: [Color.fromRGBO(26, 75, 129, .55), Color.fromRGBO(11, 27, 61, .9)]),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .28), blurRadius: 14, offset: Offset(0, 5))],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(left: s * .09, child: Text('◀', style: TextStyle(color: const Color.fromRGBO(185, 247, 255, .55), fontSize: clampD(11, s * .1, 14)))),
          Positioned(right: s * .09, child: Text('▶', style: TextStyle(color: const Color.fromRGBO(185, 247, 255, .55), fontSize: clampD(11, s * .1, 14)))),
          AnimatedSlide(
            offset: Offset(_knob.dx / (s * .44), _knob.dy / (s * .44)),
            duration: held ? Duration.zero : const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Container(
              width: s * .44,
              height: s * .44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: hex('#b9f7ff'), width: 2),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
                  held ? const Color.fromRGBO(140, 245, 255, 1) : const Color.fromRGBO(101, 232, 255, .95),
                  held ? const Color.fromRGBO(40, 100, 160, 1) : const Color.fromRGBO(26, 75, 129, .95),
                ]),
                boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .4), blurRadius: 12, offset: Offset(0, 4))],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

enum _Icons { bolt, shield, star, dash, jump, fire }

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key, required this.input, required this.action, required this.color, required this.size, required this.x, required this.y,
    required this.k, required this.label, required this.icon, this.cooldown = 0, this.pulse = false, this.pulseSeconds = 1.8,
    this.iconScale = .42, this.outerRing = false, this.showLabel = true,
  });
  final GameInput input;
  final String action, label;
  final Color color;
  final double size, x, y, k, cooldown, pulseSeconds, iconScale;
  final _Icons icon;
  final bool pulse, outerRing, showLabel;
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  final Set<int> _pointers = {};
  bool get _held => _pointers.isNotEmpty;

  void _down(PointerDownEvent e) {
    _pointers.add(e.pointer);
    widget.input.press(widget.action);
    setState(() {});
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) widget.input.release(widget.action);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size * widget.k;
    final c = widget.color;
    final cooling = widget.cooldown > 0.001;
    final ready = widget.pulse && !cooling;
    final t = DateTime.now().millisecondsSinceEpoch / 1000;
    final pulse = ready ? (0.5 - 0.5 * math.cos(t * 2 * math.pi / widget.pulseSeconds)) : 0.0;
    Widget body = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: mix(c, .85, Colors.white), width: 2),
        gradient: RadialGradient(center: const Alignment(-0.32, -0.44), radius: 0.9, stops: const [0, 0.78],
            colors: [mix(c, .5, hex('#10224a')), hex('#060d22')]),
        boxShadow: [
          const BoxShadow(color: Color.fromRGBO(3, 10, 26, .6), spreadRadius: 3),
          BoxShadow(color: c.withValues(alpha: .42 + .38 * pulse), blurRadius: 16 + 10 * pulse),
        ],
      ),
      child: Stack(alignment: Alignment.center, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: size * widget.iconScale, height: size * widget.iconScale, child: CustomPaint(painter: _ButtonIconPainter(widget.icon, c))),
          if (widget.showLabel) Text(widget.label, style: chakra(9, color: Colors.white.withValues(alpha: .9), spacing: 0.7, height: 1)),
        ]),
        if (cooling) Positioned.fill(child: CustomPaint(painter: _CooldownPainter(widget.cooldown))),
      ]),
    );
    if (cooling) {
      body = ColorFiltered(colorFilter: const ColorFilter.matrix(_dimSaturate), child: body);
    }
    if (_held) {
      body = Transform.translate(offset: const Offset(0, 2), child: Transform.scale(scale: .96, child: ColorFiltered(colorFilter: const ColorFilter.matrix(_bright), child: body)));
    }
    return Positioned(
      left: widget.x * widget.k,
      top: widget.y * widget.k,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (widget.outerRing)
            Positioned(
              left: -7, top: -7, right: -7, bottom: -7,
              child: IgnorePointer(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.withValues(alpha: .45), width: 2)))),
            ),
          body,
        ]),
      ),
    );
  }
}

// saturate(.55) brightness(.85)
const List<double> _dimSaturate = [
  .85 * (0.2126 + 0.7874 * .55), .85 * (0.7152 - 0.7152 * .55), .85 * (0.0722 - 0.0722 * .55), 0, 0,
  .85 * (0.2126 - 0.2126 * .55), .85 * (0.7152 + 0.2848 * .55), .85 * (0.0722 - 0.0722 * .55), 0, 0,
  .85 * (0.2126 - 0.2126 * .55), .85 * (0.7152 - 0.7152 * .55), .85 * (0.0722 + 0.9278 * .55), 0, 0,
  0, 0, 0, 1, 0,
];
const List<double> _bright = [1.35, 0, 0, 0, 0, 0, 1.35, 0, 0, 0, 0, 0, 1.35, 0, 0, 0, 0, 0, 1, 0];

class _CooldownPainter extends CustomPainter {
  _CooldownPainter(this.ratio);
  final double ratio;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(Offset.zero & size, -math.pi / 2, ratio * math.pi * 2, true, Paint()..color = const Color.fromRGBO(2, 6, 18, .68));
  }

  @override
  bool shouldRepaint(covariant _CooldownPainter old) => old.ratio != ratio;
}

class _ButtonIconPainter extends CustomPainter {
  _ButtonIconPainter(this.icon, this.glow);
  final _Icons icon;
  final Color glow;
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final fill = Paint()..color = Colors.white;
    Paint stroke(double w) => Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glowPaint = Paint()
      ..color = glow.withValues(alpha: .8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    Path? fillPath;
    switch (icon) {
      case _Icons.bolt:
        fillPath = Path()..moveTo(13.5, 2)..lineTo(5, 13.5)..lineTo(11.2, 13.5)..lineTo(9.5, 22)..lineTo(19, 9.8)..lineTo(12.7, 9.8)..close();
      case _Icons.star:
        fillPath = Path()
          ..moveTo(12, 1.8)..lineTo(14.7, 8.3)..lineTo(21.7, 8.9)..lineTo(16.4, 13.5)..lineTo(18, 20.4)..lineTo(12, 16.8)
          ..lineTo(6, 20.4)..lineTo(7.6, 13.5)..lineTo(2.3, 8.9)..lineTo(9.3, 8.3)..close();
      case _Icons.shield:
        final p = Path()
          ..moveTo(12, 2.8)..lineTo(19.2, 6)..lineTo(19.2, 11.8)
          ..cubicTo(19.2, 16.4, 16.2, 19.8, 12, 21.4)..cubicTo(7.8, 19.8, 4.8, 16.4, 4.8, 11.8)..lineTo(4.8, 6)..close();
        final check = Path()..moveTo(8.6, 12)..lineTo(11, 14.4)..lineTo(15.6, 9.6);
        canvas.drawPath(p, glowPaint..style = PaintingStyle.stroke..strokeWidth = 2.2);
        canvas.drawPath(p, stroke(2.2));
        canvas.drawPath(check, stroke(2.2));
      case _Icons.dash:
        for (final l in [[2.5, 8.0, 9.5], [1.5, 12.0, 9.5], [2.5, 16.0, 9.5]]) {
          canvas.drawLine(Offset(l[0], l[1]), Offset(l[2], l[1]), stroke(2.2));
        }
        fillPath = Path()..moveTo(12, 5.5)..lineTo(21, 12)..lineTo(12, 18.5)..close();
      case _Icons.jump:
        final a = Path()..moveTo(5.5, 13.5)..lineTo(12, 7)..lineTo(18.5, 13.5);
        final b = Path()..moveTo(5.5, 19.5)..lineTo(12, 13)..lineTo(18.5, 19.5);
        canvas.drawPath(a, glowPaint..style = PaintingStyle.stroke..strokeWidth = 2.6);
        canvas.drawPath(a, stroke(2.6));
        canvas.drawPath(b, stroke(2.6));
      case _Icons.fire:
        canvas.drawCircle(const Offset(12, 12), 6.5, glowPaint..style = PaintingStyle.stroke..strokeWidth = 2.2);
        canvas.drawCircle(const Offset(12, 12), 6.5, stroke(2.2));
        canvas.drawCircle(const Offset(12, 12), 1.8, fill);
        for (final l in [[12.0, 1.5, 12.0, 5.5], [12.0, 18.5, 12.0, 22.5], [1.5, 12.0, 5.5, 12.0], [18.5, 12.0, 22.5, 12.0]]) {
          canvas.drawLine(Offset(l[0], l[1]), Offset(l[2], l[3]), stroke(2.2));
        }
    }
    if (fillPath != null) {
      canvas.drawPath(fillPath, glowPaint..style = PaintingStyle.fill);
      canvas.drawPath(fillPath, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ButtonIconPainter old) => old.icon != icon;
}

// ---------- Shared panel widgets ----------

class Panel extends StatelessWidget {
  const Panel({super.key, required this.children, this.maxWidth = 520, this.borderColor = const Color.fromRGBO(100, 229, 255, .55), this.padding, this.gap = 0});
  final List<Widget> children;
  final double maxWidth;
  final Color borderColor;
  final EdgeInsets? padding;
  final double gap;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = padding ?? EdgeInsets.all(size.height <= 560 ? 12 : clampD(14, math.min(size.width, size.height) * .04, 26));
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        gradient: const LinearGradient(begin: Alignment(-0.6, -1), end: Alignment(0.6, 1),
            colors: [Color.fromRGBO(13, 31, 66, .98), Color.fromRGBO(7, 9, 27, .99)]),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .45), blurRadius: 50, offset: Offset(0, 16))],
      ),
      child: SingleChildScrollView(
        padding: pad,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0 && gap > 0) SizedBox(height: gap), children[i]],
        ]),
      ),
    );
  }
}

Widget panelSmall(String text, double w) =>
    Text(text, textAlign: TextAlign.center, style: chakra(clampD(10, 2.8 * w / 100, 13), color: hex('#65eaff')));
Widget panelTitle(String text, Size s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text, textAlign: TextAlign.center, style: chakra(math.min(math.min(s.width, s.height) * .08, 34))));
Widget panelText(String text, double w) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 5, 0, 12),
    child: Text(text, textAlign: TextAlign.center, style: inter(clampD(11, 3 * w / 100, 15), color: hex('#b9c9df'))));

enum BtnStyle { primary, ghost, danger }

class PillButton extends StatefulWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.style = BtnStyle.primary, this.minWidth = 150, this.child, this.gradient, this.border, this.minHeight = 48, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final BtnStyle style;
  final double minWidth, minHeight;
  final Widget? child;
  final Gradient? gradient;
  final Color? border;
  final bool enabled;
  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width / 100;
    final (Gradient? g, Color? bg, Color border, Color fg, double fs) = switch (widget.style) {
      BtnStyle.primary => (LinearGradient(colors: [hex('#176a8d'), hex('#55308f')]), null, hex('#65eaff'), Colors.white, clampD(13, 3.5 * w, 18)),
      BtnStyle.ghost => (null, const Color.fromRGBO(8, 20, 44, .8), const Color.fromRGBO(185, 247, 255, .45), hex('#b9f7ff'), clampD(12, 3.2 * w, 16)),
      BtnStyle.danger => (LinearGradient(colors: [hex('#8d1f3d'), hex('#5a1640')]), null, hex('#ff6f8e'), Colors.white, clampD(12, 3.2 * w, 16)),
    };
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? .97 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          constraints: BoxConstraints(minWidth: widget.minWidth, minHeight: widget.minHeight),
          padding: EdgeInsets.symmetric(horizontal: fs * 1.15, vertical: fs * .6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: widget.gradient ?? g,
            color: widget.gradient == null ? bg : null,
            border: Border.all(color: widget.border ?? border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: widget.child ?? Text(widget.label, textAlign: TextAlign.center, style: chakra(fs, color: fg)),
        ),
      ),
    );
  }
}

// ---------- Overlay (menus) ----------

class OverlayLayer extends StatelessWidget {
  const OverlayLayer({super.key, required this.engine, required this.shortH});
  final GameEngine engine;
  final bool shortH;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = clampD(12, math.min(size.width, size.height) * .03, 24);
    switch (engine.overlay) {
      case OverlayKind.loadout:
        return LoadoutMenu(engine: engine, shortH: shortH);
      case OverlayKind.camp:
        return _dim(pad, _camp(context, size));
      case OverlayKind.gameOver:
        return _dim(pad, _result(size, 'RUNE CHAMBER RETAK', 'Run berakhir', engine.state.score,
            'Realm ${engine.state.realm + 1} · Terbaik ${fmt(engine.saved.bestScore)}', 'COBA LAGI'));
      case OverlayKind.victory:
        return _dim(pad, _result(size, 'SEPULUH REALM TERSELAMATKAN', 'Demon Gunsmith tumbang', engine.state.score,
            'Build magitech-mu menjadi legenda.', 'RUN BARU'));
      case OverlayKind.none:
        return const SizedBox.shrink();
    }
  }

  Widget _dim(double pad, Widget child) => Container(
        color: const Color.fromRGBO(2, 6, 18, .82),
        padding: EdgeInsets.all(pad),
        alignment: Alignment.center,
        child: child,
      );

  Widget _result(Size s, String small, String title, double score, String text, String button) => Panel(children: [
        panelSmall(small, s.width),
        panelTitle(title, s),
        Text(fmt(score), textAlign: TextAlign.center,
            style: chakra(math.min(math.min(s.width * .16, s.height * .13), 72), color: hex('#ffe475'), height: 1)),
        panelText(text, s.width),
        Center(child: PillButton(label: button, onTap: engine.resetRun)),
      ]);

  Widget _camp(BuildContext context, Size s) {
    final w = s.width / 100;
    final iconSize = shortH ? 46.0 : clampD(48, 14 * w, 70);
    return Panel(children: [
      panelSmall('RESTING CAMP', s.width),
      panelTitle('Pilih satu rune', s),
      panelText('Buff ini bertahan sampai run berakhir.', s.width),
      for (final buff in engine.campChoices) ...[
        GestureDetector(
          onTap: () => engine.pickBuff(buff),
          child: Container(
            constraints: BoxConstraints(minHeight: shortH ? 56 : 64),
            padding: shortH ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5) : EdgeInsets.all(clampD(7, math.min(s.width, s.height) * .018, 11)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color.fromRGBO(142, 112, 255, .58)),
              gradient: const LinearGradient(colors: [Color.fromRGBO(30, 25, 78, .95), Color.fromRGBO(12, 31, 58, .95)]),
            ),
            child: Row(children: [
              SizedBox(width: iconSize, height: iconSize, child: CustomPaint(painter: IconPainter(engine.art, 'UI_ICON_ATLAS', buff.icon))),
              SizedBox(width: clampD(8, 2.4 * w, 14)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(buff.name, style: chakra(clampD(13, 3.6 * w, 18), color: hex('#fff1a8'))),
                  Text('Tier ${(engine.state.buffLevels[buff.id] ?? 0) + 1}/${buff.max}', style: inter(clampD(9, 2.5 * w, 12), color: hex('#6fe8ff'))),
                  Text(buff.description[math.min(engine.state.buffLevels[buff.id] ?? 0, buff.description.length - 1)],
                      style: inter(clampD(10, 2.8 * w, 14), color: hex('#c8d4e6'))),
                ]),
              ),
            ]),
          ),
        ),
        SizedBox(height: shortH ? 6 : clampD(8, math.min(s.width, s.height) * .02, 12)),
      ],
    ]);
  }
}

class LoadoutMenu extends StatefulWidget {
  const LoadoutMenu({super.key, required this.engine, required this.shortH});
  final GameEngine engine;
  final bool shortH;
  @override
  State<LoadoutMenu> createState() => _LoadoutMenuState();
}

class _LoadoutMenuState extends State<LoadoutMenu> with TickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 36))..repeat();
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  final _scroll = ScrollController();
  final _start = DateTime.now();

  GameEngine get e => widget.engine;

  @override
  void dispose() {
    _anim.dispose();
    _intro.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _rise(int index, Widget child) {
    final begin = (index.clamp(0, 7) * 0.05 + (index >= 3 ? 0.01 : 0)) / 0.9;
    final curve = CurvedAnimation(parent: _intro, curve: Interval(begin.clamp(0, .5), (begin + .55).clamp(0, 1), curve: const Cubic(.2, .8, .2, 1)));
    return AnimatedBuilder(
      animation: curve,
      builder: (context, c) => Opacity(opacity: curve.value, child: Transform.translate(offset: Offset(0, 12 * (1 - curve.value)), child: c)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width / 100;
    final shortH = widget.shortH;
    final state = e.state;
    final skin = skins[state.selectedSkin];
    final realm = realms[state.realm];
    final realmA = realm.colors[0], realmB = realm.colors[1];
    final owned = e.saved.unlockedSkins.contains(skin.id);
    final maxPower = skins.map((s) => s.power).reduce(math.max);
    final bg = e.art.get('REALM_BG_${pad2(state.realm + 1)}');
    final pad = clampD(12, math.min(size.width, size.height) * .03, 24);
    final gap = clampD(8, math.min(size.width, size.height) * .02, 13);

    final children = <Widget>[
      // Hero
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ROGUELITE · 10 REALM · 20 GUN-MAGE', style: chakra(clampD(8, 2.2 * w, 10), color: hex('#65eaff'), spacing: 2, height: 1)),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final shift = (_anim.value * 36 / 5) % 1;
                final fs = shortH ? 24.0 : math.min(math.min(8.6 * w, size.height * .09), 40.0);
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: 'ARCANE ',
                      style: chakra(fs, height: 1, spacing: fs * .03, shadows: const [Shadow(color: Color.fromRGBO(101, 234, 255, .35), blurRadius: 12)]).copyWith(
                        foreground: Paint()
                          ..shader = LinearGradient(
                            colors: const [Colors.white, Color(0xFF9DF6FF), Colors.white, Color(0xFFC8A2FF), Colors.white],
                            stops: const [0, .35, .5, .7, 1],
                            begin: Alignment(-1 + shift * 2.5 - 1.25, 0),
                            end: Alignment(1.5 + shift * 2.5 - 1.25, 0),
                            tileMode: TileMode.mirror,
                          ).createShader(Rect.fromLTWH(0, 0, fs * 4, fs)),
                      ),
                    ),
                    TextSpan(text: 'SIEGE', style: chakra(fs, color: hex('#ffd767'), height: 1, spacing: fs * .03)),
                  ])),
                );
              },
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: hex('#d5b34c')),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color.fromRGBO(80, 56, 10, .55), Color.fromRGBO(30, 20, 4, .55)]),
          ),
          child: Text('◆ ${e.coinText}', style: chakra(clampD(12, 3.4 * w, 16), color: hex('#ffe788'))),
        ),
      ]),
      // Stats
      Row(children: [
        for (final (i, (label, value)) in [
          ('SKOR TERBAIK', fmt(e.saved.bestScore)),
          ('REALM TERJAUH', '${math.min(10, e.saved.bestRealm)}/10'),
          ('MENANG', fmt(e.saved.wins)),
        ].indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(shortH ? 4 : 6),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color.fromRGBO(101, 234, 255, .22)),
                  color: const Color.fromRGBO(6, 14, 34, .75)),
              child: Column(children: [
                Text(label, style: chakra(clampD(7, 2 * w, 10), color: hex('#7f97b8'), spacing: .8, height: 1), maxLines: 1),
                const SizedBox(height: 2),
                Text(value, style: chakra(clampD(13, 3.8 * w, 18), height: 1.1)),
              ]),
            ),
          ),
        ],
      ]),
      // Showcase
      _showcase(size, skin, owned, maxPower),
      // Skin chips
      LayoutBuilder(builder: (context, c) {
        final chipW = ((c.maxWidth - 9 * 4) / 10).floorToDouble();
        return Wrap(spacing: 4, runSpacing: 4, children: [
          for (final item in skins) _skinChip(item, chipW, shortH),
        ]);
      }),
      // Area title
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '◆ ', style: chakra(12, color: hex('#65eaff'))),
          TextSpan(text: 'Pilih area awal', style: chakra(15, spacing: .45)),
        ])),
        const SizedBox(width: 8),
        Expanded(child: Text('Capai realm untuk membukanya', textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(clampD(8, 2.2 * w, 11), color: hex('#6eeaff')))),
      ]),
      LayoutBuilder(builder: (context, c) {
        final cell = ((c.maxWidth - 4 * 5) / 5).floorToDouble();
        return Wrap(spacing: 5, runSpacing: 5, children: [for (var i = 0; i < realms.length; i++) _areaButton(i, cell, w, shortH)]);
      }),
      // Start
      _StartButton(
        realmA: realmA,
        realmB: realmB,
        minHeight: shortH ? 46 : 58,
        title: '▶ MASUK REALM ${state.realm + 1} · ${realm.short}',
        sub: 'BOSS · ${realm.boss}'.toUpperCase(),
        w: w,
        onTap: e.startRun,
      ),
      Center(
        child: GestureDetector(
          onTap: e.cheat,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color.fromRGBO(185, 247, 255, .45)),
                color: const Color.fromRGBO(8, 20, 44, .8)),
            child: Text('◆ KOIN 999+ (TAK TERBATAS) + BUKA SEMUA AREA', style: chakra(clampD(11, 2.8 * w, 13), color: hex('#b9f7ff'))),
          ),
        ),
      ),
      Center(
        child: GestureDetector(
          onTap: e.resetProgress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('Reset progres',
                style: inter(clampD(11, 2.8 * w, 13), color: hex('#ff8fa8')).copyWith(decoration: TextDecoration.underline, decorationColor: hex('#ff8fa8'))),
          ),
        ),
      ),
    ];

    if (e.menuRefresh) _intro.value = 1;

    return Stack(fit: StackFit.expand, children: [
      // Backdrop: realm art + tinted gradients.
      ColoredBox(color: hex('#02060f')),
      if (bg != null) RawImage(image: bg.image, fit: BoxFit.cover),
      Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color.fromRGBO(2, 6, 18, .6), Color.fromRGBO(2, 6, 18, .9)])),
      ),
      Container(decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(0, -1), radius: 1.2, colors: [realmB.withValues(alpha: 0), realmB.withValues(alpha: 0)]))),
      Container(
        decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, -1), radius: .9, stops: const [0, .6], colors: [realmA.withValues(alpha: .3), realmA.withValues(alpha: 0)])),
      ),
      Container(
        decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, 1), radius: .8, stops: const [0, .65], colors: [realmB.withValues(alpha: .28), realmB.withValues(alpha: 0)])),
      ),
      AnimatedBuilder(animation: _anim, builder: (context, _) => CustomPaint(painter: _SparksPainter(_anim.value * 2))),
      Padding(
        padding: EdgeInsets.all(pad),
        child: Center(
          child: _menuPanel(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.all(shortH ? 12 : clampD(14, math.min(size.width, size.height) * .04, 26)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), _rise(i, children[i])],
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _menuPanel({required Widget child}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color.fromRGBO(140, 120, 255, .6)),
        gradient: const LinearGradient(begin: Alignment(-0.5, -1), end: Alignment(0.5, 1),
            colors: [Color.fromRGBO(14, 30, 68, .97), Color.fromRGBO(6, 8, 26, .99)]),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(0, 0, 0, .55), blurRadius: 60, offset: Offset(0, 20)),
          BoxShadow(color: Color.fromRGBO(120, 80, 255, .2), blurRadius: 60),
        ],
      ),
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const RadialGradient(center: Alignment(0, -1.16), radius: .9, stops: [0, .6],
                    colors: [Color.fromRGBO(120, 70, 255, .3), Color.fromRGBO(120, 70, 255, 0)]),
              ),
            ),
          ),
        ),
        child,
        Positioned(top: 7, left: 7, child: IgnorePointer(child: CustomPaint(size: const Size(26, 26), painter: _CornerPainter(hex('#65eaff'), false)))),
        Positioned(top: 7, right: 7, child: IgnorePointer(child: CustomPaint(size: const Size(26, 26), painter: _CornerPainter(hex('#c8a2ff'), true)))),
      ]),
    );
  }

  Widget _showcase(Size size, Skin skin, bool owned, double maxPower) {
    final w = size.width / 100;
    final color = skin.color;
    final affordable = e.canAfford(skin.price);
    final copy = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: owned ? const Color.fromRGBO(60, 230, 160, .16) : const Color.fromRGBO(255, 200, 80, .14),
          border: Border.all(color: owned ? const Color.fromRGBO(60, 230, 160, .45) : const Color.fromRGBO(255, 200, 80, .45)),
        ),
        child: Text(owned ? '✓ DIMILIKI' : 'UJI GRATIS', style: chakra(clampD(8, 2.2 * w, 10), color: owned ? hex('#6dffc0') : hex('#ffe27b'), spacing: 1, height: 1.4)),
      ),
      const SizedBox(height: 5),
      Text(skin.name, style: chakra(clampD(17, 5 * w, 26), height: 1.05, shadows: [Shadow(color: color.withValues(alpha: .7), blurRadius: 14)])),
      const SizedBox(height: 5),
      Container(
        height: 16,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color.fromRGBO(255, 255, 255, .14)),
            color: const Color.fromRGBO(2, 6, 18, .8)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(children: [
            FractionallySizedBox(
              widthFactor: skin.power / maxPower,
              child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [hex('#2bd8ff'), color, hex('#ffd767')]))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('POWER ×${skin.power.toStringAsFixed(2)}',
                  style: chakra(10, height: 1.4, shadows: const [Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1))])),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 5),
      for (final (label, name, ult) in [('S1', skin.skillOne, false), ('S2', skin.skillTwo, false), ('ULT', skin.ultimate, true)])
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Container(
              width: 26,
              padding: const EdgeInsets.symmetric(vertical: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: ult ? const Color.fromRGBO(255, 200, 80, .28) : const Color.fromRGBO(120, 90, 255, .3)),
              child: Text(label, style: chakra(9, color: ult ? hex('#ffe27b') : hex('#d9c8ff'), height: 1.3)),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(clampD(9, 2.5 * w, 12), color: hex('#c8d5e8')))),
          ]),
        ),
      if (!owned) ...[
        const SizedBox(height: 2),
        GestureDetector(
          onTap: affordable ? () => e.buySkin(skin.id) : null,
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: affordable ? hex('#e0b94a') : const Color.fromRGBO(255, 220, 103, .3)),
              gradient: affordable ? LinearGradient(colors: [hex('#8a5d0e'), hex('#c2902a')]) : null,
              color: affordable ? null : const Color.fromRGBO(70, 50, 10, .45),
              boxShadow: affordable ? const [BoxShadow(color: Color.fromRGBO(255, 200, 80, .25), blurRadius: 14)] : null,
            ),
            child: Text(affordable ? 'BELI · ◆ ${fmt(skin.price)}' : 'BUTUH ◆ ${fmt(skin.price)}',
                style: chakra(clampD(11, 3 * w, 13), color: affordable ? hex('#fff6d0') : hex('#b9a774'), height: 1)),
          ),
        ),
      ],
    ]);

    final stage = AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final s = c.maxWidth;
        return Stack(clipBehavior: Clip.none, children: [
          // Rotating rune ring.
          Positioned(
            left: s * .08, right: s * .08, top: s * .04, bottom: s * .14,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(painter: _RuneRingPainter(color, _anim.value * 36 / 7)),
            ),
          ),
          // Pedestal glow.
          Positioned(
            left: s * .14, right: s * .14, bottom: s * .02, height: s * .12,
            child: Opacity(
              opacity: .8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(s * .36, s * .06)),
                  gradient: RadialGradient(stops: const [0, .55, 1], colors: [mix(color, .8, Colors.white), color.withValues(alpha: .35), color.withValues(alpha: 0)]),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: .45), blurRadius: 22)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: SkinPreviewPainter(e.art, skin.key, DateTime.now().difference(_start).inMilliseconds / 1000),
              ),
            ),
          ),
          Positioned(
            left: 0, top: s / 2 - 22,
            child: _navButton('‹', color, () => e.selectSkin((skin.id - 1 + skins.length) % skins.length)),
          ),
          Positioned(
            right: 0, top: s / 2 - 22,
            child: _navButton('›', color, () => e.selectSkin((skin.id + 1) % skins.length)),
          ),
          Positioned(
            top: 2, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: const Color.fromRGBO(4, 10, 26, .8)),
                child: Text('#${pad2(skin.id + 1)}/${skins.length}', style: chakra(10, color: color, spacing: .8, height: 1.5)),
              ),
            ),
          ),
        ]);
      }),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .55)),
        gradient: const LinearGradient(begin: Alignment(-1, -0.4), end: Alignment(1, 0.4),
            colors: [Color.fromRGBO(9, 18, 42, .95), Color.fromRGBO(6, 12, 30, .95)]),
        boxShadow: [BoxShadow(color: color.withValues(alpha: .14), blurRadius: 24)],
      ),
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: RadialGradient(center: const Alignment(-0.52, 0.2), radius: .9, stops: const [0, .7],
                    colors: [color.withValues(alpha: .26), color.withValues(alpha: 0)]),
              ),
            ),
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          final stageW = widget.shortH ? 150.0 : c.maxWidth * .52;
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(width: stageW, child: stage),
            const SizedBox(width: 10),
            Expanded(child: copy),
          ]);
        }),
      ]),
    );
  }

  Widget _navButton(String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .6)),
            color: const Color.fromRGBO(4, 10, 26, .78),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 10)],
          ),
          child: Text(label, style: chakra(24, height: 1)),
        ),
      );

  Widget _skinChip(Skin item, double width, bool shortH) {
    final has = e.saved.unlockedSkins.contains(item.id);
    final selected = item.id == e.state.selectedSkin;
    final c = item.color;
    return GestureDetector(
      onTap: () {
        if (!selected) e.selectSkin(item.id);
      },
      child: Opacity(
        opacity: selected || has ? 1 : .62,
        child: Container(
          width: width,
          height: shortH ? 26 : 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? c : c.withValues(alpha: .4)),
            color: selected ? c : has ? Color.alphaBlend(c.withValues(alpha: .14), const Color.fromRGBO(6, 14, 34, .9)) : const Color.fromRGBO(6, 14, 34, .85),
            boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: .6), blurRadius: 12)] : null,
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Center(child: Text('${item.id + 1}', style: chakra(12, color: selected ? hex('#07101e') : mix(c, .8, Colors.white), height: 1))),
            if (!has)
              Positioned(
                top: 3 - 1, right: 3 - 1,
                child: Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: hex('#ffd767'))),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _areaButton(int index, double width, double w, bool shortH) {
    final item = realms[index];
    final open = e.areaUnlocked(index);
    final selected = index == e.state.realm;
    final a = item.colors[0], b = item.colors[1];
    Widget cell = Container(
      width: width,
      constraints: BoxConstraints(minHeight: shortH ? 38 : 46),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selected ? hex('#ffe16d') : a.withValues(alpha: .4)),
        gradient: LinearGradient(begin: const Alignment(-0.5, -1), end: const Alignment(0.5, 1), colors: [
          Color.alphaBlend(a.withValues(alpha: .26), const Color.fromRGBO(8, 20, 44, .92)),
          Color.alphaBlend(b.withValues(alpha: .22), const Color.fromRGBO(8, 14, 34, .95)),
        ]),
        boxShadow: selected ? [BoxShadow(color: hex('#ffe16d'), spreadRadius: 1), BoxShadow(color: a.withValues(alpha: .5), blurRadius: 14)] : null,
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(open ? '${index + 1}' : '🔒',
            style: chakra(clampD(13, 3.2 * w, 16), color: a, shadows: [Shadow(color: a.withValues(alpha: .6), blurRadius: 8)], height: 1.15)),
        Text(item.short,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(clampD(7, 1.9 * w, 10), color: selected ? hex('#fff1a7') : hex('#d9eaff'))),
      ]),
    );
    if (!open) {
      cell = Opacity(
        opacity: .4,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .2 + .8 * .2126, .8 * .7152, .8 * .0722, 0, 0,
            .8 * .2126, .2 + .8 * .7152, .8 * .0722, 0, 0,
            .8 * .2126, .8 * .7152, .2 + .8 * .0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: cell,
        ),
      );
    }
    return GestureDetector(onTap: open ? () => e.selectArea(index) : null, child: cell);
  }
}

class _StartButton extends StatefulWidget {
  const _StartButton({required this.realmA, required this.realmB, required this.minHeight, required this.title, required this.sub, required this.w, required this.onTap});
  final Color realmA, realmB;
  final double minHeight, w;
  final String title, sub;
  final VoidCallback onTap;
  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 7200))..repeat();
  bool _down = false;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final glowT = 0.5 - 0.5 * math.cos(_c.value * 3 * 2 * math.pi); // 2.4s cycle
          final sweep = (_c.value * 2) % 1; // 3.6s cycle
          final sweepPos = sweep < .55 ? -0.4 : -0.4 + (sweep - .55) / .45 * 1.7;
          return Transform.translate(
            offset: Offset(0, _down ? 1 : 0),
            child: Transform.scale(
              scale: _down ? .99 : 1,
              child: Container(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: mix(widget.realmA, .7, Colors.white)),
                  gradient: LinearGradient(colors: [widget.realmA, widget.realmB]),
                  boxShadow: [
                    BoxShadow(
                        color: Color.lerp(widget.realmA.withValues(alpha: .45), const Color.fromRGBO(101, 234, 255, .45), glowT)!,
                        blurRadius: 26 + 4 * glowT,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LayoutBuilder(builder: (context, c) {
                    return Stack(children: [
                      Positioned(
                        left: c.maxWidth * sweepPos,
                        top: 0,
                        bottom: 0,
                        width: c.maxWidth * .3,
                        child: Transform(
                          transform: Matrix4.skewX(-0.31),
                          child: const DecoratedBox(
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [Colors.transparent, Color.fromRGBO(255, 255, 255, .5), Colors.transparent]))),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(widget.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: chakra(clampD(14, 3.9 * widget.w, 19), spacing: .6)),
                            const SizedBox(height: 2),
                            Text(widget.sub, textAlign: TextAlign.center,
                                style: chakra(clampD(9, 2.6 * widget.w, 11), color: Colors.white.withValues(alpha: .8), weight: FontWeight.w600, spacing: 1.2, height: 1.2)),
                          ]),
                        ),
                      ),
                    ]);
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.color, this.right);
  final Color color;
  final bool right;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final path = right
        ? (Path()..moveTo(0, 1)..lineTo(s - 12, 1)..arcToPoint(Offset(s - 1, 12), radius: const Radius.circular(11))..lineTo(s - 1, s))
        : (Path()..moveTo(1, s)..lineTo(1, 12)..arcToPoint(const Offset(12, 1), radius: const Radius.circular(11))..lineTo(s, 1));
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => false;
}

class _RuneRingPainter extends CustomPainter {
  _RuneRingPainter(this.color, this.turns);
  final Color color;
  final double turns;
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final center = size.center(Offset.zero);
    final ringR = r * 0.91;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..shader = SweepGradient(
        transform: GradientRotation(turns * 2 * math.pi - math.pi / 2),
        colors: [Colors.transparent, color.withValues(alpha: .75), Colors.transparent, color.withValues(alpha: .5), Colors.transparent],
        stops: const [0, .17, .35, .55, .75],
      ).createShader(Rect.fromCircle(center: center, radius: ringR));
    canvas.drawCircle(center, ringR, paint);
  }

  @override
  bool shouldRepaint(covariant _RuneRingPainter old) => old.turns != turns || old.color != color;
}

class _SparksPainter extends CustomPainter {
  _SparksPainter(this.cycles);
  final double cycles; // full 260px rises (18s each)
  static const _sparks = [
    (0.12, 0.18, 1.5, Color(0xFF9DF6FF)), (0.28, 0.62, 1.0, Color(0xFFC8A2FF)), (0.46, 0.34, 2.0, Color(0xFFFFD767)),
    (0.63, 0.78, 1.0, Color(0xFF9DF6FF)), (0.81, 0.22, 1.5, Color(0xFFC8A2FF)), (0.90, 0.58, 1.0, Color(0xFF9DF6FF)),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 260.0;
    final offset = (cycles % 1) * tile;
    final paint = Paint();
    for (var ty = -tile; ty < size.height + tile; ty += tile) {
      for (var tx = 0.0; tx < size.width; tx += tile) {
        for (final (x, y, r, c) in _sparks) {
          paint.color = c.withValues(alpha: .7);
          canvas.drawCircle(Offset(tx + x * tile, ty + y * tile - offset), r, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparksPainter old) => old.cycles != cycles;
}

// ---------- Modals ----------

const tutorialPages = [
  (title: 'Selamat datang, Gun-Mage!', rows: <(String, String)>[],
      text: 'Bertahanlah dari gelombang musuh, kalahkan boss di setiap realm, dan taklukkan 10 realm sampai Singgasana Iblis.'),
  (title: 'Bergerak', rows: [
    ('◀ ▶', 'Geser joystick untuk berjalan ke kiri dan kanan.'),
    ('JUMP', 'Lompat. Tekan lagi di udara untuk lompat ganda.'),
    ('DASH', 'Melesat cepat dan kebal sesaat.'),
  ], text: ''),
  (title: 'Menyerang', rows: [
    ('FIRE', 'Tahan untuk terus menembak ke atas.'),
    ('S1 · S2', 'Skill khusus tiap Gun-Mage. Tunggu cooldown-nya.'),
    ('ULT', 'Serangan pamungkas yang menghantam semua musuh.'),
  ], text: ''),
  (title: 'Bertahan hidup', rows: [
    ('❤ ×3', 'Kamu punya 3 nyawa. Hindari peluru dan musuh yang jatuh.'),
    ('⚠', 'Laser dan petir selalu diberi tanda dulu. Segera menjauh!'),
    ('◆', 'Kumpulkan koin untuk membeli Gun-Mage yang lebih kuat.'),
  ], text: ''),
  (title: 'Power-up & rune', rows: [
    ('Gatling', 'Tembakan super cepat selama 10 detik.'),
    ('Pegasus', 'Lari dan lompat lebih tinggi selama 10 detik.'),
    ('Aegis', 'Perisai yang menahan satu serangan.'),
    ('Nova', 'Ledakan yang membersihkan musuh di layar.'),
  ], text: 'Setelah boss kalah, pilih satu rune di camp untuk memperkuat run-mu.'),
];

class ModalLayer extends StatelessWidget {
  const ModalLayer({super.key, required this.engine, required this.shortH});
  final GameEngine engine;
  final bool shortH;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    final gap = clampD(8, math.min(s.width, s.height) * .02, 14);
    Widget actions(List<Widget> buttons) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: buttons),
        );
    Widget panel;
    switch (engine.modal) {
      case ModalKind.pause:
        panel = Panel(maxWidth: 460, gap: gap, borderColor: const Color.fromRGBO(140, 120, 255, .6), children: [
          panelSmall('PERMAINAN DIJEDA', s.width),
          panelTitle('Jeda', s),
          panelText('Tarik napas, Gun-Mage. Realm menunggumu.', s.width),
          Center(
            child: SizedBox(
              width: math.min(280, s.width),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PillButton(label: 'LANJUTKAN', onTap: engine.closeModal),
                const SizedBox(height: 8),
                PillButton(label: 'TUTORIAL', style: BtnStyle.ghost, onTap: engine.pauseHelp),
                const SizedBox(height: 8),
                PillButton(label: 'MAIN MENU', style: BtnStyle.danger, onTap: engine.pauseMenu),
              ]),
            ),
          ),
        ]);
      case ModalKind.tutorial:
        final page = engine.tutorialPage;
        final data = tutorialPages[page];
        final last = page == tutorialPages.length - 1;
        final first = engine.tutorialFirst;
        panel = Panel(maxWidth: 460, gap: gap, children: [
          panelSmall('TUTORIAL · ${page + 1}/${tutorialPages.length}', s.width),
          panelTitle(data.title, s),
          for (final (label, text) in data.rows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color.fromRGBO(119, 224, 255, .28)),
                  color: const Color.fromRGBO(7, 16, 38, .8)),
              child: Row(children: [
                SizedBox(width: 62, child: Text(label, textAlign: TextAlign.center, style: chakra(clampD(11, 3 * s.width / 100, 14), color: hex('#fff1a8')))),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: inter(clampD(11, 3 * s.width / 100, 14), color: hex('#d4e2f3'), height: 1.35))),
              ]),
            ),
          if (data.text.isNotEmpty) Text(data.text, textAlign: TextAlign.center, style: inter(clampD(11, 3 * s.width / 100, 15), color: hex('#b9c9df'))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < tutorialPages.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == page ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4), color: i == page ? hex('#65eaff') : const Color.fromRGBO(185, 247, 255, .25)),
              ),
          ]),
          actions([
            page > 0
                ? PillButton(label: 'KEMBALI', style: BtnStyle.ghost, minWidth: 110, onTap: () => engine.tutorialGo(page - 1))
                : PillButton(label: first ? 'LEWATI' : 'TUTUP', style: BtnStyle.ghost, minWidth: 110, onTap: engine.closeModal),
            PillButton(
              label: last ? (first ? 'MULAI MAIN' : 'MENGERTI') : 'LANJUT',
              minWidth: 130,
              onTap: () => last ? engine.closeModal() : engine.tutorialGo(page + 1),
            ),
          ]),
        ]);
      case ModalKind.volume:
        panel = Panel(maxWidth: 460, gap: gap, children: [
          panelSmall('PENGATURAN', s.width),
          panelTitle('Volume', s),
          _volumeRow('Musik', engine.saved.music, (v) => engine.setVolumeMix(v, engine.saved.sfx), s),
          _volumeRow('Efek suara', engine.saved.sfx, (v) => engine.setVolumeMix(engine.saved.music, v), s),
          actions([PillButton(label: 'SELESAI', minWidth: 130, onTap: engine.closeModal)]),
        ]);
      case ModalKind.confirm:
        final data = engine.confirmData!;
        panel = Panel(maxWidth: 460, gap: gap, children: [
          panelSmall('KONFIRMASI', s.width),
          panelTitle(data.title, s),
          panelText(data.text, s.width),
          actions([
            PillButton(label: 'BATAL', minWidth: 130, onTap: engine.closeModal),
            PillButton(label: data.confirmLabel, style: BtnStyle.danger, minWidth: 110, onTap: data.onConfirm),
          ]),
        ]);
      case ModalKind.none:
        return const SizedBox.shrink();
    }
    return Container(
      color: const Color.fromRGBO(2, 6, 18, .86),
      padding: EdgeInsets.all(clampD(12, math.min(s.width, s.height) * .03, 24)),
      alignment: Alignment.center,
      child: panel,
    );
  }

  Widget _volumeRow(String label, double value, ValueChanged<double> onChanged, Size s) {
    final fs = clampD(12, 3.2 * s.width / 100, 15);
    return Row(children: [
      SizedBox(width: fs * 6.5, child: Text(label, style: inter(fs, color: hex('#d4e2f3')))),
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(activeTrackColor: hex('#65eaff'), thumbColor: hex('#65eaff'), inactiveTrackColor: const Color.fromRGBO(185, 247, 255, .25)),
          child: Slider(value: value, divisions: 20, onChanged: onChanged),
        ),
      ),
      SizedBox(width: fs * 3.2, child: Text('${(value * 100).round()}%', textAlign: TextAlign.end, style: chakra(fs, color: hex('#ffe27b')))),
    ]);
  }
}

// ---------- Loading & splash ----------

class _Spinner extends StatefulWidget {
  const _Spinner({required this.size, this.right});
  final double size;
  final Color? right;
  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _SpinnerPainter(widget.right)),
        ),
      );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.right);
  final Color? right;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(rect.center, rect.width / 2, p(const Color.fromRGBO(95, 230, 255, .18)));
    canvas.drawArc(rect, -math.pi * 3 / 4, math.pi / 2, false, p(const Color(0xFF5FE6FF)));
    if (right != null) canvas.drawArc(rect, -math.pi / 4, math.pi / 2, false, p(right!));
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter old) => false;
}

class _Loading extends StatelessWidget {
  const _Loading(this.message, this.c);
  final String message;
  final BoxConstraints c;
  @override
  Widget build(BuildContext context) {
    final m = math.min(c.maxWidth, c.maxHeight);
    return Container(
      decoration: const BoxDecoration(gradient: RadialGradient(stops: [0, .68], colors: [Color(0xFF10255A), Color(0xFF040814)])),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Spinner(size: clampD(44, m * .14, 72), right: hex('#c25cff')),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: chakra(clampD(13, 3.7 * c.maxWidth / 100, 18), color: hex('#d7fbff'), weight: FontWeight.w400)),
      ]),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash(this.c);
  final BoxConstraints c;
  @override
  Widget build(BuildContext context) {
    final m = math.min(c.maxWidth, c.maxHeight);
    return Container(
      decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.16), stops: [0, .7], colors: [Color(0xFF14306E), Color(0xFF040814)])),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(opacity: t, child: Transform.scale(scale: .92 + .08 * t, child: child)),
          child: Container(
            decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color.fromRGBO(101, 234, 255, .2), blurRadius: 36)]),
            child: Image.asset('android-assets/images/logo.png', width: math.min(math.min(c.maxWidth * .7, c.maxHeight * .5), 320)),
          ),
        ),
        SizedBox(height: clampD(12, m * .03, 20)),
        _Spinner(size: clampD(28, m * .08, 40)),
      ]),
    );
  }
}

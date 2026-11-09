import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'game/engine.dart';
import 'game/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('=== FLUTTER ERROR ===');
    debugPrint(details.exceptionAsString());
    debugPrint(details.stack.toString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== PLATFORM ERROR ===\n$error\n$stack');
    return true;
  };
  runApp(const ArcherApp());
}

class ArcherApp extends StatelessWidget {
  const ArcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arcane Siege',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF040815)),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GameEngine _engine = GameEngine();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick)..start();
    _engine.boot();
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.033, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _engine.update(dt);
    _frame.value++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_engine.booted) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _engine.saveNow();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _engine.saveNow();
        _engine.audio.suspend();
      case AppLifecycleState.resumed:
        _engine.audio.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _engine.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea keeps the game clear of the notch and gesture bar.
    return Scaffold(
      backgroundColor: const Color(0xFF040815),
      body: SafeArea(child: GameShell(engine: _engine, frame: _frame)),
    );
  }
}

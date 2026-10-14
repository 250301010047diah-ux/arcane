import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Minimal local "server" so the bundled HTML5 game can run inside a WebView.
// The game is an ES-module that expects the Playabl SDK + asset manifest, which
// we provide via the stub below and the bundled `game js` / `dummy` folders.
const String _indexHtml = r'''<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
<title>Arcane Siege</title>
<script>
(function () {
  window.__weblogs = [];
  function post(m) {
    try {
      if (window.FlutterBridge) FlutterBridge.postMessage(m);
      else window.__weblogs.push(m);
    } catch (e) { window.__weblogs.push(String(m)); }
  }
  window.addEventListener('error', function (e) {
    post('JS ERROR: ' + (e.message || '') + ' @ ' + (e.filename || '') + ':' + (e.lineno || ''));
  });
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason; post('JS REJECTION: ' + (r && r.message ? r.message : r));
  });
  ['error', 'warn', 'log'].forEach(function (level) {
    var orig = console[level];
    console[level] = function () {
      try {
        post('console.' + level + ': ' + Array.prototype.map.call(arguments, function (a) {
          return a && a.stack ? a.stack : (typeof a === 'object' ? JSON.stringify(a) : a);
        }).join(' '));
      } catch (_) {}
      if (orig) orig.apply(console, arguments);
    };
  });
})();
</script>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@400;600;700&family=Inter:wght@400;600;700;800&display=swap" />
<link rel="stylesheet" href="/game/styles.css" />
</head>
<body>
<div id="app"></div>
<script type="module">
import { createGame } from "/game/game.js";
import sdk from "/sdk.js";
const assetsManifest = await (await fetch("/assets.json")).json();
const tweaksManifest = await (await fetch("/tweaks.json")).json();
const app = document.querySelector("#app");
const ready = await sdk.ready();
const tweaks = await sdk.tweaks.init(tweaksManifest);
const assets = Object.keys(assetsManifest).length > 0 ? await sdk.assets.register(assetsManifest) : undefined;
const game = createGame({ mount: app, sdk: sdk, ready: ready, tweaks: tweaks, assets: assets });
game.start();
</script>
</body>
</html>''';

const String _sdkJs = r'''const sdk = {
  ready: async function () { return {}; },
  tweaks: {
    init: async function (manifest) {
      var values = {};
      for (var k in manifest) { values[k] = manifest[k].value; }
      var subscribers = {};
      return {
        get: function (key) { return values[key]; },
        subscribe: function (key, cb) {
          subscribers[key] = subscribers[key] || [];
          subscribers[key].push(cb);
          if (typeof cb === "function") { try { cb(values[key]); } catch (_) {} }
          return function () {
            subscribers[key] = (subscribers[key] || []).filter(function (fn) { return fn !== cb; });
          };
        }
      };
    }
  },
  assets: {
    register: async function (manifest) {
      var map = {};
      for (var k in manifest) { map[k] = manifest[k]; }
      return { get: function (key) { return map[key]; } };
    }
  },
  gameState: {
    load: async function () {
      var raw = window.localStorage.getItem("archer.gameState");
      return raw ? JSON.parse(raw) : null;
    },
    save: async function (data) {
      window.localStorage.setItem("archer.gameState", JSON.stringify(data));
    }
  },
  leaderboard: { submit: async function () {} },
  audio: {
    getContext: async function () {
      var Ctx = window.AudioContext || window.webkitAudioContext;
      var ctx = Ctx ? new Ctx() : null;
      // Flutter suspends/resumes this context when the app goes to background.
      window.__archerAudio = ctx;
      return {
        context: ctx,
        unlock: async function () {
          if (ctx && ctx.state !== "running") {
            try { await ctx.resume(); } catch (_) {}
          }
        },
        dispose: async function () {
          if (ctx && ctx.state !== "closed") {
            try { await ctx.close(); } catch (_) {}
          }
        }
      };
    }
  },
  device: { haptics: { isSupported: function () { return false; }, vibrate: async function () {} } }
};
export default sdk;''';

late final HttpServer _server;
late final int _port;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Surface the REAL error in the console instead of the useless infinite
  // "Instance of 'DiagnosticsProperty<void>'" loop.
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('=== FLUTTER ERROR ===');
    debugPrint(details.exceptionAsString());
    debugPrint(details.stack.toString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== PLATFORM ERROR ===');
    debugPrint(error.toString());
    debugPrint(stack.toString());
    return true;
  };
  // Also show a readable screen if a widget build error occurs.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    return Material(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Terjadi error:\n\n$message',
          style: const TextStyle(color: Colors.red, fontSize: 14),
        ),
      ),
    );
  };
  // A fixed port keeps the page origin stable, so localStorage (save data)
  // survives app restarts. Fall back to any free port if it is taken.
  try {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 47821);
  } on SocketException {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  }
  _port = _server.port;
  _server.listen(_handleRequest);
  runApp(const ArcherApp());
}

Future<void> _handleRequest(HttpRequest req) async {
  final path = Uri.decodeComponent(req.uri.path);
  try {
    if (path == '/' || path == '/index.html') {
      await _sendString(req, _indexHtml, 'text/html; charset=utf-8');
      return;
    }
    if (path == '/sdk.js') {
      await _sendString(req, _sdkJs, 'text/javascript; charset=utf-8');
      return;
    }
    if (path == '/assets.json' || path == '/tweaks.json') {
      final json = await rootBundle.loadString(
        path == '/assets.json' ? 'game js/assets.json' : 'game js/tweaks.json',
      );
      // The game modules do `import manifest from "../assets.json"`, which needs
      // a JS module here since there is no bundler. Wrap it when requested as a script.
      if (req.headers.value('sec-fetch-dest') == 'script') {
        await _sendString(req, 'export default $json;', 'text/javascript; charset=utf-8');
      } else {
        await _sendString(req, json, 'application/json');
      }
      return;
    }
    if (path.startsWith('/game/')) {
      final rest = path.substring(6);
      final mime = _mime(path);
      // The game modules live under `game js/game/`, but the entry module and
      // styles.css live directly under `game js/`. Try both locations.
      ByteData? data;
      for (final candidate in ['game js/$rest', 'game js/game/$rest']) {
        try {
          data = await rootBundle.load(candidate);
          break;
        } catch (_) {
          // try the next candidate
        }
      }
      if (data == null) {
        await _notFound(req);
        return;
      }
      if (mime.startsWith('image')) {
        await _sendBytes(req, data, mime);
      } else {
        final text = utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        await _sendString(req, text, mime);
      }
      return;
    }
    if (path.startsWith('/audio/')) {
      final asset = 'android-assets/audio/${path.substring('/audio/'.length)}';
      await _sendBytes(req, await rootBundle.load(asset), _mime(path));
      return;
    }
    if (path.startsWith('/generated-assets/')) {
      final name = path.substring('/generated-assets/'.length);
      // Frame data (.frames.json) lives in android-assets/json, images in android-assets/images.
      final asset = name.endsWith('.json') ? 'android-assets/json/$name' : 'android-assets/images/$name';
      await _sendBytes(req, await rootBundle.load(asset), _mime(path));
      return;
    }
    await _notFound(req);
  } catch (e, stack) {
    debugPrint('Server error for "$path": $e');
    debugPrint(stack.toString());
    try {
      req.response.statusCode = 500;
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }
}

Future<void> _sendString(HttpRequest req, String body, String mime) async {
  req.response.headers.contentType = ContentType.parse(mime);
  req.response.write(body);
  await req.response.close();
}

Future<void> _sendBytes(HttpRequest req, ByteData data, String mime) async {
  req.response.headers.contentType = ContentType.parse(mime);
  req.response.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  await req.response.close();
}

Future<void> _notFound(HttpRequest req) async {
  req.response.statusCode = 404;
  await req.response.close();
}

String _mime(String path) {
  if (path.endsWith('.js')) return 'text/javascript; charset=utf-8';
  if (path.endsWith('.json')) return 'application/json';
  if (path.endsWith('.css')) return 'text/css; charset=utf-8';
  if (path.endsWith('.webp')) return 'image/webp';
  if (path.endsWith('.mp3')) return 'audio/mpeg';
  if (path.endsWith('.html')) return 'text/html; charset=utf-8';
  return 'application/octet-stream';
}

class ArcherApp extends StatelessWidget {
  const ArcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Ask the game to save as soon as the app may be leaving (home, app switch,
  // swipe-away). The WebView also keeps its AudioContext open in the
  // background, so suspend it while hidden and resume only what we suspended.
  static const _saveScript = "window.dispatchEvent(new Event('archer-save'));";

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_initError != null) return;
    final String script = switch (state) {
      AppLifecycleState.inactive || AppLifecycleState.detached => _saveScript,
      AppLifecycleState.paused || AppLifecycleState.hidden => '''
        $_saveScript
        (function () {
          var c = window.__archerAudio;
          if (c && c.state === "running") { c.__pausedByApp = true; c.suspend(); }
        })();''',
      AppLifecycleState.resumed => '''
        (function () {
          var c = window.__archerAudio;
          if (c && c.__pausedByApp) { c.__pausedByApp = false; c.resume(); }
        })();''',
    };
    _controller
        .runJavaScript(script)
        .catchError((e) => debugPrint('WEB: lifecycle JS error $e'));
  }

  Future<void> _initWebView() async {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF040815))
        ..addJavaScriptChannel(
          'FlutterBridge',
          onMessageReceived: (message) {
            debugPrint('WEB: ${message.message}');
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              debugPrint('WEB: page finished $url');
              _controller
                  .runJavaScript('''
                (function () {
                  try {
                    var el = document.querySelector('[data-ui="loading"]');
                    if (el && el.className.indexOf('load-failed') >= 0) {
                      FlutterBridge.postMessage('BOOT FAILED: ' + el.innerText);
                    }
                  } catch (e) {}
                  try {
                    var logs = window.__weblogs || [];
                    logs.forEach(function (m) { FlutterBridge.postMessage(m); });
                    window.__weblogs = [];
                  } catch (e) {}
                })();
              ''')
                  .catchError((e) => debugPrint('WEB: runJS error $e'));
            },
            onWebResourceError: (error) {
              debugPrint('WEB resource error: ${error.description} (${error.url})');
            },
          ),
        )
        ..loadRequest(Uri.parse('http://127.0.0.1:$_port/'));
    } catch (e, stack) {
      if (!mounted) return;
      setState(() {
        _initError = '$e\n\n$stack';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Gagal memuat WebView:\n\n$_initError',
            style: const TextStyle(color: Colors.red, fontSize: 14),
          ),
        ),
      );
    }
    // Until the WebView is tapped it has no input focus, so hardware keyboard
    // events land in Flutter; forward the game's keys to the page.
    // SafeArea keeps the game clear of the notch, status bar and gesture bar, so
    // the on-screen controls are never hidden behind system UI.
    return Scaffold(
      backgroundColor: const Color(0xFF040815),
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: _forwardKey,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }

  static final Map<LogicalKeyboardKey, String> _domCodes = {
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.keyA: 'KeyA',
    LogicalKeyboardKey.keyD: 'KeyD',
    LogicalKeyboardKey.keyW: 'KeyW',
    LogicalKeyboardKey.keyK: 'KeyK',
    LogicalKeyboardKey.keyJ: 'KeyJ',
    LogicalKeyboardKey.keyU: 'KeyU',
    LogicalKeyboardKey.keyI: 'KeyI',
    LogicalKeyboardKey.keyO: 'KeyO',
    LogicalKeyboardKey.keyP: 'KeyP',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.shiftLeft: 'ShiftLeft',
    LogicalKeyboardKey.shiftRight: 'ShiftRight',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'NumpadEnter',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.digit0: 'Digit0',
    LogicalKeyboardKey.digit1: 'Digit1',
    LogicalKeyboardKey.digit2: 'Digit2',
    LogicalKeyboardKey.digit3: 'Digit3',
    LogicalKeyboardKey.digit4: 'Digit4',
    LogicalKeyboardKey.digit5: 'Digit5',
    LogicalKeyboardKey.digit6: 'Digit6',
    LogicalKeyboardKey.digit7: 'Digit7',
    LogicalKeyboardKey.digit8: 'Digit8',
    LogicalKeyboardKey.digit9: 'Digit9',
  };

  KeyEventResult _forwardKey(FocusNode node, KeyEvent event) {
    final code = _domCodes[event.logicalKey];
    if (code == null || _initError != null) return KeyEventResult.ignored;
    final type = event is KeyUpEvent ? 'keyup' : 'keydown';
    final repeat = event is KeyRepeatEvent;
    _controller
        .runJavaScript(
          "window.dispatchEvent(new KeyboardEvent('$type', {code: '$code', repeat: $repeat, bubbles: true, cancelable: true}));",
        )
        .catchError((e) => debugPrint('WEB: key forward error $e'));
    return KeyEventResult.handled;
  }
}

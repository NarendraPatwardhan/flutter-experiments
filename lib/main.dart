import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'session/product_session.dart';
import 'vt/bindings.dart'
    show
        kSelectionGestureDrag,
        kSelectionGesturePress,
        kSelectionGestureRelease;
import 'vt/metrics.dart';
import 'vt/painter.dart';
import 'vt/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgentOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: VtTheme.chromeBg,
        colorScheme: const ColorScheme.dark(
          surface: VtTheme.chromeBg,
          onSurface: VtTheme.chromeFg,
          primary: VtTheme.chromeAccent,
          onPrimary: Color(0xFF0A0A0A),
          outline: VtTheme.chromeBorder,
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final ProductSession _session;
  late final AnimationController _blink;

  // Re-measured after first frame so fontconfig has resolved a real mono face.
  VtMetrics _metrics = VtMetrics.measure(fontSize: 13);
  EdgeInsets _gridPadding = const EdgeInsets.all(8);
  bool _focused = true;
  int _layoutCols = 80;
  int _layoutRows = 24;
  bool _starting = false;
  /// Host-side boot diagnostic when [ProductSession] never starts.
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _session = ProductSession()..addListener(_onSession);
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      final m = VtMetrics.measure(fontSize: 13);
      if (mounted) {
        setState(() => _metrics = m);
      }
      unawaited(_startSession());
    });
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _blink.dispose();
    _session.removeListener(_onSession);
    // ProductSession.dispose drains/defers native free so an in-flight tick
    // cannot use-after-free libghostty-vt (that corrupted GTK on close).
    _session.dispose();
    super.dispose();
  }

  ({String hostLib, String? vtLib, String kernel, String? image})?
      _locateAssets() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final hostCandidates = [
      '$exeDir/lib/libagentos_flutter_host.so',
      '$exeDir/libagentos_flutter_host.so',
    ];
    final vtCandidates = [
      '$exeDir/lib/libghostty-vt.so',
      '$exeDir/libghostty-vt.so',
    ];
    final kernelCandidates = [
      '$exeDir/data/kernel.wasm',
      '$exeDir/kernel.wasm',
    ];
    final imageCandidates = [
      '$exeDir/data/loom.tar',
      '$exeDir/data/posix.tar',
      '$exeDir/loom.tar',
      '$exeDir/posix.tar',
    ];

    String? hostPath;
    String? vtPath;
    String? kernelPath;
    String? imagePath;
    for (final p in hostCandidates) {
      if (File(p).existsSync()) {
        hostPath = p;
        break;
      }
    }
    for (final p in vtCandidates) {
      if (File(p).existsSync()) {
        vtPath = p;
        break;
      }
    }
    for (final p in kernelCandidates) {
      if (File(p).existsSync()) {
        kernelPath = p;
        break;
      }
    }
    for (final p in imageCandidates) {
      if (File(p).existsSync()) {
        imagePath = p;
        break;
      }
    }
    if (hostPath == null || kernelPath == null) return null;
    return (
      hostLib: hostPath,
      vtLib: vtPath,
      kernel: kernelPath,
      image: imagePath,
    );
  }

  Future<void> _startSession() async {
    if (_starting) return;
    _starting = true;
    _bootError = null;
    try {
      final assets = _locateAssets();
      if (assets == null) {
        _bootError = 'missing libagentos_flutter_host.so or kernel.wasm '
            '(expected beside the binary under lib/ and data/)';
        return;
      }
      if (assets.vtLib == null) {
        _bootError = 'missing libghostty-vt.so (expected under lib/ next to host)';
        return;
      }
      if (assets.image == null) {
        _bootError = 'missing guest image (loom.tar / posix.tar under data/)';
        return;
      }
      await _session.start(
        hostLib: assets.hostLib,
        vtLib: assets.vtLib!,
        kernel: assets.kernel,
        image: assets.image!,
        cols: _layoutCols,
        rows: _layoutRows,
        cellW: _metrics.cellWidth.round(),
        cellH: _metrics.cellHeight.round(),
      );
    } catch (e) {
      // ProductSession records detail on statusLine; keep a local fallback.
      _bootError ??= 'start failed: $e';
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _rerun() async {
    await _startSession();
  }

  void _onSurfaceLayout(Size size) {
    final fit = _metrics.fit(size);
    if (fit.cols == _layoutCols &&
        fit.rows == _layoutRows &&
        fit.padding == _gridPadding) {
      return;
    }
    setState(() {
      _layoutCols = fit.cols;
      _layoutRows = fit.rows;
      _gridPadding = fit.padding;
    });
    unawaited(
      _session.resize(
        fit.cols,
        fit.rows,
        _metrics.cellWidth.round(),
        _metrics.cellHeight.round(),
        padL: fit.padding.left.round(),
        padT: fit.padding.top.round(),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final mod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    // Ctrl/Cmd+V → paste; Ctrl/Cmd+Shift+C → copy selection (Ctrl+C stays interrupt).
    if (event is KeyDownEvent && mod) {
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        unawaited(_pasteClipboard());
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC &&
          HardwareKeyboard.instance.isShiftPressed) {
        unawaited(_copySelection());
        return KeyEventResult.handled;
      }
    }
    unawaited(_session.onKey(event));
    return KeyEventResult.handled;
  }

  Future<void> _copySelection() async {
    final text = await _session.copySelection();
    if (text != null && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      await _session.onPaste(text);
    }
  }

  void _onFocusChange(bool gained) {
    setState(() => _focused = gained);
    unawaited(_session.onFocus(gained));
  }

  String get _statusText {
    if (_bootError != null && !_session.started) return _bootError!;
    if (!_session.started && !_session.busy) {
      final assets = _locateAssets();
      if (assets == null) {
        return 'missing libagentos_flutter_host.so or kernel.wasm';
      }
      if (assets.vtLib == null) return 'missing libghostty-vt.so';
      if (assets.image == null) return 'missing loom.tar / posix.tar';
    }
    return _session.statusLine;
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        _session.bellFlash ? VtTheme.chromeBell : VtTheme.chromeAccent;
    final busy = _session.busy || _starting;

    return Focus(
      autofocus: true,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: VtTheme.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thin status strip — not a Material marketing header.
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: VtTheme.chromeBg,
                border: Border(
                  bottom: BorderSide(
                    color: _session.bellFlash
                        ? VtTheme.chromeBell
                        : VtTheme.chromeBorder,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'agentos',
                    style: TextStyle(
                      fontFamily: _metrics.fontFamily,
                      fontFamilyFallback: VtMetrics.fontFamilyFallback,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: _metrics.fontFamily,
                        fontFamilyFallback: VtMetrics.fontFamilyFallback,
                        fontSize: 12,
                        color: VtTheme.chromeFg,
                        height: 1,
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: VtTheme.chromeDim,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _rerun,
                      style: TextButton.styleFrom(
                        foregroundColor: VtTheme.chromeDim,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'rerun',
                        style: TextStyle(
                          fontFamily: _metrics.fontFamily,
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _onSurfaceLayout(size);
                  });
                  return Listener(
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        unawaited(
                          _session.onScroll(signal.scrollDelta.dy),
                        );
                      }
                    },
                    onPointerDown: (e) {
                      unawaited(_session.onPointer(
                        kind: kSelectionGesturePress,
                        x: e.localPosition.dx,
                        y: e.localPosition.dy,
                        padL: _gridPadding.left.round(),
                        padT: _gridPadding.top.round(),
                      ));
                    },
                    onPointerMove: (e) {
                      if (e.down) {
                        unawaited(_session.onPointer(
                          kind: kSelectionGestureDrag,
                          x: e.localPosition.dx,
                          y: e.localPosition.dy,
                          padL: _gridPadding.left.round(),
                          padT: _gridPadding.top.round(),
                        ));
                      }
                    },
                    onPointerUp: (e) {
                      unawaited(_session.onPointer(
                        kind: kSelectionGestureRelease,
                        x: e.localPosition.dx,
                        y: e.localPosition.dy,
                        padL: _gridPadding.left.round(),
                        padT: _gridPadding.top.round(),
                      ));
                    },
                    child: AnimatedBuilder(
                      animation: _blink,
                      builder: (context, _) {
                        return VtView(
                          frame: _session.frame,
                          metrics: _metrics,
                          padding: _gridPadding,
                          focused: _focused,
                          blinkPhase: _blink.value >= 0.5,
                          imagesBelow: _session.imagesBelow,
                          imagesAbove: _session.imagesAbove,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

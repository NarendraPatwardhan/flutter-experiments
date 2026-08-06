import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'notebook/controller.dart';
import 'notebook/host_keys.dart';
import 'notebook/model.dart';
import 'notebook/widgets/control_plane.dart';
import 'notebook/widgets/notebook_shell.dart';
import 'session/product_session.dart';
import 'vt/metrics.dart';
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
        splashFactory: NoSplash.splashFactory,
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
  late final NotebookController _notebook;
  late final AnimationController _blink;
  late final TextEditingController _nlText;
  late final FocusNode _shellFocus;
  late final FocusNode _nlFocus;

  VtMetrics _metrics = VtMetrics.measure(fontSize: 13);
  bool _terminalFocused = true;
  int _layoutCols = 80;
  int _layoutRows = 24;
  EdgeInsets _gridPadding = const EdgeInsets.all(8);
  bool _starting = false;
  String? _bootError;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _session = ProductSession()..addListener(_rebuild);
    _notebook = NotebookController()..addListener(_onNotebook);
    _nlText = TextEditingController();
    _shellFocus = FocusNode(debugLabel: 'shell');
    _nlFocus = FocusNode(debugLabel: 'ask');
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);

    HardwareKeyboard.instance.addHandler(_onHardwareKey);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      final m = VtMetrics.measure(fontSize: 13);
      if (!mounted) return;
      setState(() => _metrics = m);
      unawaited(_startSession());
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final m2 = VtMetrics.measure(fontSize: 13);
        if (m2.cellWidth != _metrics.cellWidth ||
            m2.cellHeight != _metrics.cellHeight ||
            m2.fontFamily != _metrics.fontFamily) {
          setState(() => _metrics = m2);
          unawaited(_resizeSession());
        }
      });
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onNotebook() {
    if (!mounted) return;
    setState(() {});
    if (_notebook.statusFlash != null) {
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) _notebook.clearStatusFlash();
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _flashTimer?.cancel();
    _blink.dispose();
    _nlText.dispose();
    _nlFocus.dispose();
    _shellFocus.dispose();
    _notebook.removeListener(_onNotebook);
    _notebook.dispose();
    _session.removeListener(_rebuild);
    _session.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || _notebook.paletteOpen) return false;
    final chord = classifyHostChord(event);
    if (chord == null) return false;

    switch (chord) {
      case HostChord.controlPlane:
        unawaited(_openControlPlane());
        return true;
      case HostChord.toggleMode:
        _toggleMode();
        return true;
      case HostChord.nlSubmit:
        if (_notebook.mode == InputMode.naturalLanguage) {
          _submitNl();
          return true;
        }
        return false;
      case HostChord.escape:
        if (_notebook.mode == InputMode.naturalLanguage) {
          _onEscapeInAsk();
          return true;
        }
        return false;
    }
  }

  ({String hostLib, String? vtLib, String kernel, String? image})?
      _locateAssets() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    String? pick(List<String> c) {
      for (final p in c) {
        if (File(p).existsSync()) return p;
      }
      return null;
    }

    final host = pick([
      '$exeDir/lib/libagentos_flutter_host.so',
      '$exeDir/libagentos_flutter_host.so',
    ]);
    final vt = pick([
      '$exeDir/lib/libghostty-vt.so',
      '$exeDir/libghostty-vt.so',
    ]);
    final kernel = pick([
      '$exeDir/data/kernel.wasm',
      '$exeDir/kernel.wasm',
    ]);
    final image = pick([
      '$exeDir/data/loom.tar',
      '$exeDir/data/posix.tar',
      '$exeDir/loom.tar',
      '$exeDir/posix.tar',
    ]);
    if (host == null || kernel == null) return null;
    return (hostLib: host, vtLib: vt, kernel: kernel, image: image);
  }

  Future<void> _startSession() async {
    if (_starting) return;
    _starting = true;
    _bootError = null;
    if (mounted) setState(() {});
    try {
      final assets = _locateAssets();
      if (assets == null) {
        _bootError = 'missing host library or kernel.wasm';
        return;
      }
      if (assets.vtLib == null) {
        _bootError = 'missing libghostty-vt.so';
        return;
      }
      if (assets.image == null) {
        _bootError = 'missing guest image (loom.tar / posix.tar)';
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
      _bootError ??= 'start failed: $e';
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _resizeSession() async {
    if (!_session.started) return;
    await _session.resize(
      _layoutCols,
      _layoutRows,
      _metrics.cellWidth.round(),
      _metrics.cellHeight.round(),
      padL: _gridPadding.left.round(),
      padT: _gridPadding.top.round(),
    );
  }

  void _onTerminalLayout(int cols, int rows, EdgeInsets padding) {
    if (cols == _layoutCols &&
        rows == _layoutRows &&
        padding == _gridPadding) {
      return;
    }
    _layoutCols = cols;
    _layoutRows = rows;
    _gridPadding = padding;
    unawaited(_resizeSession());
  }

  String get _statusText {
    if (_bootError != null && !_session.started) return _bootError!;
    if (!_session.started && !_session.busy) {
      final a = _locateAssets();
      if (a == null) return 'missing host library or kernel';
      if (a.vtLib == null) return 'missing libghostty-vt.so';
      if (a.image == null) return 'missing guest image';
      return 'starting…';
    }
    return _session.statusLine;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_notebook.paletteOpen) return KeyEventResult.ignored;
    if (_notebook.mode == InputMode.naturalLanguage) {
      return KeyEventResult.ignored;
    }
    if (classifyHostChord(event) != null) return KeyEventResult.handled;

    final mod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (event is KeyDownEvent && mod) {
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        unawaited(_paste());
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC &&
          HardwareKeyboard.instance.isShiftPressed) {
        unawaited(_copy());
        return KeyEventResult.handled;
      }
    }

    unawaited(_session.onKey(event));
    return KeyEventResult.handled;
  }

  void _onEscapeInAsk() {
    if (_nlText.text.isNotEmpty) {
      _nlText.clear();
      setState(() {});
      return;
    }
    _enterTerminal();
  }

  void _toggleMode() {
    if (_notebook.mode == InputMode.terminal) {
      _enterAsk();
    } else {
      _enterTerminal();
    }
  }

  void _enterAsk() {
    _notebook.setMode(InputMode.naturalLanguage);
    setState(() => _terminalFocused = false);
    unawaited(_session.onFocus(false));
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nlFocus.requestFocus();
    });
  }

  void _enterTerminal() {
    _notebook.setMode(InputMode.terminal);
    setState(() => _terminalFocused = true);
    _shellFocus.requestFocus();
    unawaited(_session.onFocus(true));
  }

  void _submitNl() {
    if (!_notebook.submitUserMessage(_nlText.text)) return;
    _nlText.clear();
    _enterTerminal();
  }

  Future<void> _openControlPlane() async {
    if (_notebook.paletteOpen) return;
    _notebook.setPaletteOpen(true);
    await showControlPlane(
      context,
      onRestart: () => unawaited(_startSession()),
      fontFamily: _metrics.fontFamily,
    );
    if (!mounted) return;
    _notebook.setPaletteOpen(false);
    if (_notebook.mode == InputMode.terminal) {
      _shellFocus.requestFocus();
    } else {
      _nlFocus.requestFocus();
    }
  }

  Future<void> _copy() async {
    final text = await _session.copySelection();
    if (text != null && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      await _session.onPaste(text);
    }
  }

  void _onFocusChange(bool gained) {
    if (_notebook.mode == InputMode.naturalLanguage) return;
    setState(() => _terminalFocused = gained);
    unawaited(_session.onFocus(gained));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _session.busy || _starting;
    return Focus(
      focusNode: _shellFocus,
      autofocus: true,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: VtTheme.background,
        body: AnimatedBuilder(
          animation: _blink,
          builder: (context, _) {
            return NotebookShell(
              session: _session,
              notebook: _notebook,
              metrics: _metrics,
              blinkPhase: _blink.value >= 0.5,
              terminalFocused:
                  _terminalFocused && _notebook.mode == InputMode.terminal,
              statusText: _statusText,
              busy: busy,
              title: 'agentos',
              nlController: _nlText,
              nlFocus: _nlFocus,
              onRestart: () => unawaited(_startSession()),
              onTerminalLayout: _onTerminalLayout,
            );
          },
        ),
      ),
    );
  }
}

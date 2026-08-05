import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'agent_os/vm.dart';
import 'vt/frame.dart';
import 'vt/metrics.dart';
import 'vt/painter.dart';
import 'vt/session.dart';
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

class _HomePageState extends State<HomePage> {
  String _status = 'starting…';
  VtFrame _frame = VtFrame.empty(cols: 80, rows: 24);
  // Re-measured after first frame so fontconfig has resolved a real mono face.
  VtMetrics _metrics = VtMetrics.measure(fontSize: 13);
  EdgeInsets _gridPadding = const EdgeInsets.all(8);
  bool _busy = true;
  bool _focused = true;
  GhosttyVtSession? _vt;
  int _layoutCols = 80;
  int _layoutRows = 24;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // Remeasure once the UI isolate has font fallback resolution.
      final m = VtMetrics.measure(fontSize: 13);
      if (mounted) {
        setState(() => _metrics = m);
      }
      _runSession();
    });
  }

  @override
  void dispose() {
    _vt?.close();
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

  void _paintVt(GhosttyVtSession vt) {
    final frame = vt.snapshot();
    if (!mounted) return;
    setState(() => _frame = frame);
  }

  void _vtBanner(GhosttyVtSession vt, String title) {
    vt.writeText(
      '\r\n\x1b[90m── \x1b[0m\x1b[1m$title\x1b[0m\r\n',
    );
  }

  void _vtWriteOutput(GhosttyVtSession vt, Uint8List data) {
    if (data.isEmpty) return;
    vt.writeGuest(data);
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
    final vt = _vt;
    if (vt != null && (vt.cols != fit.cols || vt.rows != fit.rows)) {
      // Keep cell pixel size in sync with font metrics (Ghostty resize).
      try {
        vt.resize(
          fit.cols,
          fit.rows,
          cellW: _metrics.cellWidth.round(),
          cellH: _metrics.cellHeight.round(),
        );
        _paintVt(vt);
      } catch (_) {
        // Resize can fail mid-boot; ignore.
      }
    }
  }

  Future<void> _runSession() async {
    _vt?.close();
    _vt = null;

    setState(() {
      _busy = true;
      _status = 'looking for assets…';
      _frame = VtFrame.empty(cols: _layoutCols, rows: _layoutRows);
    });

    try {
      final assets = _locateAssets();
      if (assets == null) {
        setState(() {
          _status = 'missing host.so / kernel.wasm / loom.tar';
          _busy = false;
        });
        return;
      }
      if (assets.vtLib == null) {
        setState(() {
          _status = 'missing libghostty-vt.so';
          _busy = false;
        });
        return;
      }
      if (assets.image == null) {
        setState(() {
          _status = 'missing loom.tar';
          _busy = false;
        });
        return;
      }
      setState(() => _status = 'opening vt…');
      final vt = GhosttyVtSession.open(
        libraryPath: assets.vtLib,
        cols: _layoutCols,
        rows: _layoutRows,
      );
      // Pixel cell size for image protocols / size reports.
      vt.resize(
        _layoutCols,
        _layoutRows,
        cellW: _metrics.cellWidth.round(),
        cellH: _metrics.cellHeight.round(),
      );
      _vt = vt;

      vt.writeText(
        '\x1b[1;32magentos\x1b[0m · flutter · libghostty-vt\r\n'
        '\x1b[90m${vt.cols}×${vt.rows}  cell '
        '${_metrics.cellWidth.round()}×${_metrics.cellHeight.round()}px'
        '  ${_metrics.fontFamily}\x1b[0m\r\n',
      );
      _paintVt(vt);

      final imageName = assets.image!.split(Platform.pathSeparator).last;
      setState(() => _status = 'boot $imageName…');
      final vm = await AgentOsVm.bootFromFiles(
        kernelPath: assets.kernel,
        imagePath: assets.image,
        libraryPath: assets.hostLib,
      );
      try {
        for (var i = 0; i < 64; i++) {
          final s = await vm.tick();
          if (s == AgentOsTickState.exited || s == AgentOsTickState.waiting) {
            break;
          }
        }
        final bootBytes = await vm.takeOutput();
        _vtBanner(vt, 'boot ($imageName)');
        if (bootBytes.isEmpty) {
          vt.writeText('\x1b[90m(quiet shell)\x1b[0m\r\n');
        } else {
          _vtWriteOutput(vt, bootBytes);
        }
        _paintVt(vt);

        setState(() => _status = 'running…');

        Future<void> runCmd(String cmd) async {
          final r = await vm.exec(cmd);
          _vtBanner(vt, '$cmd  ·  ${r.exitCode}');
          _vtWriteOutput(vt, r.stdout);
          if (r.stderr.isNotEmpty) {
            vt.writeText('\x1b[31m');
            _vtWriteOutput(vt, r.stderr);
            vt.writeText('\x1b[0m');
          }
          _paintVt(vt);
        }

        await runCmd('echo Hello from AgentOS');
        await runCmd('uname -a');
        await runCmd('ls /bin | head -n 20');

        _vtBanner(vt, 'style');
        vt.writeText(
          'plain  \x1b[1mbold\x1b[0m  \x1b[32mgreen\x1b[0m  '
          '\x1b[38;2;255;160;60morange\x1b[0m  \x1b[4munderline\x1b[0m\r\n',
        );
        _paintVt(vt);

        setState(() => _status = 'ok  ${vt.cols}×${vt.rows}');
      } finally {
        await vm.close();
      }
    } catch (e, st) {
      final msg = 'error: $e';
      try {
        _vt?.writeText('\r\n\x1b[1;31m$msg\x1b[0m\r\n');
        _vt?.writeText(st.toString());
        if (_vt != null) _paintVt(_vt!);
      } catch (_) {}
      setState(() => _status = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onFocusChange: (v) => setState(() => _focused = v),
      child: Scaffold(
        backgroundColor: VtTheme.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thin status strip — not a Material marketing header.
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: VtTheme.chromeBg,
                border: Border(
                  bottom: BorderSide(color: VtTheme.chromeBorder, width: 1),
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
                      color: VtTheme.chromeAccent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status,
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
                  if (_busy)
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
                      onPressed: _runSession,
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
                  // Defer layout→resize to after frame to avoid setState during build.
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _onSurfaceLayout(size);
                  });
                  return VtView(
                    frame: _frame,
                    metrics: _metrics,
                    padding: _gridPadding,
                    focused: _focused,
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

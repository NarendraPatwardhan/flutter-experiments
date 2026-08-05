import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'agent_os/vm.dart';
import 'vt/frame.dart';
import 'vt/painter.dart';
import 'vt/session.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter AgentOS Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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
  String _status = 'Starting AgentOS + libghostty-vt…';
  VtFrame _frame = VtFrame.empty(cols: 80, rows: 28);
  bool _busy = true;
  GhosttyVtSession? _vt;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _runSession());
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
    // Dim separator via SGR, then bold title.
    vt.writeText(
      '\r\n\x1b[90m────────────────────────────────────────\x1b[0m\r\n'
      '\x1b[1;36m$title\x1b[0m\r\n',
    );
  }

  void _vtWriteOutput(GhosttyVtSession vt, Uint8List data) {
    if (data.isEmpty) return;
    vt.writeGuest(data);
  }

  Future<void> _runSession() async {
    _vt?.close();
    _vt = null;

    setState(() {
      _busy = true;
      _status = 'Looking for native assets…';
      _frame = VtFrame.empty(cols: 80, rows: 28);
    });

    try {
      final assets = _locateAssets();
      if (assets == null) {
        setState(() {
          _status =
              'Native assets missing.\n'
              'Need lib/libagentos_flutter_host.so, data/kernel.wasm, data/loom.tar.';
          _busy = false;
        });
        return;
      }
      if (assets.vtLib == null) {
        setState(() {
          _status =
              'libghostty-vt.so missing under lib/. Rebuild //:linux_product_bundle.';
          _busy = false;
        });
        return;
      }
      if (assets.image == null) {
        setState(() {
          _status =
              'Guest image missing (data/loom.tar). Rebuild //:linux_product_bundle.';
          _busy = false;
        });
        return;
      }

      setState(() => _status = 'Opening libghostty-vt…');
      final vt = GhosttyVtSession.open(
        libraryPath: assets.vtLib,
        cols: 80,
        rows: 28,
      );
      _vt = vt;

      vt.writeText(
        '\x1b[1;32mAgentOS · Flutter · libghostty-vt\x1b[0m\r\n'
        'VT grid ${vt.cols}×${vt.rows}  ·  guest → vt_write → render_state\r\n',
      );
      _paintVt(vt);

      final imageName = assets.image!.split(Platform.pathSeparator).last;
      setState(() => _status = 'Booting kernel + $imageName…');
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
        _vtBanner(vt, 'shell after boot ($imageName)');
        if (bootBytes.isEmpty) {
          vt.writeText('(no capture yet — shell may be quiet)\r\n');
        } else {
          _vtWriteOutput(vt, bootBytes);
        }
        _paintVt(vt);

        setState(() => _status = 'Running guest commands…');

        Future<void> runCmd(String cmd) async {
          final r = await vm.exec(cmd);
          _vtBanner(vt, '$cmd  (exit ${r.exitCode})');
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

        // Demo styled VT that never came from the guest.
        _vtBanner(vt, 'VT style check');
        vt.writeText(
          'plain  \x1b[1mbold\x1b[0m  \x1b[32mgreen\x1b[0m  '
          '\x1b[38;2;255;128;0morange\x1b[0m  \x1b[4munderline\x1b[0m\r\n',
        );
        _paintVt(vt);

        setState(() {
          _status =
              'OK — guest ran through VT (${vt.cols}×${vt.rows} cells painted)';
        });
      } finally {
        await vm.close();
      }
    } catch (e, st) {
      // Surface error both in status and (if VT up) on the grid.
      final msg = 'Error: $e';
      try {
        _vt?.writeText('\r\n\x1b[1;31m$msg\x1b[0m\r\n');
        _vt?.writeText(st.toString());
        if (_vt != null) _paintVt(_vt!);
      } catch (_) {}
      setState(() {
        _status = msg;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AgentOS on Flutter',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Native host · loom guest · libghostty-vt paint path',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (!_busy)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _runSession,
                  child: const Text('Run again'),
                ),
              ),
            const SizedBox(height: 8),
            Text(_status, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: VtView(frame: _frame, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

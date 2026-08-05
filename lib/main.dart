import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'agent_os/vm.dart';

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
  String _status = 'Starting AgentOS (loom)…';
  String _output = '';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    // Auto-run so launching the binary shows guest output immediately.
    SchedulerBinding.instance.addPostFrameCallback((_) => _smoke());
  }

  ({String lib, String kernel, String? loom})? _locateAssets() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final libCandidates = [
      '$exeDir/lib/libagentos_flutter_host.so',
      '$exeDir/libagentos_flutter_host.so',
    ];
    final kernelCandidates = [
      '$exeDir/data/kernel.wasm',
      '$exeDir/kernel.wasm',
    ];
    final loomCandidates = [
      '$exeDir/data/loom.tar',
      '$exeDir/loom.tar',
    ];
    String? libPath;
    String? kernelPath;
    String? loomPath;
    for (final p in libCandidates) {
      if (File(p).existsSync()) {
        libPath = p;
        break;
      }
    }
    for (final p in kernelCandidates) {
      if (File(p).existsSync()) {
        kernelPath = p;
        break;
      }
    }
    for (final p in loomCandidates) {
      if (File(p).existsSync()) {
        loomPath = p;
        break;
      }
    }
    if (libPath == null || kernelPath == null) return null;
    return (lib: libPath, kernel: kernelPath, loom: loomPath);
  }

  Future<void> _smoke() async {
    setState(() {
      _busy = true;
      _status = 'Looking for native assets…';
      _output = '';
    });
    try {
      final assets = _locateAssets();
      if (assets == null) {
        setState(() {
          _status =
              'Native assets missing.\n'
              'Need lib/libagentos_flutter_host.so and data/kernel.wasm '
              '(and data/loom.tar for a full shell).';
          _busy = false;
        });
        return;
      }
      if (assets.loom == null) {
        setState(() {
          _status =
              'loom.tar missing under data/ — rebuild //:linux_product_bundle.';
          _busy = false;
        });
        return;
      }

      setState(() => _status = 'Booting kernel + loom image…');
      final vm = await AgentOsVm.bootFromFiles(
        kernelPath: assets.kernel,
        imagePath: assets.loom,
        libraryPath: assets.lib,
      );
      try {
        // Extra ticks so the login shell can paint if it was still settling.
        for (var i = 0; i < 64; i++) {
          final s = await vm.tick();
          if (s == AgentOsTickState.exited) break;
          if (s == AgentOsTickState.waiting) break;
        }
        final bootBytes = await vm.takeOutput();
        final bootText = utf8.decode(bootBytes, allowMalformed: true);

        setState(() => _status = 'Running guest commands…');
        final echo = await vm.exec('echo Hello from AgentOS loom');
        final uname = await vm.exec('uname -a');
        final ls = await vm.exec('ls /bin | head -n 20');

        final text = StringBuffer()
          ..writeln('=== shell output after boot ===')
          ..writeln(bootText.isEmpty ? '(empty — prompt may be quiet)' : bootText)
          ..writeln()
          ..writeln('=== exec: echo Hello from AgentOS loom  (exit ${echo.exitCode}) ===')
          ..writeln(utf8.decode(echo.stdout, allowMalformed: true))
          ..write(utf8.decode(echo.stderr, allowMalformed: true))
          ..writeln()
          ..writeln('=== exec: uname -a  (exit ${uname.exitCode}) ===')
          ..writeln(utf8.decode(uname.stdout, allowMalformed: true))
          ..write(utf8.decode(uname.stderr, allowMalformed: true))
          ..writeln()
          ..writeln('=== exec: ls /bin | head  (exit ${ls.exitCode}) ===')
          ..writeln(utf8.decode(ls.stdout, allowMalformed: true))
          ..write(utf8.decode(ls.stderr, allowMalformed: true));

        setState(() {
          _status =
              'OK — loom guest ran (echo exit=${echo.exitCode}, uname exit=${uname.exitCode})';
          _output = text.toString();
        });
      } finally {
        await vm.close();
      }
    } catch (e, st) {
      setState(() {
        _status = 'Error: $e';
        _output = '$st';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AgentOS on Flutter (loom)',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Native host · kernel.wasm + loom.tar · no JS path',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (!_busy)
              FilledButton(
                onPressed: _smoke,
                child: const Text('Run again'),
              ),
            const SizedBox(height: 16),
            Text(_status, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _output.isEmpty ? '…' : _output,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

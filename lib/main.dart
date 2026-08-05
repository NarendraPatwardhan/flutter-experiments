import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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
  String _status =
      'Idle — product bundle stages lib/ + data/kernel.wasm for smoke.';
  String _output = '';
  bool _busy = false;

  ({String lib, String kernel})? _locateAssets() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final libCandidates = [
      '$exeDir/lib/libagentos_flutter_host.so',
      '$exeDir/libagentos_flutter_host.so',
    ];
    final kernelCandidates = [
      '$exeDir/data/kernel.wasm',
      '$exeDir/kernel.wasm',
      '$exeDir/lib/kernel.wasm',
    ];
    String? libPath;
    String? kernelPath;
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
    if (libPath == null || kernelPath == null) return null;
    return (lib: libPath, kernel: kernelPath);
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
              'Native assets missing under exe dir lib/ and data/.\n'
              'Build //:linux_product_bundle on BuildBuddy and unpack to dist/linux.';
        });
        return;
      }
      setState(() => _status = 'Booting AgentOS kernel…');
      final vm = await AgentOsVm.bootFromFile(
        assets.kernel,
        libraryPath: assets.lib,
      );
      try {
        final state = await vm.tick();
        final bootOut = await vm.takeOutput();
        setState(() => _status = 'Boot OK (tick=$state). Running exec…');
        // Minimal structured command; no base image ⇒ may fail closed without /bin/sh.
        final result = await vm.exec('echo agentos-flutter-host');
        final text = StringBuffer()
          ..writeln('--- take_output ---')
          ..writeln(utf8.decode(bootOut, allowMalformed: true))
          ..writeln('--- exec exit=${result.exitCode} ---')
          ..writeln(utf8.decode(result.stdout, allowMalformed: true))
          ..writeln(utf8.decode(result.stderr, allowMalformed: true));
        setState(() {
          _status = 'Done. exec exit=${result.exitCode}';
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
              'AgentOS native host',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'C ABI over KernelHost — boot + exec. No JS path.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _smoke,
              child: Text(_busy ? 'Working…' : 'Smoke boot + exec'),
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
                    _output,
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

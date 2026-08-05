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
  String _status = 'Idle — place kernel.wasm + libagentos_flutter_host.so '
      'beside the binary (lib/) to smoke-boot.';
  String _output = '';
  bool _busy = false;

  Future<void> _smokeBoot() async {
    setState(() {
      _busy = true;
      _status = 'Looking for native assets…';
      _output = '';
    });
    try {
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
      final libPath = libCandidates.cast<String?>().firstWhere(
            (p) => p != null && File(p).existsSync(),
            orElse: () => null,
          );
      final kernelPath = kernelCandidates.cast<String?>().firstWhere(
            (p) => p != null && File(p).existsSync(),
            orElse: () => null,
          );
      if (libPath == null || kernelPath == null) {
        setState(() {
          _status =
              'Native assets missing.\nlib: $libPath\nkernel: $kernelPath\n'
              'Stage from bazel-bin agentos_native/ after remote build.';
        });
        return;
      }
      setState(() => _status = 'Booting AgentOS kernel…');
      final vm = await AgentOsVm.bootFromFile(
        kernelPath,
        libraryPath: libPath,
      );
      try {
        final state = await vm.tick();
        final bytes = await vm.takeOutput();
        final text = utf8.decode(bytes, allowMalformed: true);
        setState(() {
          _status = 'Boot OK. tick=$state';
          _output = text.isEmpty ? '(no output yet)' : text;
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
              'C ABI over KernelHost (not JS). See docs/native-host-ffi.md',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _smokeBoot,
              child: Text(_busy ? 'Working…' : 'Smoke-boot kernel'),
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

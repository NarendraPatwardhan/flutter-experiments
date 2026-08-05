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
  String _status = 'Starting AgentOS (loom guest)…';
  String _output = '';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _smoke());
  }

  ({String lib, String kernel, String? image})? _locateAssets() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final libCandidates = [
      '$exeDir/lib/libagentos_flutter_host.so',
      '$exeDir/libagentos_flutter_host.so',
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
    String? libPath;
    String? kernelPath;
    String? imagePath;
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
    for (final p in imageCandidates) {
      if (File(p).existsSync()) {
        imagePath = p;
        break;
      }
    }
    if (libPath == null || kernelPath == null) return null;
    return (lib: libPath, kernel: kernelPath, image: imagePath);
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
              'Need lib/libagentos_flutter_host.so, data/kernel.wasm, data/loom.tar.';
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

      final imageName = assets.image!.split(Platform.pathSeparator).last;
      setState(() => _status = 'Booting kernel + $imageName…');
      final vm = await AgentOsVm.bootFromFiles(
        kernelPath: assets.kernel,
        imagePath: assets.image,
        libraryPath: assets.lib,
      );
      try {
        for (var i = 0; i < 64; i++) {
          final s = await vm.tick();
          if (s == AgentOsTickState.exited || s == AgentOsTickState.waiting) {
            break;
          }
        }
        final bootBytes = await vm.takeOutput();
        final bootText = utf8.decode(bootBytes, allowMalformed: true);

        setState(() => _status = 'Running guest commands…');
        final echo = await vm.exec('echo Hello from AgentOS');
        final uname = await vm.exec('uname -a');
        final ls = await vm.exec('ls /bin | head -n 20');

        final text = StringBuffer()
          ..writeln('=== shell after boot ($imageName) ===')
          ..writeln(
            bootText.isEmpty ? '(no capture yet — shell may be quiet)' : bootText,
          )
          ..writeln()
          ..writeln(
            '=== echo Hello from AgentOS  (exit ${echo.exitCode}) ===',
          )
          ..writeln(utf8.decode(echo.stdout, allowMalformed: true))
          ..write(utf8.decode(echo.stderr, allowMalformed: true))
          ..writeln()
          ..writeln('=== uname -a  (exit ${uname.exitCode}) ===')
          ..writeln(utf8.decode(uname.stdout, allowMalformed: true))
          ..write(utf8.decode(uname.stderr, allowMalformed: true))
          ..writeln()
          ..writeln('=== ls /bin | head  (exit ${ls.exitCode}) ===')
          ..writeln(utf8.decode(ls.stdout, allowMalformed: true))
          ..write(utf8.decode(ls.stderr, allowMalformed: true));

        setState(() {
          _status =
              'OK — guest ran (echo=${echo.exitCode}, uname=${uname.exitCode}, ls=${ls.exitCode})';
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
              'AgentOS on Flutter',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Native host · kernel + loom guest image · auto-runs on launch',
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

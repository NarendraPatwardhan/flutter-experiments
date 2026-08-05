import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'bindings.dart';

/// Tick state from aos_vm_tick (matches agentos_flutter_host.h).
enum AgentOsTickState {
  runnable,
  waiting,
  exited,
}

/// Single-owner AgentOS VM over the product C ABI.
class AgentOsVm {
  AgentOsVm._(this._handle, this._libraryPath);

  final int _handle;
  final String? _libraryPath;
  bool _closed = false;

  /// Boot [kernelBytes] with optional base image tar (e.g. loom.tar).
  static Future<AgentOsVm> boot(
    Uint8List kernelBytes, {
    Uint8List? imageBytes,
    String? libraryPath,
  }) {
    final path = libraryPath;
    final kernel = Uint8List.fromList(kernelBytes);
    final image = imageBytes == null ? null : Uint8List.fromList(imageBytes);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final kPtr = mallocBytes<Uint8>(kernel.length, sizeOf<Uint8>());
      final out = mallocBytes<Uint64>(1, sizeOf<Uint64>());
      Pointer<Uint8> iPtr = nullptr;
      try {
        kPtr.asTypedList(kernel.length).setAll(0, kernel);
        var imageLen = 0;
        if (image != null && image.isNotEmpty) {
          iPtr = mallocBytes<Uint8>(image.length, sizeOf<Uint8>());
          iPtr.asTypedList(image.length).setAll(0, image);
          imageLen = image.length;
        }
        final rc = native.boot(kPtr, kernel.length, iPtr, imageLen, out);
        if (rc != 0) {
          throw StateError('aos_vm_boot failed: ${native.errorMessage()}');
        }
        return out.value;
      } finally {
        freePtr(kPtr);
        freePtr(out);
        if (iPtr != nullptr) freePtr(iPtr);
      }
    }).then((handle) => AgentOsVm._(handle, path));
  }

  static Future<AgentOsVm> bootFromFiles({
    required String kernelPath,
    String? imagePath,
    String? libraryPath,
  }) async {
    final kernel = await File(kernelPath).readAsBytes();
    final image =
        imagePath == null ? null : await File(imagePath).readAsBytes();
    return boot(
      Uint8List.fromList(kernel),
      imageBytes: image == null ? null : Uint8List.fromList(image),
      libraryPath: libraryPath,
    );
  }

  Future<AgentOsTickState> tick() {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = mallocBytes<Int32>(1, sizeOf<Int32>());
      try {
        final rc = native.tick(handle, out);
        if (rc != 0) {
          throw StateError('aos_vm_tick failed: ${native.errorMessage()}');
        }
        return switch (out.value) {
          0 => AgentOsTickState.runnable,
          1 => AgentOsTickState.waiting,
          2 => AgentOsTickState.exited,
          _ => AgentOsTickState.waiting,
        };
      } finally {
        freePtr(out);
      }
    });
  }

  Future<void> sendInput(Uint8List data) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final copy = Uint8List.fromList(data);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      if (copy.isEmpty) {
        final rc = native.sendInput(handle, nullptr, 0);
        if (rc != 0) {
          throw StateError('aos_vm_send_input failed: ${native.errorMessage()}');
        }
        return;
      }
      final buf = mallocBytes<Uint8>(copy.length, sizeOf<Uint8>());
      try {
        buf.asTypedList(copy.length).setAll(0, copy);
        final rc = native.sendInput(handle, buf, copy.length);
        if (rc != 0) {
          throw StateError('aos_vm_send_input failed: ${native.errorMessage()}');
        }
      } finally {
        freePtr(buf);
      }
    });
  }

  Future<Uint8List> takeOutput({int capacity = 65536}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final buf = mallocBytes<Uint8>(capacity, sizeOf<Uint8>());
      try {
        final n = native.takeOutput(handle, buf, capacity);
        if (n < 0) {
          throw StateError('aos_vm_take_output failed: ${native.errorMessage()}');
        }
        if (n == 0) return Uint8List(0);
        return Uint8List.fromList(buf.asTypedList(n));
      } finally {
        freePtr(buf);
      }
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final handle = _handle;
    final path = _libraryPath;
    await Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.close(handle);
      if (rc != 0) {
        throw StateError('aos_vm_close failed: ${native.errorMessage()}');
      }
    });
  }

  Future<AgentOsExecResult> exec(
    String cmd, {
    int maxTicks = 0,
    int stdoutCap = 256 * 1024,
    int stderrCap = 64 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final cmdUnits = [...cmd.codeUnits, 0];
      final cmdPtr = mallocBytes<Uint8>(cmdUnits.length, sizeOf<Uint8>());
      final stdoutBuf = mallocBytes<Uint8>(stdoutCap, sizeOf<Uint8>());
      final stderrBuf = mallocBytes<Uint8>(stderrCap, sizeOf<Uint8>());
      final stdoutLen = mallocBytes<Size>(1, sizeOf<Size>());
      final stderrLen = mallocBytes<Size>(1, sizeOf<Size>());
      final outExit = mallocBytes<Int32>(1, sizeOf<Int32>());
      try {
        cmdPtr.asTypedList(cmdUnits.length).setAll(0, cmdUnits);
        final rc = native.exec(
          handle,
          cmdPtr,
          maxTicks,
          stdoutBuf,
          stdoutCap,
          stdoutLen,
          stderrBuf,
          stderrCap,
          stderrLen,
          outExit,
        );
        if (rc != 0) {
          throw StateError('aos_vm_exec failed: ${native.errorMessage()}');
        }
        final so = stdoutLen.value;
        final se = stderrLen.value;
        return AgentOsExecResult(
          exitCode: outExit.value,
          stdout: so == 0
              ? Uint8List(0)
              : Uint8List.fromList(stdoutBuf.asTypedList(so)),
          stderr: se == 0
              ? Uint8List(0)
              : Uint8List.fromList(stderrBuf.asTypedList(se)),
        );
      } finally {
        freePtr(cmdPtr);
        freePtr(stdoutBuf);
        freePtr(stderrBuf);
        freePtr(stdoutLen);
        freePtr(stderrLen);
        freePtr(outExit);
      }
    });
  }

  void _ensureOpen() {
    if (_closed) throw StateError('AgentOsVm is closed');
  }
}

class AgentOsExecResult {
  const AgentOsExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final Uint8List stdout;
  final Uint8List stderr;
}

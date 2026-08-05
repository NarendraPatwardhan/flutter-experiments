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
///
/// Native handles live in the process-wide host table inside the cdylib.
/// Long work runs on a worker isolate (DirtyCpu analogue).
class AgentOsVm {
  AgentOsVm._(this._handle, this._libraryPath);

  final int _handle;
  final String? _libraryPath;
  bool _closed = false;

  static Future<AgentOsVm> boot(
    Uint8List kernelBytes, {
    String? libraryPath,
  }) {
    final path = libraryPath;
    final bytes = Uint8List.fromList(kernelBytes);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final kernel = mallocBytes<Uint8>(bytes.length, sizeOf<Uint8>());
      final out = mallocBytes<Uint64>(1, sizeOf<Uint64>());
      try {
        kernel.asTypedList(bytes.length).setAll(0, bytes);
        final rc = native.boot(kernel, bytes.length, out);
        if (rc != 0) {
          throw StateError('aos_vm_boot failed: ${native.errorMessage()}');
        }
        return out.value;
      } finally {
        freePtr(kernel);
        freePtr(out);
      }
    }).then((handle) => AgentOsVm._(handle, path));
  }

  static Future<AgentOsVm> bootFromFile(
    String kernelPath, {
    String? libraryPath,
  }) async {
    final fileBytes = await File(kernelPath).readAsBytes();
    return boot(Uint8List.fromList(fileBytes), libraryPath: libraryPath);
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

  void _ensureOpen() {
    if (_closed) throw StateError('AgentOsVm is closed');
  }
}

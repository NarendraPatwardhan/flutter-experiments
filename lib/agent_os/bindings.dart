// Hand-written dart:ffi bindings for agentos_flutter_host.h (first cut).
// Keep in sync with native/agentos_flutter_host/include/agentos_flutter_host.h
// No package:ffi — only dart:ffi + libc malloc.

import 'dart:ffi';
import 'dart:io';

final DynamicLibrary _libc = Platform.isLinux
    ? DynamicLibrary.open('libc.so.6')
    : DynamicLibrary.process();

final Pointer<Void> Function(int) _malloc = _libc
    .lookup<NativeFunction<Pointer<Void> Function(IntPtr)>>('malloc')
    .asFunction();

final void Function(Pointer<Void>) _free = _libc
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('free')
    .asFunction();

Pointer<T> mallocBytes<T extends NativeType>(int count, int sizeOfT) {
  final p = _malloc(count * sizeOfT);
  if (p == nullptr) {
    throw StateError('malloc failed');
  }
  return p.cast();
}

void freePtr(Pointer p) => _free(p.cast());

typedef _BootNative = Int32 Function(
  Pointer<Uint8> kernel,
  Size kernelLen,
  Pointer<Uint64> outVm,
);
typedef _BootDart = int Function(
  Pointer<Uint8> kernel,
  int kernelLen,
  Pointer<Uint64> outVm,
);

typedef _TickNative = Int32 Function(Uint64 vm, Pointer<Int32> outState);
typedef _TickDart = int Function(int vm, Pointer<Int32> outState);

typedef _SendInputNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> data,
  Size len,
);
typedef _SendInputDart = int Function(int vm, Pointer<Uint8> data, int len);

typedef _TakeOutputNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> buf,
  Size cap,
);
typedef _TakeOutputDart = int Function(int vm, Pointer<Uint8> buf, int cap);

typedef _CloseNative = Int32 Function(Uint64 vm);
typedef _CloseDart = int Function(int vm);

typedef _ExecNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> cmd,
  Uint64 maxTicks,
  Pointer<Uint8> stdoutBuf,
  Size stdoutCap,
  Pointer<Size> stdoutLen,
  Pointer<Uint8> stderrBuf,
  Size stderrCap,
  Pointer<Size> stderrLen,
  Pointer<Int32> outExit,
);
typedef _ExecDart = int Function(
  int vm,
  Pointer<Uint8> cmd,
  int maxTicks,
  Pointer<Uint8> stdoutBuf,
  int stdoutCap,
  Pointer<Size> stdoutLen,
  Pointer<Uint8> stderrBuf,
  int stderrCap,
  Pointer<Size> stderrLen,
  Pointer<Int32> outExit,
);

typedef _LastErrorNative = Pointer<Uint8> Function();
typedef _LastErrorDart = Pointer<Uint8> Function();

/// Low-level bindings to `libagentos_flutter_host`.
class AgentOsNative {
  AgentOsNative._(this._lib)
      : boot = _lib.lookupFunction<_BootNative, _BootDart>('aos_vm_boot'),
        tick = _lib.lookupFunction<_TickNative, _TickDart>('aos_vm_tick'),
        sendInput =
            _lib.lookupFunction<_SendInputNative, _SendInputDart>('aos_vm_send_input'),
        takeOutput =
            _lib.lookupFunction<_TakeOutputNative, _TakeOutputDart>('aos_vm_take_output'),
        close = _lib.lookupFunction<_CloseNative, _CloseDart>('aos_vm_close'),
        exec = _lib.lookupFunction<_ExecNative, _ExecDart>('aos_vm_exec'),
        lastError =
            _lib.lookupFunction<_LastErrorNative, _LastErrorDart>('aos_last_error');

  final DynamicLibrary _lib;

  final _BootDart boot;
  final _TickDart tick;
  final _SendInputDart sendInput;
  final _TakeOutputDart takeOutput;
  final _CloseDart close;
  final _ExecDart exec;
  final _LastErrorDart lastError;

  static AgentOsNative open([String? path]) {
    final p = path ?? _defaultLibPath();
    return AgentOsNative._(DynamicLibrary.open(p));
  }

  static String _defaultLibPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir/lib/libagentos_flutter_host.so',
      '$exeDir/libagentos_flutter_host.so',
      'libagentos_flutter_host.so',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return candidates.first;
  }

  String errorMessage() {
    final p = lastError();
    if (p == nullptr) return 'unknown error';
    // Read C string until NUL.
    final units = <int>[];
    for (var i = 0;; i++) {
      final b = p[i];
      if (b == 0) break;
      units.add(b);
    }
    return String.fromCharCodes(units);
  }
}

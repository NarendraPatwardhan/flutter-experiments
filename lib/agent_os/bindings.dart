// Hand-written dart:ffi bindings for agentos_flutter_host.h.
// Keep in sync with native/agentos_flutter_host/include/agentos_flutter_host.h

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

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

// --- Status / constants (match header enums) --------------------------------

const int kAosOk = 0;
const int kAosErr = -1;

const int kAosTickRunnable = 0;
const int kAosTickWaiting = 1;
const int kAosTickExited = 2;

const int kAosNetDeny = 0;
const int kAosNetRelay = 1;
const int kAosNetReal = 2;

const int kAosCapDeny = 0;
const int kAosCapRelay = 1;

const int kAosStreamStdout = 1;
const int kAosStreamStderr = 2;
const int kAosStreamLog = 4;

const int kAosApiVersion = 1;

// --- Native structs ---------------------------------------------------------

/// Caller-owned byte buffer: set ptr/cap; on success len = written.
final class AosBuf extends Struct {
  external Pointer<Uint8> ptr;

  @Size()
  external int cap;

  @Size()
  external int len;
}

/// Library-allocated blob; free with [AgentOsNative.bytesFree].
final class AosBytes extends Struct {
  external Pointer<Uint8> ptr;

  @Size()
  external int len;
}

final class AosBootOpts extends Struct {
  @Size()
  external int size;

  external Pointer<Uint8> baseImage;

  @Size()
  external int baseImageLen;

  external Pointer<Pointer<Uint8>> layers;

  external Pointer<Size> layerLens;

  @Size()
  external int layerCount;

  @Int32()
  external int deterministic;

  @Int32()
  external int hasContract;

  @Int32()
  external int contractTier;

  @Int32()
  external int contractBudgetMib;

  @Int64()
  external int contractFuel;

  @Uint32()
  external int workers;

  @Int32()
  external int net;

  @Int32()
  external int hostCall;

  @Int32()
  external int hostCallSidecarOnly;

  @Int32()
  external int persist;

  @Int32()
  external int toolApproval;

  external Pointer<Uint8> connectionsBlob;

  @Size()
  external int connectionsLen;

  external Pointer<Uint8> connectionPoliciesBlob;

  @Size()
  external int connectionPoliciesLen;
}

final class AosExecOpts extends Struct {
  @Size()
  external int size;

  external Pointer<Uint8> cwd;

  external Pointer<Uint8> envBlob;

  @Size()
  external int envBlobLen;

  external Pointer<Uint8> stdinData;

  @Size()
  external int stdinLen;

  @Uint64()
  external int maxTicks;
}

final class AosVmStatus extends Struct {
  @Size()
  external int size;

  @Uint64()
  external int bytesWritten;

  @Int32()
  external int exitCode;

  @Int32()
  external int atPrompt;

  @Uint32()
  external int workers;

  @Int32()
  external int hasWorkerEntry;

  @Uint32()
  external int inflightEgress;

  @Uint32()
  external int pendingCommits;
}

final class AosStat extends Struct {
  @Uint64()
  external int size;

  @Int32()
  external int isDir;

  @Int32()
  external int isSymlink;

  @Uint32()
  external int nlink;

  @Uint32()
  external int mode;
}

// --- AosBuf / string helpers ------------------------------------------------

/// Allocate a zeroed [AosBuf] with a [capacity]-byte data region (or null ptr if 0).
Pointer<AosBuf> allocAosBuf(int capacity) {
  final p = mallocBytes<AosBuf>(1, sizeOf<AosBuf>());
  if (capacity > 0) {
    p.ref.ptr = mallocBytes<Uint8>(capacity, sizeOf<Uint8>());
  } else {
    p.ref.ptr = nullptr;
  }
  p.ref.cap = capacity;
  p.ref.len = 0;
  return p;
}

void freeAosBuf(Pointer<AosBuf> p) {
  if (p == nullptr) return;
  if (p.ref.ptr != nullptr) freePtr(p.ref.ptr);
  freePtr(p);
}

/// Copy bytes currently reported by the buffer (capped to [AosBuf.cap]).
Uint8List copyFromAosBuf(Pointer<AosBuf> p) {
  final n = p.ref.len;
  if (n <= 0 || p.ref.ptr == nullptr || p.ref.cap <= 0) return Uint8List(0);
  final take = n > p.ref.cap ? p.ref.cap : n;
  return Uint8List.fromList(p.ref.ptr.asTypedList(take));
}

/// Copy library-owned bytes then free via [bytesFree].
Uint8List takeAosBytes(AgentOsNative native, Pointer<AosBytes> p) {
  final n = p.ref.len;
  final Uint8List out;
  if (n == 0 || p.ref.ptr == nullptr) {
    out = Uint8List(0);
  } else {
    out = Uint8List.fromList(p.ref.ptr.asTypedList(n));
  }
  native.bytesFree(p);
  return out;
}

/// NUL-terminated C string (UTF-16 code units for ASCII-safe paths; use utf8 for full Unicode).
Pointer<Uint8> allocCString(String s) {
  final units = s.codeUnits;
  final p = mallocBytes<Uint8>(units.length + 1, sizeOf<Uint8>());
  final view = p.asTypedList(units.length + 1);
  for (var i = 0; i < units.length; i++) {
    view[i] = units[i] & 0xff;
  }
  view[units.length] = 0;
  return p;
}

Pointer<Uint8> allocBytes(Uint8List data) {
  if (data.isEmpty) return nullptr;
  final p = mallocBytes<Uint8>(data.length, sizeOf<Uint8>());
  p.asTypedList(data.length).setAll(0, data);
  return p;
}

String cStringToDart(Pointer<Uint8> p) {
  if (p == nullptr) return '';
  final units = <int>[];
  for (var i = 0;; i++) {
    final b = p[i];
    if (b == 0) break;
    units.add(b);
  }
  return String.fromCharCodes(units);
}

// --- Native / Dart function types -------------------------------------------

typedef _ApiVersionNative = Int32 Function();
typedef _ApiVersionDart = int Function();

typedef _VersionNative = Pointer<Uint8> Function();
typedef _VersionDart = Pointer<Uint8> Function();

typedef _LastErrorNative = Pointer<Uint8> Function();
typedef _LastErrorDart = Pointer<Uint8> Function();

typedef _BytesFreeNative = Void Function(Pointer<AosBytes> b);
typedef _BytesFreeDart = void Function(Pointer<AosBytes> b);

typedef _BootNative = Int32 Function(
  Pointer<Uint8> kernel,
  Size kernelLen,
  Pointer<Uint8> image,
  Size imageLen,
  Pointer<Uint64> outVm,
);
typedef _BootDart = int Function(
  Pointer<Uint8> kernel,
  int kernelLen,
  Pointer<Uint8> image,
  int imageLen,
  Pointer<Uint64> outVm,
);

typedef _BootExNative = Int32 Function(
  Pointer<Uint8> kernel,
  Size kernelLen,
  Pointer<AosBootOpts> opts,
  Pointer<Uint64> outVm,
);
typedef _BootExDart = int Function(
  Pointer<Uint8> kernel,
  int kernelLen,
  Pointer<AosBootOpts> opts,
  Pointer<Uint64> outVm,
);

typedef _RestoreNative = Int32 Function(
  Pointer<Uint8> kernel,
  Size kernelLen,
  Pointer<Uint8> snapshot,
  Size snapshotLen,
  Pointer<Uint8> baseSnapshot,
  Size baseSnapshotLen,
  Pointer<AosBootOpts> opts,
  Pointer<Uint64> outVm,
);
typedef _RestoreDart = int Function(
  Pointer<Uint8> kernel,
  int kernelLen,
  Pointer<Uint8> snapshot,
  int snapshotLen,
  Pointer<Uint8> baseSnapshot,
  int baseSnapshotLen,
  Pointer<AosBootOpts> opts,
  Pointer<Uint64> outVm,
);

typedef _CloseNative = Int32 Function(Uint64 vm);
typedef _CloseDart = int Function(int vm);

typedef _TickNative = Int32 Function(Uint64 vm, Pointer<Int32> outState);
typedef _TickDart = int Function(int vm, Pointer<Int32> outState);

typedef _TickNNative = Int32 Function(
  Uint64 vm,
  Uint32 n,
  Pointer<Int32> outState,
);
typedef _TickNDart = int Function(int vm, int n, Pointer<Int32> outState);

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

typedef _TakeOutputExNative = Int32 Function(
  Uint64 vm,
  Int32 streamMask,
  Pointer<AosBuf> out,
);
typedef _TakeOutputExDart = int Function(
  int vm,
  int streamMask,
  Pointer<AosBuf> out,
);

typedef _StatusNative = Int32 Function(Uint64 vm, Pointer<AosVmStatus> out);
typedef _StatusDart = int Function(int vm, Pointer<AosVmStatus> out);

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

typedef _ExecExNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> cmd,
  Pointer<AosExecOpts> opts,
  Pointer<AosBuf> stdoutB,
  Pointer<AosBuf> stderrB,
  Pointer<Int32> outExit,
);
typedef _ExecExDart = int Function(
  int vm,
  Pointer<Uint8> cmd,
  Pointer<AosExecOpts> opts,
  Pointer<AosBuf> stdoutB,
  Pointer<AosBuf> stderrB,
  Pointer<Int32> outExit,
);

typedef _RunNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> program,
  Pointer<Pointer<Uint8>> argv,
  Size argc,
  Pointer<AosExecOpts> opts,
  Pointer<AosBuf> stdoutB,
  Pointer<AosBuf> stderrB,
  Pointer<Int32> outExit,
);
typedef _RunDart = int Function(
  int vm,
  Pointer<Uint8> program,
  Pointer<Pointer<Uint8>> argv,
  int argc,
  Pointer<AosExecOpts> opts,
  Pointer<AosBuf> stdoutB,
  Pointer<AosBuf> stderrB,
  Pointer<Int32> outExit,
);

typedef _ExecStartNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> cmd,
  Pointer<AosExecOpts> opts,
  Pointer<Int64> outJob,
);
typedef _ExecStartDart = int Function(
  int vm,
  Pointer<Uint8> cmd,
  Pointer<AosExecOpts> opts,
  Pointer<Int64> outJob,
);

typedef _RunStartNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> program,
  Pointer<Pointer<Uint8>> argv,
  Size argc,
  Pointer<AosExecOpts> opts,
  Pointer<Int64> outJob,
);
typedef _RunStartDart = int Function(
  int vm,
  Pointer<Uint8> program,
  Pointer<Pointer<Uint8>> argv,
  int argc,
  Pointer<AosExecOpts> opts,
  Pointer<Int64> outJob,
);

typedef _ExecPollNative = Int32 Function(
  Uint64 vm,
  Int64 job,
  Pointer<Int32> outDone,
  Pointer<Int32> outExit,
  Pointer<AosBuf> stdoutB,
  Pointer<AosBuf> stderrB,
);
typedef _ExecPollDart = int Function(
  int vm,
  int job,
  Pointer<Int32> outDone,
  Pointer<Int32> outExit,
  Pointer<AosBuf> stdoutB,
  Pointer<AosBuf> stderrB,
);

typedef _ExecStdoutPeekNative = Int32 Function(
  Uint64 vm,
  Int64 job,
  Pointer<AosBuf> out,
);
typedef _ExecStdoutPeekDart = int Function(
  int vm,
  int job,
  Pointer<AosBuf> out,
);

typedef _ExecCancelNative = Int32 Function(Uint64 vm, Int64 job);
typedef _ExecCancelDart = int Function(int vm, int job);

typedef _AutocompleteNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> source,
  Size cursorByte,
  Pointer<AosExecOpts> opts,
  Pointer<AosBuf> outEncoded,
);
typedef _AutocompleteDart = int Function(
  int vm,
  Pointer<Uint8> source,
  int cursorByte,
  Pointer<AosExecOpts> opts,
  Pointer<AosBuf> outEncoded,
);

typedef _SvcCallNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> service,
  Pointer<Uint8> req,
  Size reqLen,
  Pointer<Int32> outStatus,
  Pointer<AosBuf> outBody,
);
typedef _SvcCallDart = int Function(
  int vm,
  Pointer<Uint8> service,
  Pointer<Uint8> req,
  int reqLen,
  Pointer<Int32> outStatus,
  Pointer<AosBuf> outBody,
);

typedef _ReadFileNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Pointer<AosBuf> out,
);
typedef _ReadFileDart = int Function(
  int vm,
  Pointer<Uint8> path,
  Pointer<AosBuf> out,
);

typedef _WriteFileNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Pointer<Uint8> data,
  Size len,
);
typedef _WriteFileDart = int Function(
  int vm,
  Pointer<Uint8> path,
  Pointer<Uint8> data,
  int len,
);

typedef _ReaddirNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Pointer<AosBuf> outEncoded,
);
typedef _ReaddirDart = int Function(
  int vm,
  Pointer<Uint8> path,
  Pointer<AosBuf> outEncoded,
);

typedef _StatNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Pointer<AosStat> out,
);
typedef _StatDart = int Function(
  int vm,
  Pointer<Uint8> path,
  Pointer<AosStat> out,
);

typedef _ReadlinkNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Pointer<AosBuf> out,
);
typedef _ReadlinkDart = int Function(
  int vm,
  Pointer<Uint8> path,
  Pointer<AosBuf> out,
);

typedef _MkdirNative = Int32 Function(Uint64 vm, Pointer<Uint8> path);
typedef _MkdirDart = int Function(int vm, Pointer<Uint8> path);

typedef _UnlinkNative = Int32 Function(Uint64 vm, Pointer<Uint8> path);
typedef _UnlinkDart = int Function(int vm, Pointer<Uint8> path);

typedef _ChmodNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Uint32 mode,
);
typedef _ChmodDart = int Function(int vm, Pointer<Uint8> path, int mode);

typedef _SymlinkNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> target,
  Pointer<Uint8> linkPath,
);
typedef _SymlinkDart = int Function(
  int vm,
  Pointer<Uint8> target,
  Pointer<Uint8> linkPath,
);

typedef _MountNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> path,
  Int32 readOnly,
);
typedef _MountDart = int Function(int vm, Pointer<Uint8> path, int readOnly);

typedef _UnmountNative = Int32 Function(Uint64 vm, Pointer<Uint8> path);
typedef _UnmountDart = int Function(int vm, Pointer<Uint8> path);

typedef _SnapshotNative = Int32 Function(Uint64 vm, Pointer<AosBytes> out);
typedef _SnapshotDart = int Function(int vm, Pointer<AosBytes> out);

typedef _SnapshotIntoNative = Int32 Function(Uint64 vm, Pointer<AosBuf> out);
typedef _SnapshotIntoDart = int Function(int vm, Pointer<AosBuf> out);

typedef _SnapshotIncrementalNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> base,
  Size baseLen,
  Pointer<AosBytes> out,
);
typedef _SnapshotIncrementalDart = int Function(
  int vm,
  Pointer<Uint8> base,
  int baseLen,
  Pointer<AosBytes> out,
);

typedef _CommitLayerNative = Int32 Function(
  Uint64 vm,
  Pointer<AosBytes> outTar,
  Pointer<AosBuf> outDigestHex,
);
typedef _CommitLayerDart = int Function(
  int vm,
  Pointer<AosBytes> outTar,
  Pointer<AosBuf> outDigestHex,
);

typedef _RelayNextNative = Int32 Function(Uint64 vm, Pointer<AosBuf> outFrame);
typedef _RelayNextDart = int Function(int vm, Pointer<AosBuf> outFrame);

typedef _RelayHttpRespondNative = Int32 Function(
  Uint64 vm,
  Int64 handle,
  Int32 ok,
  Pointer<Uint8> head,
  Size headLen,
  Pointer<Uint8> body,
  Size bodyLen,
);
typedef _RelayHttpRespondDart = int Function(
  int vm,
  int handle,
  int ok,
  Pointer<Uint8> head,
  int headLen,
  Pointer<Uint8> body,
  int bodyLen,
);

typedef _RelayHostCallRespondNative = Int32 Function(
  Uint64 vm,
  Int64 handle,
  Int32 ok,
  Pointer<Uint8> result,
  Size resultLen,
);
typedef _RelayHostCallRespondDart = int Function(
  int vm,
  int handle,
  int ok,
  Pointer<Uint8> result,
  int resultLen,
);

typedef _RelayPersistRespondNative = Int32 Function(
  Uint64 vm,
  Int64 handle,
  Int32 ok,
  Pointer<Uint8> body,
  Size bodyLen,
);
typedef _RelayPersistRespondDart = int Function(
  int vm,
  int handle,
  int ok,
  Pointer<Uint8> body,
  int bodyLen,
);

typedef _RelayToolApprovalRespondNative = Int32 Function(
  Uint64 vm,
  Int64 handle,
  Int32 allow,
  Int32 rememberSession,
);
typedef _RelayToolApprovalRespondDart = int Function(
  int vm,
  int handle,
  int allow,
  int rememberSession,
);

typedef _RelayWsOpenNative = Int32 Function(
  Uint64 vm,
  Int64 handle,
  Int32 ok,
);
typedef _RelayWsOpenDart = int Function(int vm, int handle, int ok);

typedef _RelayWsPushNative = Int32 Function(
  Uint64 vm,
  Int64 handle,
  Pointer<Uint8> data,
  Size len,
);
typedef _RelayWsPushDart = int Function(
  int vm,
  int handle,
  Pointer<Uint8> data,
  int len,
);

typedef _RelayWsCloseNative = Int32 Function(Uint64 vm, Int64 handle);
typedef _RelayWsCloseDart = int Function(int vm, int handle);

typedef _InjectCatalogNative = Int32 Function(
  Uint64 vm,
  Pointer<Uint8> compilerWasm,
  Size compilerLen,
  Uint64 generation,
  Pointer<Uint8> catalogBlob,
  Size catalogLen,
  Pointer<AosBuf> outStatusEncoded,
);
typedef _InjectCatalogDart = int Function(
  int vm,
  Pointer<Uint8> compilerWasm,
  int compilerLen,
  int generation,
  Pointer<Uint8> catalogBlob,
  int catalogLen,
  Pointer<AosBuf> outStatusEncoded,
);

typedef _SetPerfEnabledNative = Int32 Function(Uint64 vm, Int32 on);
typedef _SetPerfEnabledDart = int Function(int vm, int on);

typedef _ScrubPerfNative = Int32 Function(Uint64 vm);
typedef _ScrubPerfDart = int Function(int vm);

typedef _TakeCommandPerfNative = Int32 Function(
  Uint64 vm,
  Pointer<AosBuf> outEncoded,
);
typedef _TakeCommandPerfDart = int Function(
  int vm,
  Pointer<AosBuf> outEncoded,
);

/// Low-level bindings to `libagentos_flutter_host`.
class AgentOsNative {
  AgentOsNative._(this._lib)
      : apiVersion =
            _lib.lookupFunction<_ApiVersionNative, _ApiVersionDart>(
                'aos_api_version'),
        version =
            _lib.lookupFunction<_VersionNative, _VersionDart>('aos_version'),
        lastError =
            _lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
                'aos_last_error'),
        bytesFree =
            _lib.lookupFunction<_BytesFreeNative, _BytesFreeDart>(
                'aos_bytes_free'),
        boot = _lib.lookupFunction<_BootNative, _BootDart>('aos_vm_boot'),
        bootEx =
            _lib.lookupFunction<_BootExNative, _BootExDart>('aos_vm_boot_ex'),
        restore =
            _lib.lookupFunction<_RestoreNative, _RestoreDart>('aos_vm_restore'),
        close = _lib.lookupFunction<_CloseNative, _CloseDart>('aos_vm_close'),
        tick = _lib.lookupFunction<_TickNative, _TickDart>('aos_vm_tick'),
        tickN =
            _lib.lookupFunction<_TickNNative, _TickNDart>('aos_vm_tick_n'),
        sendInput = _lib
            .lookupFunction<_SendInputNative, _SendInputDart>(
                'aos_vm_send_input'),
        takeOutput = _lib
            .lookupFunction<_TakeOutputNative, _TakeOutputDart>(
                'aos_vm_take_output'),
        takeOutputEx = _lib
            .lookupFunction<_TakeOutputExNative, _TakeOutputExDart>(
                'aos_vm_take_output_ex'),
        status =
            _lib.lookupFunction<_StatusNative, _StatusDart>('aos_vm_status'),
        exec = _lib.lookupFunction<_ExecNative, _ExecDart>('aos_vm_exec'),
        execEx =
            _lib.lookupFunction<_ExecExNative, _ExecExDart>('aos_vm_exec_ex'),
        run = _lib.lookupFunction<_RunNative, _RunDart>('aos_vm_run'),
        execStart = _lib
            .lookupFunction<_ExecStartNative, _ExecStartDart>(
                'aos_vm_exec_start'),
        runStart = _lib
            .lookupFunction<_RunStartNative, _RunStartDart>('aos_vm_run_start'),
        execPoll = _lib
            .lookupFunction<_ExecPollNative, _ExecPollDart>('aos_vm_exec_poll'),
        execStdoutPeek = _lib.lookupFunction<_ExecStdoutPeekNative,
            _ExecStdoutPeekDart>('aos_vm_exec_stdout_peek'),
        execCancel = _lib
            .lookupFunction<_ExecCancelNative, _ExecCancelDart>(
                'aos_vm_exec_cancel'),
        autocomplete = _lib.lookupFunction<_AutocompleteNative,
            _AutocompleteDart>('aos_vm_autocomplete'),
        svcCall = _lib
            .lookupFunction<_SvcCallNative, _SvcCallDart>('aos_vm_svc_call'),
        readFile = _lib
            .lookupFunction<_ReadFileNative, _ReadFileDart>('aos_vm_read_file'),
        writeFile = _lib.lookupFunction<_WriteFileNative, _WriteFileDart>(
            'aos_vm_write_file'),
        readdir =
            _lib.lookupFunction<_ReaddirNative, _ReaddirDart>('aos_vm_readdir'),
        stat = _lib.lookupFunction<_StatNative, _StatDart>('aos_vm_stat'),
        readlink = _lib
            .lookupFunction<_ReadlinkNative, _ReadlinkDart>('aos_vm_readlink'),
        mkdir = _lib.lookupFunction<_MkdirNative, _MkdirDart>('aos_vm_mkdir'),
        unlink =
            _lib.lookupFunction<_UnlinkNative, _UnlinkDart>('aos_vm_unlink'),
        chmod = _lib.lookupFunction<_ChmodNative, _ChmodDart>('aos_vm_chmod'),
        symlink =
            _lib.lookupFunction<_SymlinkNative, _SymlinkDart>('aos_vm_symlink'),
        mount = _lib.lookupFunction<_MountNative, _MountDart>('aos_vm_mount'),
        unmount =
            _lib.lookupFunction<_UnmountNative, _UnmountDart>('aos_vm_unmount'),
        snapshot = _lib
            .lookupFunction<_SnapshotNative, _SnapshotDart>('aos_vm_snapshot'),
        snapshotInto = _lib.lookupFunction<_SnapshotIntoNative,
            _SnapshotIntoDart>('aos_vm_snapshot_into'),
        snapshotIncremental = _lib.lookupFunction<_SnapshotIncrementalNative,
            _SnapshotIncrementalDart>('aos_vm_snapshot_incremental'),
        commitLayer = _lib.lookupFunction<_CommitLayerNative, _CommitLayerDart>(
            'aos_vm_commit_layer'),
        relayNext = _lib
            .lookupFunction<_RelayNextNative, _RelayNextDart>(
                'aos_vm_relay_next'),
        relayNextSidecar = _lib.lookupFunction<_RelayNextNative, _RelayNextDart>(
            'aos_vm_relay_next_sidecar'),
        relayHttpRespond = _lib.lookupFunction<_RelayHttpRespondNative,
            _RelayHttpRespondDart>('aos_vm_relay_http_respond'),
        relayHostCallRespond = _lib.lookupFunction<_RelayHostCallRespondNative,
            _RelayHostCallRespondDart>('aos_vm_relay_host_call_respond'),
        relayPersistRespond = _lib.lookupFunction<_RelayPersistRespondNative,
            _RelayPersistRespondDart>('aos_vm_relay_persist_respond'),
        relayToolApprovalRespond = _lib.lookupFunction<
                _RelayToolApprovalRespondNative,
                _RelayToolApprovalRespondDart>(
            'aos_vm_relay_tool_approval_respond'),
        relayWsOpen = _lib.lookupFunction<_RelayWsOpenNative, _RelayWsOpenDart>(
            'aos_vm_relay_ws_open'),
        relayWsPush = _lib
            .lookupFunction<_RelayWsPushNative, _RelayWsPushDart>(
                'aos_vm_relay_ws_push'),
        relayWsClose = _lib.lookupFunction<_RelayWsCloseNative, _RelayWsCloseDart>(
            'aos_vm_relay_ws_close'),
        injectCatalog = _lib.lookupFunction<_InjectCatalogNative,
            _InjectCatalogDart>('aos_vm_inject_catalog'),
        setPerfEnabled = _lib.lookupFunction<_SetPerfEnabledNative,
            _SetPerfEnabledDart>('aos_vm_set_perf_enabled'),
        scrubPerf = _lib
            .lookupFunction<_ScrubPerfNative, _ScrubPerfDart>(
                'aos_vm_scrub_perf'),
        takeCommandPerf = _lib.lookupFunction<_TakeCommandPerfNative,
            _TakeCommandPerfDart>('aos_vm_take_command_perf');

  final DynamicLibrary _lib;

  final _ApiVersionDart apiVersion;
  final _VersionDart version;
  final _LastErrorDart lastError;
  final _BytesFreeDart bytesFree;

  final _BootDart boot;
  final _BootExDart bootEx;
  final _RestoreDart restore;
  final _CloseDart close;

  final _TickDart tick;
  final _TickNDart tickN;
  final _SendInputDart sendInput;
  final _TakeOutputDart takeOutput;
  final _TakeOutputExDart takeOutputEx;
  final _StatusDart status;

  final _ExecDart exec;
  final _ExecExDart execEx;
  final _RunDart run;
  final _ExecStartDart execStart;
  final _RunStartDart runStart;
  final _ExecPollDart execPoll;
  final _ExecStdoutPeekDart execStdoutPeek;
  final _ExecCancelDart execCancel;
  final _AutocompleteDart autocomplete;

  final _SvcCallDart svcCall;
  final _ReadFileDart readFile;
  final _WriteFileDart writeFile;
  final _ReaddirDart readdir;
  final _StatDart stat;
  final _ReadlinkDart readlink;
  final _MkdirDart mkdir;
  final _UnlinkDart unlink;
  final _ChmodDart chmod;
  final _SymlinkDart symlink;
  final _MountDart mount;
  final _UnmountDart unmount;

  final _SnapshotDart snapshot;
  final _SnapshotIntoDart snapshotInto;
  final _SnapshotIncrementalDart snapshotIncremental;
  final _CommitLayerDart commitLayer;

  final _RelayNextDart relayNext;
  final _RelayNextDart relayNextSidecar;
  final _RelayHttpRespondDart relayHttpRespond;
  final _RelayHostCallRespondDart relayHostCallRespond;
  final _RelayPersistRespondDart relayPersistRespond;
  final _RelayToolApprovalRespondDart relayToolApprovalRespond;
  final _RelayWsOpenDart relayWsOpen;
  final _RelayWsPushDart relayWsPush;
  final _RelayWsCloseDart relayWsClose;

  final _InjectCatalogDart injectCatalog;
  final _SetPerfEnabledDart setPerfEnabled;
  final _ScrubPerfDart scrubPerf;
  final _TakeCommandPerfDart takeCommandPerf;

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
    return cStringToDart(p);
  }

  String versionString() {
    final p = version();
    if (p == nullptr) return '';
    return cStringToDart(p);
  }
}

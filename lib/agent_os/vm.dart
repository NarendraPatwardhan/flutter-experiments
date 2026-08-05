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

/// Network capability mode at boot.
enum AgentOsNetMode {
  deny,
  relay,
  real,
}

/// Generic capability mode (host_call / persist / tool_approval).
enum AgentOsCapMode {
  deny,
  relay,
}

AgentOsTickState _tickStateFromInt(int v) {
  return switch (v) {
    kAosTickRunnable => AgentOsTickState.runnable,
    kAosTickExited => AgentOsTickState.exited,
    _ => AgentOsTickState.waiting,
  };
}

int _netModeToInt(AgentOsNetMode m) => switch (m) {
      AgentOsNetMode.deny => kAosNetDeny,
      AgentOsNetMode.relay => kAosNetRelay,
      AgentOsNetMode.real => kAosNetReal,
    };

int _capModeToInt(AgentOsCapMode m) => switch (m) {
      AgentOsCapMode.deny => kAosCapDeny,
      AgentOsCapMode.relay => kAosCapRelay,
    };

/// Options for [AgentOsVm.bootEx] / [AgentOsVm.restore].
class AgentOsBootOptions {
  const AgentOsBootOptions({
    this.baseImage,
    this.layers,
    this.deterministic = false,
    this.contractTier,
    this.contractBudgetMib,
    this.contractFuel,
    this.workers = 0,
    this.net = AgentOsNetMode.deny,
    this.hostCall = AgentOsCapMode.deny,
    this.hostCallSidecarOnly = false,
    this.persist = AgentOsCapMode.deny,
    this.toolApproval = AgentOsCapMode.deny,
    this.connectionsBlob,
    this.connectionPoliciesBlob,
  });

  final Uint8List? baseImage;
  final List<Uint8List>? layers;
  final bool deterministic;
  final int? contractTier;
  final int? contractBudgetMib;
  final int? contractFuel;
  final int workers;
  final AgentOsNetMode net;
  final AgentOsCapMode hostCall;
  final bool hostCallSidecarOnly;
  final AgentOsCapMode persist;
  final AgentOsCapMode toolApproval;
  final Uint8List? connectionsBlob;
  final Uint8List? connectionPoliciesBlob;
}

/// Options for exec / run / autocomplete.
class AgentOsExecOptions {
  const AgentOsExecOptions({
    this.cwd,
    this.envBlob,
    this.stdinData,
    this.maxTicks = 0,
  });

  final String? cwd;
  final Uint8List? envBlob;
  final Uint8List? stdinData;
  final int maxTicks;
}

/// Result of [AgentOsVm.status].
class AgentOsVmStatusInfo {
  const AgentOsVmStatusInfo({
    required this.bytesWritten,
    required this.exitCode,
    required this.atPrompt,
    required this.workers,
    required this.hasWorkerEntry,
    required this.inflightEgress,
    required this.pendingCommits,
  });

  final int bytesWritten;
  /// INT32_MIN (-2147483648) means none.
  final int exitCode;
  final bool atPrompt;
  final int workers;
  final bool hasWorkerEntry;
  final int inflightEgress;
  final int pendingCommits;
}

/// Result of [AgentOsVm.stat].
class AgentOsFileStat {
  const AgentOsFileStat({
    required this.size,
    required this.isDir,
    required this.isSymlink,
    required this.nlink,
    required this.mode,
  });

  final int size;
  final bool isDir;
  final bool isSymlink;
  final int nlink;
  final int mode;
}

/// Result of blocking exec / run.
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

/// Result of [AgentOsVm.execPoll].
class AgentOsExecPollResult {
  const AgentOsExecPollResult({
    required this.done,
    this.exitCode,
    this.stdout,
    this.stderr,
  });

  final bool done;
  final int? exitCode;
  final Uint8List? stdout;
  final Uint8List? stderr;
}

/// Result of [AgentOsVm.svcCall].
class AgentOsSvcResult {
  const AgentOsSvcResult({
    required this.status,
    required this.body,
  });

  final int status;
  final Uint8List body;
}

/// Result of [AgentOsVm.commitLayer].
class AgentOsCommitLayerResult {
  const AgentOsCommitLayerResult({
    required this.tar,
    required this.digestHex,
  });

  final Uint8List tar;
  final Uint8List digestHex;
}

// ---------------------------------------------------------------------------
// Native option packing helpers (used inside Isolate.run only)
// ---------------------------------------------------------------------------

class _BootOptsNative {
  _BootOptsNative(this.ptr, this._owned);

  final Pointer<AosBootOpts> ptr;
  final List<Pointer> _owned;

  void free() {
    for (final p in _owned) {
      freePtr(p);
    }
    freePtr(ptr);
  }
}

_BootOptsNative? _packBootOpts(AgentOsBootOptions? opts) {
  if (opts == null) return null;
  final owned = <Pointer>[];
  final p = mallocBytes<AosBootOpts>(1, sizeOf<AosBootOpts>());
  p.ref.size = sizeOf<AosBootOpts>();
  p.ref.baseImage = nullptr;
  p.ref.baseImageLen = 0;
  p.ref.layers = nullptr;
  p.ref.layerLens = nullptr;
  p.ref.layerCount = 0;
  p.ref.deterministic = opts.deterministic ? 1 : 0;
  p.ref.hasContract = 0;
  p.ref.contractTier = 0;
  p.ref.contractBudgetMib = 0;
  p.ref.contractFuel = 0;
  p.ref.workers = opts.workers;
  p.ref.net = _netModeToInt(opts.net);
  p.ref.hostCall = _capModeToInt(opts.hostCall);
  p.ref.hostCallSidecarOnly = opts.hostCallSidecarOnly ? 1 : 0;
  p.ref.persist = _capModeToInt(opts.persist);
  p.ref.toolApproval = _capModeToInt(opts.toolApproval);
  p.ref.connectionsBlob = nullptr;
  p.ref.connectionsLen = 0;
  p.ref.connectionPoliciesBlob = nullptr;
  p.ref.connectionPoliciesLen = 0;

  if (opts.baseImage != null && opts.baseImage!.isNotEmpty) {
    final b = allocBytes(opts.baseImage!);
    owned.add(b);
    p.ref.baseImage = b;
    p.ref.baseImageLen = opts.baseImage!.length;
  }

  final layers = opts.layers;
  if (layers != null && layers.isNotEmpty) {
    final layerPtrs = mallocBytes<Pointer<Uint8>>(
      layers.length,
      sizeOf<Pointer<Uint8>>(),
    );
    final lens = mallocBytes<Size>(layers.length, sizeOf<Size>());
    owned.add(layerPtrs);
    owned.add(lens);
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (layer.isEmpty) {
        layerPtrs[i] = nullptr;
        lens[i] = 0;
      } else {
        final lp = allocBytes(layer);
        owned.add(lp);
        layerPtrs[i] = lp;
        lens[i] = layer.length;
      }
    }
    p.ref.layers = layerPtrs;
    p.ref.layerLens = lens;
    p.ref.layerCount = layers.length;
  }

  if (opts.contractTier != null ||
      opts.contractBudgetMib != null ||
      opts.contractFuel != null) {
    p.ref.hasContract = 1;
    p.ref.contractTier = opts.contractTier ?? 0;
    p.ref.contractBudgetMib = opts.contractBudgetMib ?? 0;
    p.ref.contractFuel = opts.contractFuel ?? 0;
  }

  if (opts.connectionsBlob != null && opts.connectionsBlob!.isNotEmpty) {
    final b = allocBytes(opts.connectionsBlob!);
    owned.add(b);
    p.ref.connectionsBlob = b;
    p.ref.connectionsLen = opts.connectionsBlob!.length;
  }
  if (opts.connectionPoliciesBlob != null &&
      opts.connectionPoliciesBlob!.isNotEmpty) {
    final b = allocBytes(opts.connectionPoliciesBlob!);
    owned.add(b);
    p.ref.connectionPoliciesBlob = b;
    p.ref.connectionPoliciesLen = opts.connectionPoliciesBlob!.length;
  }

  return _BootOptsNative(p, owned);
}

class _ExecOptsNative {
  _ExecOptsNative(this.ptr, this._owned);

  final Pointer<AosExecOpts> ptr;
  final List<Pointer> _owned;

  void free() {
    for (final p in _owned) {
      freePtr(p);
    }
    freePtr(ptr);
  }
}

_ExecOptsNative? _packExecOpts(AgentOsExecOptions? opts) {
  if (opts == null) return null;
  final owned = <Pointer>[];
  final p = mallocBytes<AosExecOpts>(1, sizeOf<AosExecOpts>());
  p.ref.size = sizeOf<AosExecOpts>();
  p.ref.cwd = nullptr;
  p.ref.envBlob = nullptr;
  p.ref.envBlobLen = 0;
  p.ref.stdinData = nullptr;
  p.ref.stdinLen = 0;
  p.ref.maxTicks = opts.maxTicks;

  if (opts.cwd != null && opts.cwd!.isNotEmpty) {
    final c = allocCString(opts.cwd!);
    owned.add(c);
    p.ref.cwd = c;
  }
  if (opts.envBlob != null && opts.envBlob!.isNotEmpty) {
    final e = allocBytes(opts.envBlob!);
    owned.add(e);
    p.ref.envBlob = e;
    p.ref.envBlobLen = opts.envBlob!.length;
  }
  if (opts.stdinData != null && opts.stdinData!.isNotEmpty) {
    final s = allocBytes(opts.stdinData!);
    owned.add(s);
    p.ref.stdinData = s;
    p.ref.stdinLen = opts.stdinData!.length;
  }
  return _ExecOptsNative(p, owned);
}

class _ArgvNative {
  _ArgvNative(this.ptr, this.argc, this._owned);

  final Pointer<Pointer<Uint8>> ptr;
  final int argc;
  final List<Pointer> _owned;

  void free() {
    for (final p in _owned) {
      freePtr(p);
    }
    freePtr(ptr);
  }
}

_ArgvNative _packArgv(List<String> argv) {
  final owned = <Pointer>[];
  final p = mallocBytes<Pointer<Uint8>>(
    argv.length,
    sizeOf<Pointer<Uint8>>(),
  );
  for (var i = 0; i < argv.length; i++) {
    final s = allocCString(argv[i]);
    owned.add(s);
    p[i] = s;
  }
  return _ArgvNative(p, argv.length, owned);
}

void _check(AgentOsNative native, int rc, String op) {
  if (rc != kAosOk) {
    throw StateError('$op failed: ${native.errorMessage()}');
  }
}

/// Single-owner AgentOS VM over the product C ABI.
class AgentOsVm {
  AgentOsVm._(this._handle, this._libraryPath);

  final int _handle;
  final String? _libraryPath;
  bool _closed = false;

  /// Library API version constant from the shared object.
  static Future<int> apiVersion({String? libraryPath}) {
    final path = libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      return native.apiVersion();
    });
  }

  /// Native package / host version string.
  static Future<String> libraryVersion({String? libraryPath}) {
    final path = libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      return native.versionString();
    });
  }

  /// Boot [kernelBytes] with optional base image tar (e.g. loom.tar).
  /// Uses compat [aos_vm_boot] (deny-default caps).
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

  /// Extended boot with [AgentOsBootOptions] via [aos_vm_boot_ex].
  static Future<AgentOsVm> bootEx(
    Uint8List kernelBytes, {
    AgentOsBootOptions? opts,
    String? libraryPath,
  }) {
    final path = libraryPath;
    final kernel = Uint8List.fromList(kernelBytes);
    final bootOpts = opts;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final kPtr = allocBytes(kernel);
      final out = mallocBytes<Uint64>(1, sizeOf<Uint64>());
      final packed = _packBootOpts(bootOpts);
      try {
        final rc = native.bootEx(
          kPtr,
          kernel.length,
          packed?.ptr ?? nullptr,
          out,
        );
        _check(native, rc, 'aos_vm_boot_ex');
        return out.value;
      } finally {
        if (kPtr != nullptr) freePtr(kPtr);
        freePtr(out);
        packed?.free();
      }
    }).then((handle) => AgentOsVm._(handle, path));
  }

  /// Restore from snapshot blob(s).
  static Future<AgentOsVm> restore(
    Uint8List kernelBytes,
    Uint8List snapshot, {
    Uint8List? baseSnapshot,
    AgentOsBootOptions? opts,
    String? libraryPath,
  }) {
    final path = libraryPath;
    final kernel = Uint8List.fromList(kernelBytes);
    final snap = Uint8List.fromList(snapshot);
    final base = baseSnapshot == null ? null : Uint8List.fromList(baseSnapshot);
    final bootOpts = opts;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final kPtr = allocBytes(kernel);
      final sPtr = allocBytes(snap);
      final bPtr = base == null ? nullptr : allocBytes(base);
      final out = mallocBytes<Uint64>(1, sizeOf<Uint64>());
      final packed = _packBootOpts(bootOpts);
      try {
        final rc = native.restore(
          kPtr,
          kernel.length,
          sPtr,
          snap.length,
          bPtr,
          base?.length ?? 0,
          packed?.ptr ?? nullptr,
          out,
        );
        _check(native, rc, 'aos_vm_restore');
        return out.value;
      } finally {
        if (kPtr != nullptr) freePtr(kPtr);
        if (sPtr != nullptr) freePtr(sPtr);
        if (bPtr != nullptr) freePtr(bPtr);
        freePtr(out);
        packed?.free();
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
        return _tickStateFromInt(out.value);
      } finally {
        freePtr(out);
      }
    });
  }

  /// Run up to [n] ticks; returns the last tick state.
  Future<AgentOsTickState> tickN(int n) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final count = n;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = mallocBytes<Int32>(1, sizeOf<Int32>());
      try {
        final rc = native.tickN(handle, count, out);
        _check(native, rc, 'aos_vm_tick_n');
        return _tickStateFromInt(out.value);
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

  /// Stream-masked take via [aos_vm_take_output_ex].
  /// [streamMask] is a bitset of [kAosStreamStdout] / [kAosStreamStderr] / [kAosStreamLog].
  Future<Uint8List> takeOutputEx({
    int streamMask = kAosStreamStdout | kAosStreamStderr | kAosStreamLog,
    int capacity = 65536,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final mask = streamMask;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = allocAosBuf(cap);
      try {
        final rc = native.takeOutputEx(handle, mask, out);
        _check(native, rc, 'aos_vm_take_output_ex');
        return copyFromAosBuf(out);
      } finally {
        freeAosBuf(out);
      }
    });
  }

  Future<AgentOsVmStatusInfo> status() {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = mallocBytes<AosVmStatus>(1, sizeOf<AosVmStatus>());
      try {
        out.ref.size = sizeOf<AosVmStatus>();
        final rc = native.status(handle, out);
        _check(native, rc, 'aos_vm_status');
        return AgentOsVmStatusInfo(
          bytesWritten: out.ref.bytesWritten,
          exitCode: out.ref.exitCode,
          atPrompt: out.ref.atPrompt != 0,
          workers: out.ref.workers,
          hasWorkerEntry: out.ref.hasWorkerEntry != 0,
          inflightEgress: out.ref.inflightEgress,
          pendingCommits: out.ref.pendingCommits,
        );
      } finally {
        freePtr(out);
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

  /// Compat blocking exec (no cwd/env/stdin opts).
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

  /// Extended blocking shell exec with [AgentOsExecOptions].
  Future<AgentOsExecResult> execEx(
    String cmd, {
    AgentOsExecOptions? opts,
    int stdoutCap = 256 * 1024,
    int stderrCap = 64 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final command = cmd;
    final execOpts = opts;
    final soCap = stdoutCap;
    final seCap = stderrCap;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final cmdPtr = allocCString(command);
      final packed = _packExecOpts(execOpts);
      final stdoutB = allocAosBuf(soCap);
      final stderrB = allocAosBuf(seCap);
      final outExit = mallocBytes<Int32>(1, sizeOf<Int32>());
      try {
        final rc = native.execEx(
          handle,
          cmdPtr,
          packed?.ptr ?? nullptr,
          stdoutB,
          stderrB,
          outExit,
        );
        _check(native, rc, 'aos_vm_exec_ex');
        return AgentOsExecResult(
          exitCode: outExit.value,
          stdout: copyFromAosBuf(stdoutB),
          stderr: copyFromAosBuf(stderrB),
        );
      } finally {
        freePtr(cmdPtr);
        packed?.free();
        freeAosBuf(stdoutB);
        freeAosBuf(stderrB);
        freePtr(outExit);
      }
    });
  }

  /// Blocking argv-style run.
  Future<AgentOsExecResult> run(
    String program,
    List<String> argv, {
    AgentOsExecOptions? opts,
    int stdoutCap = 256 * 1024,
    int stderrCap = 64 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final prog = program;
    final args = List<String>.from(argv);
    final execOpts = opts;
    final soCap = stdoutCap;
    final seCap = stderrCap;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final progPtr = allocCString(prog);
      final packedArgv = _packArgv(args);
      final packed = _packExecOpts(execOpts);
      final stdoutB = allocAosBuf(soCap);
      final stderrB = allocAosBuf(seCap);
      final outExit = mallocBytes<Int32>(1, sizeOf<Int32>());
      try {
        final rc = native.run(
          handle,
          progPtr,
          packedArgv.ptr,
          packedArgv.argc,
          packed?.ptr ?? nullptr,
          stdoutB,
          stderrB,
          outExit,
        );
        _check(native, rc, 'aos_vm_run');
        return AgentOsExecResult(
          exitCode: outExit.value,
          stdout: copyFromAosBuf(stdoutB),
          stderr: copyFromAosBuf(stderrB),
        );
      } finally {
        freePtr(progPtr);
        packedArgv.free();
        packed?.free();
        freeAosBuf(stdoutB);
        freeAosBuf(stderrB);
        freePtr(outExit);
      }
    });
  }

  /// Start async shell job; returns job id.
  Future<int> execStart(String cmd, {AgentOsExecOptions? opts}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final command = cmd;
    final execOpts = opts;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final cmdPtr = allocCString(command);
      final packed = _packExecOpts(execOpts);
      final outJob = mallocBytes<Int64>(1, sizeOf<Int64>());
      try {
        final rc = native.execStart(
          handle,
          cmdPtr,
          packed?.ptr ?? nullptr,
          outJob,
        );
        _check(native, rc, 'aos_vm_exec_start');
        return outJob.value;
      } finally {
        freePtr(cmdPtr);
        packed?.free();
        freePtr(outJob);
      }
    });
  }

  /// Start async argv job; returns job id.
  Future<int> runStart(
    String program,
    List<String> argv, {
    AgentOsExecOptions? opts,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final prog = program;
    final args = List<String>.from(argv);
    final execOpts = opts;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final progPtr = allocCString(prog);
      final packedArgv = _packArgv(args);
      final packed = _packExecOpts(execOpts);
      final outJob = mallocBytes<Int64>(1, sizeOf<Int64>());
      try {
        final rc = native.runStart(
          handle,
          progPtr,
          packedArgv.ptr,
          packedArgv.argc,
          packed?.ptr ?? nullptr,
          outJob,
        );
        _check(native, rc, 'aos_vm_run_start');
        return outJob.value;
      } finally {
        freePtr(progPtr);
        packedArgv.free();
        packed?.free();
        freePtr(outJob);
      }
    });
  }

  Future<AgentOsExecPollResult> execPoll(
    int job, {
    int stdoutCap = 256 * 1024,
    int stderrCap = 64 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final jobId = job;
    final soCap = stdoutCap;
    final seCap = stderrCap;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final outDone = mallocBytes<Int32>(1, sizeOf<Int32>());
      final outExit = mallocBytes<Int32>(1, sizeOf<Int32>());
      final stdoutB = allocAosBuf(soCap);
      final stderrB = allocAosBuf(seCap);
      try {
        final rc = native.execPoll(
          handle,
          jobId,
          outDone,
          outExit,
          stdoutB,
          stderrB,
        );
        _check(native, rc, 'aos_vm_exec_poll');
        final done = outDone.value != 0;
        if (!done) {
          return const AgentOsExecPollResult(done: false);
        }
        return AgentOsExecPollResult(
          done: true,
          exitCode: outExit.value,
          stdout: copyFromAosBuf(stdoutB),
          stderr: copyFromAosBuf(stderrB),
        );
      } finally {
        freePtr(outDone);
        freePtr(outExit);
        freeAosBuf(stdoutB);
        freeAosBuf(stderrB);
      }
    });
  }

  Future<Uint8List> execStdoutPeek(int job, {int capacity = 65536}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final jobId = job;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = allocAosBuf(cap);
      try {
        final rc = native.execStdoutPeek(handle, jobId, out);
        _check(native, rc, 'aos_vm_exec_stdout_peek');
        return copyFromAosBuf(out);
      } finally {
        freeAosBuf(out);
      }
    });
  }

  Future<void> execCancel(int job) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final jobId = job;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.execCancel(handle, jobId);
      _check(native, rc, 'aos_vm_exec_cancel');
    });
  }

  /// Encoded autocomplete candidates (implementation-defined).
  Future<Uint8List> autocomplete(
    String source,
    int cursorByte, {
    AgentOsExecOptions? opts,
    int capacity = 64 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final src = source;
    final cursor = cursorByte;
    final execOpts = opts;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final srcPtr = allocCString(src);
      final packed = _packExecOpts(execOpts);
      final out = allocAosBuf(cap);
      try {
        final rc = native.autocomplete(
          handle,
          srcPtr,
          cursor,
          packed?.ptr ?? nullptr,
          out,
        );
        _check(native, rc, 'aos_vm_autocomplete');
        return copyFromAosBuf(out);
      } finally {
        freePtr(srcPtr);
        packed?.free();
        freeAosBuf(out);
      }
    });
  }

  Future<AgentOsSvcResult> svcCall(
    String service,
    Uint8List request, {
    int bodyCap = 256 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final svc = service;
    final req = Uint8List.fromList(request);
    final cap = bodyCap;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final svcPtr = allocCString(svc);
      final reqPtr = allocBytes(req);
      final outStatus = mallocBytes<Int32>(1, sizeOf<Int32>());
      final outBody = allocAosBuf(cap);
      try {
        final rc = native.svcCall(
          handle,
          svcPtr,
          reqPtr,
          req.length,
          outStatus,
          outBody,
        );
        _check(native, rc, 'aos_vm_svc_call');
        return AgentOsSvcResult(
          status: outStatus.value,
          body: copyFromAosBuf(outBody),
        );
      } finally {
        freePtr(svcPtr);
        if (reqPtr != nullptr) freePtr(reqPtr);
        freePtr(outStatus);
        freeAosBuf(outBody);
      }
    });
  }

  Future<Uint8List> readFile(String path, {int capacity = 256 * 1024}) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      final out = allocAosBuf(cap);
      try {
        final rc = native.readFile(handle, pathPtr, out);
        _check(native, rc, 'aos_vm_read_file');
        return copyFromAosBuf(out);
      } finally {
        freePtr(pathPtr);
        freeAosBuf(out);
      }
    });
  }

  Future<void> writeFile(String path, Uint8List data) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    final bytes = Uint8List.fromList(data);
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      final dataPtr = allocBytes(bytes);
      try {
        final rc = native.writeFile(handle, pathPtr, dataPtr, bytes.length);
        _check(native, rc, 'aos_vm_write_file');
      } finally {
        freePtr(pathPtr);
        if (dataPtr != nullptr) freePtr(dataPtr);
      }
    });
  }

  /// Encoded directory listing (implementation-defined).
  Future<Uint8List> readdir(String path, {int capacity = 256 * 1024}) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      final out = allocAosBuf(cap);
      try {
        final rc = native.readdir(handle, pathPtr, out);
        _check(native, rc, 'aos_vm_readdir');
        return copyFromAosBuf(out);
      } finally {
        freePtr(pathPtr);
        freeAosBuf(out);
      }
    });
  }

  Future<AgentOsFileStat> stat(String path) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      final out = mallocBytes<AosStat>(1, sizeOf<AosStat>());
      try {
        final rc = native.stat(handle, pathPtr, out);
        _check(native, rc, 'aos_vm_stat');
        return AgentOsFileStat(
          size: out.ref.size,
          isDir: out.ref.isDir != 0,
          isSymlink: out.ref.isSymlink != 0,
          nlink: out.ref.nlink,
          mode: out.ref.mode,
        );
      } finally {
        freePtr(pathPtr);
        freePtr(out);
      }
    });
  }

  Future<Uint8List> readlink(String path, {int capacity = 4096}) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      final out = allocAosBuf(cap);
      try {
        final rc = native.readlink(handle, pathPtr, out);
        _check(native, rc, 'aos_vm_readlink');
        return copyFromAosBuf(out);
      } finally {
        freePtr(pathPtr);
        freeAosBuf(out);
      }
    });
  }

  Future<void> mkdir(String path) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      try {
        final rc = native.mkdir(handle, pathPtr);
        _check(native, rc, 'aos_vm_mkdir');
      } finally {
        freePtr(pathPtr);
      }
    });
  }

  Future<void> unlink(String path) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      try {
        final rc = native.unlink(handle, pathPtr);
        _check(native, rc, 'aos_vm_unlink');
      } finally {
        freePtr(pathPtr);
      }
    });
  }

  Future<void> chmod(String path, int mode) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    final modeVal = mode;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      try {
        final rc = native.chmod(handle, pathPtr, modeVal);
        _check(native, rc, 'aos_vm_chmod');
      } finally {
        freePtr(pathPtr);
      }
    });
  }

  Future<void> symlink(String target, String linkPath) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final tgt = target;
    final link = linkPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final tPtr = allocCString(tgt);
      final lPtr = allocCString(link);
      try {
        final rc = native.symlink(handle, tPtr, lPtr);
        _check(native, rc, 'aos_vm_symlink');
      } finally {
        freePtr(tPtr);
        freePtr(lPtr);
      }
    });
  }

  Future<void> mount(String path, {bool readOnly = true}) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    final ro = readOnly;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      try {
        final rc = native.mount(handle, pathPtr, ro ? 1 : 0);
        _check(native, rc, 'aos_vm_mount');
      } finally {
        freePtr(pathPtr);
      }
    });
  }

  Future<void> unmount(String path) {
    _ensureOpen();
    final handle = _handle;
    final libPath = _libraryPath;
    final filePath = path;
    return Isolate.run(() {
      final native = AgentOsNative.open(libPath);
      final pathPtr = allocCString(filePath);
      try {
        final rc = native.unmount(handle, pathPtr);
        _check(native, rc, 'aos_vm_unmount');
      } finally {
        freePtr(pathPtr);
      }
    });
  }

  /// Full snapshot as library-owned bytes (copied then freed).
  Future<Uint8List> snapshot() {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = mallocBytes<AosBytes>(1, sizeOf<AosBytes>());
      out.ref.ptr = nullptr;
      out.ref.len = 0;
      try {
        final rc = native.snapshot(handle, out);
        _check(native, rc, 'aos_vm_snapshot');
        return takeAosBytes(native, out);
      } catch (e) {
        // If snapshot failed after partial fill, still free.
        if (out.ref.ptr != nullptr) native.bytesFree(out);
        rethrow;
      } finally {
        freePtr(out);
      }
    });
  }

  /// Snapshot into a caller buffer (may truncate if capacity too small).
  Future<Uint8List> snapshotInto({int capacity = 16 * 1024 * 1024}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = allocAosBuf(cap);
      try {
        final rc = native.snapshotInto(handle, out);
        _check(native, rc, 'aos_vm_snapshot_into');
        return copyFromAosBuf(out);
      } finally {
        freeAosBuf(out);
      }
    });
  }

  Future<Uint8List> snapshotIncremental(Uint8List base) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final baseCopy = Uint8List.fromList(base);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final basePtr = allocBytes(baseCopy);
      final out = mallocBytes<AosBytes>(1, sizeOf<AosBytes>());
      out.ref.ptr = nullptr;
      out.ref.len = 0;
      try {
        final rc = native.snapshotIncremental(
          handle,
          basePtr,
          baseCopy.length,
          out,
        );
        _check(native, rc, 'aos_vm_snapshot_incremental');
        return takeAosBytes(native, out);
      } catch (e) {
        if (out.ref.ptr != nullptr) native.bytesFree(out);
        rethrow;
      } finally {
        if (basePtr != nullptr) freePtr(basePtr);
        freePtr(out);
      }
    });
  }

  Future<AgentOsCommitLayerResult> commitLayer({int digestCap = 128}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final digCap = digestCap;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final outTar = mallocBytes<AosBytes>(1, sizeOf<AosBytes>());
      outTar.ref.ptr = nullptr;
      outTar.ref.len = 0;
      final outDigest = allocAosBuf(digCap);
      try {
        final rc = native.commitLayer(handle, outTar, outDigest);
        _check(native, rc, 'aos_vm_commit_layer');
        final tar = takeAosBytes(native, outTar);
        return AgentOsCommitLayerResult(
          tar: tar,
          digestHex: copyFromAosBuf(outDigest),
        );
      } catch (e) {
        if (outTar.ref.ptr != nullptr) native.bytesFree(outTar);
        rethrow;
      } finally {
        freePtr(outTar);
        freeAosBuf(outDigest);
      }
    });
  }

  /// Pull next relay frame (empty if none).
  Future<Uint8List> relayNext({int capacity = 256 * 1024}) {
    return _relayPull(sidecar: false, capacity: capacity);
  }

  Future<Uint8List> relayNextSidecar({int capacity = 256 * 1024}) {
    return _relayPull(sidecar: true, capacity: capacity);
  }

  Future<Uint8List> _relayPull({required bool sidecar, required int capacity}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final cap = capacity;
    final isSidecar = sidecar;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = allocAosBuf(cap);
      try {
        final rc = isSidecar
            ? native.relayNextSidecar(handle, out)
            : native.relayNext(handle, out);
        _check(native, rc, isSidecar ? 'aos_vm_relay_next_sidecar' : 'aos_vm_relay_next');
        return copyFromAosBuf(out);
      } finally {
        freeAosBuf(out);
      }
    });
  }

  Future<void> relayHttpRespond(
    int relayHandle, {
    required bool ok,
    Uint8List? head,
    Uint8List? body,
  }) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    final okFlag = ok ? 1 : 0;
    final headCopy = head == null ? null : Uint8List.fromList(head);
    final bodyCopy = body == null ? null : Uint8List.fromList(body);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final headPtr = headCopy == null ? nullptr : allocBytes(headCopy);
      final bodyPtr = bodyCopy == null ? nullptr : allocBytes(bodyCopy);
      try {
        final rc = native.relayHttpRespond(
          vm,
          h,
          okFlag,
          headPtr,
          headCopy?.length ?? 0,
          bodyPtr,
          bodyCopy?.length ?? 0,
        );
        _check(native, rc, 'aos_vm_relay_http_respond');
      } finally {
        if (headPtr != nullptr) freePtr(headPtr);
        if (bodyPtr != nullptr) freePtr(bodyPtr);
      }
    });
  }

  Future<void> relayHostCallRespond(
    int relayHandle, {
    required bool ok,
    Uint8List? result,
  }) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    final okFlag = ok ? 1 : 0;
    final res = result == null ? null : Uint8List.fromList(result);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final resPtr = res == null ? nullptr : allocBytes(res);
      try {
        final rc = native.relayHostCallRespond(
          vm,
          h,
          okFlag,
          resPtr,
          res?.length ?? 0,
        );
        _check(native, rc, 'aos_vm_relay_host_call_respond');
      } finally {
        if (resPtr != nullptr) freePtr(resPtr);
      }
    });
  }

  Future<void> relayPersistRespond(
    int relayHandle, {
    required bool ok,
    Uint8List? body,
  }) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    final okFlag = ok ? 1 : 0;
    final bodyCopy = body == null ? null : Uint8List.fromList(body);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final bodyPtr = bodyCopy == null ? nullptr : allocBytes(bodyCopy);
      try {
        final rc = native.relayPersistRespond(
          vm,
          h,
          okFlag,
          bodyPtr,
          bodyCopy?.length ?? 0,
        );
        _check(native, rc, 'aos_vm_relay_persist_respond');
      } finally {
        if (bodyPtr != nullptr) freePtr(bodyPtr);
      }
    });
  }

  Future<void> relayToolApprovalRespond(
    int relayHandle, {
    required bool allow,
    bool rememberSession = false,
  }) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    final allowFlag = allow ? 1 : 0;
    final remember = rememberSession ? 1 : 0;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.relayToolApprovalRespond(vm, h, allowFlag, remember);
      _check(native, rc, 'aos_vm_relay_tool_approval_respond');
    });
  }

  Future<void> relayWsOpen(int relayHandle, {required bool ok}) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    final okFlag = ok ? 1 : 0;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.relayWsOpen(vm, h, okFlag);
      _check(native, rc, 'aos_vm_relay_ws_open');
    });
  }

  Future<void> relayWsPush(int relayHandle, Uint8List data) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    final copy = Uint8List.fromList(data);
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final dataPtr = allocBytes(copy);
      try {
        final rc = native.relayWsPush(vm, h, dataPtr, copy.length);
        _check(native, rc, 'aos_vm_relay_ws_push');
      } finally {
        if (dataPtr != nullptr) freePtr(dataPtr);
      }
    });
  }

  Future<void> relayWsClose(int relayHandle) {
    _ensureOpen();
    final vm = _handle;
    final path = _libraryPath;
    final h = relayHandle;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.relayWsClose(vm, h);
      _check(native, rc, 'aos_vm_relay_ws_close');
    });
  }

  Future<Uint8List> injectCatalog({
    required Uint8List compilerWasm,
    required Uint8List catalogBlob,
    int generation = 0,
    int statusCap = 64 * 1024,
  }) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final compiler = Uint8List.fromList(compilerWasm);
    final catalog = Uint8List.fromList(catalogBlob);
    final gen = generation;
    final cap = statusCap;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final cPtr = allocBytes(compiler);
      final catPtr = allocBytes(catalog);
      final out = allocAosBuf(cap);
      try {
        final rc = native.injectCatalog(
          handle,
          cPtr,
          compiler.length,
          gen,
          catPtr,
          catalog.length,
          out,
        );
        _check(native, rc, 'aos_vm_inject_catalog');
        return copyFromAosBuf(out);
      } finally {
        if (cPtr != nullptr) freePtr(cPtr);
        if (catPtr != nullptr) freePtr(catPtr);
        freeAosBuf(out);
      }
    });
  }

  Future<void> setPerfEnabled(bool on) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final flag = on ? 1 : 0;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.setPerfEnabled(handle, flag);
      _check(native, rc, 'aos_vm_set_perf_enabled');
    });
  }

  Future<void> scrubPerf() {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final rc = native.scrubPerf(handle);
      _check(native, rc, 'aos_vm_scrub_perf');
    });
  }

  Future<Uint8List> takeCommandPerf({int capacity = 256 * 1024}) {
    _ensureOpen();
    final handle = _handle;
    final path = _libraryPath;
    final cap = capacity;
    return Isolate.run(() {
      final native = AgentOsNative.open(path);
      final out = allocAosBuf(cap);
      try {
        final rc = native.takeCommandPerf(handle, out);
        _check(native, rc, 'aos_vm_take_command_perf');
        return copyFromAosBuf(out);
      } finally {
        freeAosBuf(out);
      }
    });
  }

  void _ensureOpen() {
    if (_closed) throw StateError('AgentOsVm is closed');
  }
}

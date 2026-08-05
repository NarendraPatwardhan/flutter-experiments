// Idle scrollback compression scheduler (G4).

import 'dart:async';
import 'dart:ffi';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';

/// Caller-driven scrollback compression after compression-relevant activity
/// goes idle (matches `example/c-vt-compression`).
class VtCompressScheduler {
  VtCompressScheduler({
    this.idleDelay = const Duration(milliseconds: 300),
  });

  final Duration idleDelay;

  int lastActivity = 0;
  Timer? _idle;
  bool _closed = false;

  /// Call after each [vt_write] batch (or any mutation). Restarts the idle
  /// timer when [ghostty_terminal_compression_activity] changes.
  void onWrite(GhosttyVtNative n, Pointer term) {
    if (_closed) return;
    final out = mallocBytes<Uint64>(1, sizeOf<Uint64>());
    try {
      final rc = n.terminalCompressionActivity(term.cast(), out);
      if (rc != kGhosttySuccess) return;
      final activity = out.value;
      if (activity != lastActivity) {
        lastActivity = activity;
        _restartIdle(n, term);
      }
    } finally {
      freePtr(out);
    }
  }

  void _restartIdle(GhosttyVtNative n, Pointer term) {
    _idle?.cancel();
    _idle = Timer(idleDelay, () => _runIdleSteps(n, term));
  }

  void _runIdleSteps(GhosttyVtNative n, Pointer term) {
    if (_closed) return;
    final resultPtr = mallocBytes<Int32>(1, sizeOf<Int32>());
    try {
      // Drain pending incremental work while idle.
      while (!_closed) {
        resultPtr.value = kCompressResultComplete;
        final rc = n.terminalCompress(
          term.cast(),
          kCompressModeIncremental,
          resultPtr,
        );
        if (rc != kGhosttySuccess) break;
        final r = resultPtr.value;
        if (r == kCompressResultPending) {
          // Yield to the event loop between steps.
          _idle = Timer(Duration.zero, () => _runIdleSteps(n, term));
          return;
        }
        // COMPLETE or UNSUPPORTED — stop until activity changes again.
        break;
      }
    } finally {
      freePtr(resultPtr);
    }
  }

  /// Cancel pending idle work. Safe to call multiple times; [onWrite] works again
  /// after [reset].
  void dispose() {
    _closed = true;
    _idle?.cancel();
    _idle = null;
  }

  /// Re-arm after [dispose] so a new session can reuse this scheduler.
  void reset() {
    _idle?.cancel();
    _idle = null;
    lastActivity = 0;
    _closed = false;
  }
}

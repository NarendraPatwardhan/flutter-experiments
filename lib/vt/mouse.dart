// G3 — mouse encoder helpers over libghostty-vt.
//
// Thin wrapper around ghostty_mouse_encoder_* + ghostty_mouse_event_*.
// Modes/format are synced from the terminal via setopt_from_terminal.

import 'dart:ffi';
import 'dart:typed_data';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';

/// Owns a `GhosttyMouseEncoder` (+ optional reusable event).
///
/// Not thread-safe — call from the isolate that owns the terminal.
class VtMouseEncoder {
  VtMouseEncoder._({
    required GhosttyVtNative native,
    required Pointer<Void> encoder,
    required Pointer<Void> event,
  })  : _n = native,
        _encoder = encoder,
        _event = event;

  final GhosttyVtNative _n;
  Pointer<Void> _encoder;
  Pointer<Void> _event;
  bool _closed = false;

  /// Create encoder + a reusable mouse event.
  factory VtMouseEncoder.open(GhosttyVtNative n) {
    final encOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final evOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    try {
      var rc = n.mouseEncoderNew(nullptr, encOut);
      if (rc != kGhosttySuccess) {
        throw StateError('ghostty_mouse_encoder_new failed: $rc');
      }
      rc = n.mouseEventNew(nullptr, evOut);
      if (rc != kGhosttySuccess) {
        n.mouseEncoderFree(encOut.value);
        throw StateError('ghostty_mouse_event_new failed: $rc');
      }
      return VtMouseEncoder._(
        native: n,
        encoder: encOut.value,
        event: evOut.value,
      );
    } finally {
      freePtr(encOut);
      freePtr(evOut);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _n.mouseEventFree(_event);
    _n.mouseEncoderFree(_encoder);
    _event = nullptr;
    _encoder = nullptr;
  }

  /// Sync tracking mode + output format from [term] live state.
  void setoptFromTerminal(Pointer term) {
    _ensureOpen();
    _n.mouseEncoderSetoptFromTerminal(_encoder, term.cast());
  }

  /// Encode a mouse event into terminal escape bytes.
  ///
  /// [action] is [kMouseActionPress] / [kMouseActionRelease] / [kMouseActionMotion].
  /// [button] is [kMouseButtonLeft] etc.; pass null for motion with no button.
  /// [x]/[y] are surface-space pixels (see GhosttyMousePosition).
  ///
  /// Returns encoded bytes (may be empty when the encoder emits nothing for
  /// this event under the current mode), or null on error.
  Uint8List? encode({
    required int action,
    int? button,
    required double x,
    required double y,
    int mods = 0,
    int bufCap = 128,
  }) {
    _ensureOpen();

    _n.mouseEventSetAction(_event, action);
    if (button != null) {
      _n.mouseEventSetButton(_event, button);
    } else {
      _n.mouseEventClearButton(_event);
    }
    _n.mouseEventSetMods(_event, mods);

    // set_position takes GhosttyMousePosition by value (2× float).
    final pos = mallocBytes<GhosttyMousePositionNative>(
      1,
      sizeOf<GhosttyMousePositionNative>(),
    );
    final outLen = mallocBytes<Size>(1, sizeOf<Size>());
    final buf = mallocBytes<Uint8>(bufCap, 1);
    try {
      pos.ref
        ..x = x
        ..y = y;
      _n.mouseEventSetPosition(_event, pos.ref);

      var rc = _n.mouseEncoderEncode(
        _encoder,
        _event,
        buf,
        bufCap,
        outLen,
      );
      if (rc == kGhosttyOutOfSpace) {
        final need = outLen.value;
        if (need <= 0) return null;
        final big = mallocBytes<Uint8>(need, 1);
        try {
          rc = _n.mouseEncoderEncode(
            _encoder,
            _event,
            big,
            need,
            outLen,
          );
          if (rc != kGhosttySuccess) return null;
          final n = outLen.value;
          if (n <= 0) return Uint8List(0);
          return Uint8List.fromList(big.asTypedList(n));
        } finally {
          freePtr(big);
        }
      }
      if (rc != kGhosttySuccess) return null;
      final n = outLen.value;
      if (n <= 0) return Uint8List(0);
      return Uint8List.fromList(buf.asTypedList(n));
    } finally {
      freePtr(pos);
      freePtr(outLen);
      freePtr(buf);
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('VtMouseEncoder is closed');
  }
}

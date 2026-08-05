// Terminal snapshot encode (G4 debug / export).

import 'dart:ffi';
import 'dart:typed_data';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';

/// Encode a complete terminal snapshot via [ghostty_snapshot_encode_buf]
/// with grow-on-demand buffer.
///
/// Requires continuation tracking when the VT parser is unfinished; at
/// ground state encoding works without it.
Uint8List snapshotEncode(GhosttyVtNative native, Pointer term) {
  final outLen = mallocBytes<Size>(1, sizeOf<Size>());
  try {
    // Size query
    outLen.value = 0;
    var rc = native.snapshotEncodeBuf(term.cast(), nullptr, 0, outLen);
    var need = outLen.value;
    if (rc == kGhosttySuccess && need == 0) {
      return Uint8List(0);
    }
    if (rc != kGhosttyOutOfSpace && rc != kGhosttySuccess) {
      throw StateError('ghostty_snapshot_encode_buf size query failed: $rc');
    }
    if (need <= 0) need = 4096;

    // Grow loop
    for (var attempt = 0; attempt < 8; attempt++) {
      final buf = mallocBytes<Uint8>(need, sizeOf<Uint8>());
      try {
        outLen.value = 0;
        rc = native.snapshotEncodeBuf(term.cast(), buf, need, outLen);
        if (rc == kGhosttySuccess) {
          final n = outLen.value;
          if (n <= 0) return Uint8List(0);
          return Uint8List.fromList(buf.asTypedList(n));
        }
        if (rc == kGhosttyOutOfSpace) {
          need = outLen.value > need ? outLen.value : need * 2;
          continue;
        }
        throw StateError('ghostty_snapshot_encode_buf failed: $rc');
      } finally {
        freePtr(buf);
      }
    }
    throw StateError('ghostty_snapshot_encode_buf: buffer growth exhausted');
  } finally {
    freePtr(outLen);
  }
}

// G3 — scrollback viewport helpers over libghostty-vt.

import 'dart:ffi';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'frame.dart' show VtScrollbar;

/// Scroll the terminal viewport.
///
/// [tag] is one of [kScrollViewportTop], [kScrollViewportBottom],
/// [kScrollViewportDelta], [kScrollViewportRow].
///
/// For [kScrollViewportDelta], pass [delta] (negative = up, positive = down).
/// For [kScrollViewportRow], pass [row] (absolute offset in scrollbar row space).
void scrollViewport(
  GhosttyVtNative n,
  Pointer term, {
  required int tag,
  int delta = 0,
  int row = 0,
}) {
  final beh = mallocBytes<GhosttyScrollViewportNative>(
    1,
    sizeOf<GhosttyScrollViewportNative>(),
  );
  try {
    beh.ref
      ..tag = tag
      ..pad = 0
      ..value0 = 0
      ..value1 = 0;
    if (tag == kScrollViewportDelta) {
      beh.ref.value0 = delta;
    } else if (tag == kScrollViewportRow) {
      beh.ref.value0 = row;
    }
    n.terminalScrollViewport(term.cast(), beh.ref);
  } finally {
    freePtr(beh);
  }
}

/// Read scrollbar metrics via `GHOSTTY_TERMINAL_DATA_SCROLLBAR` (= 9).
///
/// Returns null when the terminal reports no value or on error.
VtScrollbar? readScrollbar(GhosttyVtNative n, Pointer term) {
  final out = mallocBytes<GhosttyTerminalScrollbarNative>(
    1,
    sizeOf<GhosttyTerminalScrollbarNative>(),
  );
  try {
    final rc = n.terminalGet(
      term.cast(),
      kTerminalDataScrollbar,
      out.cast(),
    );
    if (rc != kGhosttySuccess) return null;
    return VtScrollbar(
      total: out.ref.total,
      offset: out.ref.offset,
      len: out.ref.len,
    );
  } finally {
    freePtr(out);
  }
}

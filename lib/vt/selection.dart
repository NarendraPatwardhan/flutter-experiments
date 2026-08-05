// G3 — selection gesture + copy helpers over libghostty-vt.
//
// Mirrors example/c-vt-selection-gesture: press/drag/release events with
// grid refs, apply resulting GhosttySelection via OPT_SELECTION, copy via
// selection_format_buf (plain text).

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';

/// Wraps a `GhosttySelectionGesture` and reusable typed events.
///
/// Not thread-safe — serialize with other terminal mutations on one isolate.
class VtSelectionController {
  VtSelectionController._({
    required GhosttyVtNative native,
    required Pointer<Void> gesture,
    required Pointer<Void> pressEvent,
    required Pointer<Void> dragEvent,
    required Pointer<Void> releaseEvent,
  })  : _n = native,
        _gesture = gesture,
        _press = pressEvent,
        _drag = dragEvent,
        _release = releaseEvent;

  final GhosttyVtNative _n;
  Pointer<Void> _gesture;
  Pointer<Void> _press;
  Pointer<Void> _drag;
  Pointer<Void> _release;
  bool _closed = false;

  /// Create gesture state + reusable press/drag/release events.
  factory VtSelectionController.open(GhosttyVtNative n) {
    final gOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final pOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final dOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final rOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    try {
      var rc = n.selectionGestureNew(nullptr, gOut);
      if (rc != kGhosttySuccess) {
        throw StateError('ghostty_selection_gesture_new failed: $rc');
      }
      final gesture = gOut.value;

      rc = n.selectionGestureEventNew(nullptr, pOut, kSelectionGesturePress);
      if (rc != kGhosttySuccess) {
        n.selectionGestureFree(gesture, nullptr);
        throw StateError('selection_gesture_event_new(press) failed: $rc');
      }
      rc = n.selectionGestureEventNew(nullptr, dOut, kSelectionGestureDrag);
      if (rc != kGhosttySuccess) {
        n.selectionGestureEventFree(pOut.value);
        n.selectionGestureFree(gesture, nullptr);
        throw StateError('selection_gesture_event_new(drag) failed: $rc');
      }
      rc = n.selectionGestureEventNew(nullptr, rOut, kSelectionGestureRelease);
      if (rc != kGhosttySuccess) {
        n.selectionGestureEventFree(dOut.value);
        n.selectionGestureEventFree(pOut.value);
        n.selectionGestureFree(gesture, nullptr);
        throw StateError('selection_gesture_event_new(release) failed: $rc');
      }

      return VtSelectionController._(
        native: n,
        gesture: gesture,
        pressEvent: pOut.value,
        dragEvent: dOut.value,
        releaseEvent: rOut.value,
      );
    } finally {
      freePtr(gOut);
      freePtr(pOut);
      freePtr(dOut);
      freePtr(rOut);
    }
  }

  /// Release gesture + events. Pass [term] when the terminal is still alive
  /// so tracked refs can be released.
  void close([Pointer? term]) {
    if (_closed) return;
    _closed = true;
    _n.selectionGestureFree(_gesture, term?.cast() ?? nullptr);
    _n.selectionGestureEventFree(_press);
    _n.selectionGestureEventFree(_drag);
    _n.selectionGestureEventFree(_release);
    _gesture = nullptr;
    _press = nullptr;
    _drag = nullptr;
    _release = nullptr;
  }

  /// Reset active click sequence without freeing the controller.
  void reset(Pointer term) {
    _ensureOpen();
    _n.selectionGestureReset(_gesture, term.cast());
  }

  /// Feed a pointer event at cell ([cellX], [cellY]).
  ///
  /// [kind] is [kSelectionGesturePress], [kSelectionGestureDrag], or
  /// [kSelectionGestureRelease].
  ///
  /// For drag, [columns], [cellWidth], and [screenHeight] should describe the
  /// rendered surface (see GhosttySelectionGestureGeometry). Defaults are
  /// usable placeholders when the embedder has not measured yet.
  ///
  /// When the gesture produces a selection snapshot and [applyToTerminal] is
  /// true, it is installed via [kTerminalOptSelection].
  ///
  /// Returns true when a selection was produced (SUCCESS), false for
  /// NO_VALUE (e.g. press/release), throws on hard errors.
  bool onPointer(
    Pointer term, {
    required int kind,
    required int cellX,
    required int cellY,
    int pointTag = kPointTagViewport,
    double surfaceX = 0,
    double surfaceY = 0,
    int columns = 80,
    int cellWidth = 10,
    int paddingLeft = 0,
    int screenHeight = 480,
    bool applyToTerminal = true,
  }) {
    _ensureOpen();

    final event = switch (kind) {
      kSelectionGesturePress => _press,
      kSelectionGestureDrag => _drag,
      kSelectionGestureRelease => _release,
      _ => throw ArgumentError.value(kind, 'kind', 'unsupported gesture kind'),
    };

    final ref = mallocBytes<GhosttyGridRefNative>(
      1,
      sizeOf<GhosttyGridRefNative>(),
    );
    final point = mallocBytes<GhosttyPointNative>(
      1,
      sizeOf<GhosttyPointNative>(),
    );
    final sel = mallocBytes<GhosttySelectionNative>(
      1,
      sizeOf<GhosttySelectionNative>(),
    );
    Pointer<GhosttySurfacePositionNative>? pos;
    Pointer<GhosttySelectionGestureGeometryNative>? geom;

    try {
      // Resolve cell → untracked grid ref.
      point.ref
        ..tag = pointTag
        ..pad = 0
        ..x = cellX & 0xffff
        ..padXy = 0
        ..y = cellY
        ..valuePad = 0;
      ref.ref
        ..size = sizeOf<GhosttyGridRefNative>()
        ..node = nullptr
        ..x = 0
        ..y = 0;

      final grc = _n.terminalGridRef(term.cast(), point, ref);
      if (grc != kGhosttySuccess) {
        throw StateError('ghostty_terminal_grid_ref failed: $grc');
      }

      var rc = _n.selectionGestureEventSet(
        event,
        kSelectionGestureEventOptRef,
        ref.cast(),
      );
      if (rc != kGhosttySuccess) {
        throw StateError('gesture_event_set(REF) failed: $rc');
      }

      if (kind == kSelectionGesturePress || kind == kSelectionGestureDrag) {
        pos = mallocBytes<GhosttySurfacePositionNative>(
          1,
          sizeOf<GhosttySurfacePositionNative>(),
        );
        pos.ref
          ..x = surfaceX
          ..y = surfaceY;
        rc = _n.selectionGestureEventSet(
          event,
          kSelectionGestureEventOptPosition,
          pos.cast(),
        );
        if (rc != kGhosttySuccess) {
          throw StateError('gesture_event_set(POSITION) failed: $rc');
        }
      }

      if (kind == kSelectionGestureDrag) {
        geom = mallocBytes<GhosttySelectionGestureGeometryNative>(
          1,
          sizeOf<GhosttySelectionGestureGeometryNative>(),
        );
        geom.ref
          ..columns = columns
          ..cellWidth = cellWidth
          ..paddingLeft = paddingLeft
          ..screenHeight = screenHeight;
        rc = _n.selectionGestureEventSet(
          event,
          kSelectionGestureEventOptGeometry,
          geom.cast(),
        );
        if (rc != kGhosttySuccess) {
          throw StateError('gesture_event_set(GEOMETRY) failed: $rc');
        }
      }

      // Zero selection out; size set so C ABI can validate sized struct.
      sel.ref
        ..size = sizeOf<GhosttySelectionNative>()
        ..rectangle = false;
      sel.ref.start
        ..size = sizeOf<GhosttyGridRefNative>()
        ..node = nullptr
        ..x = 0
        ..y = 0;
      sel.ref.end
        ..size = sizeOf<GhosttyGridRefNative>()
        ..node = nullptr
        ..x = 0
        ..y = 0;

      rc = _n.selectionGestureEvent(
        _gesture,
        term.cast(),
        event,
        kind == kSelectionGestureRelease ? nullptr : sel,
      );

      if (rc == kGhosttyNoValue) return false;
      if (rc != kGhosttySuccess) {
        throw StateError('ghostty_selection_gesture_event failed: $rc');
      }

      // Install snapshot as terminal-owned selection when requested.
      if (applyToTerminal && kind != kSelectionGestureRelease) {
        final setRc = _n.terminalSet(
          term.cast(),
          kTerminalOptSelection,
          sel.cast(),
        );
        if (setRc != kGhosttySuccess) {
          throw StateError('terminal_set(OPT_SELECTION) failed: $setRc');
        }
      }
      return true;
    } finally {
      freePtr(ref);
      freePtr(point);
      freePtr(sel);
      if (pos != null) freePtr(pos);
      if (geom != null) freePtr(geom);
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('VtSelectionController is closed');
  }
}

/// Format the terminal's active selection (or [selection] snapshot) as text.
///
/// Uses `GHOSTTY_FORMATTER_FORMAT_PLAIN` with unwrap+trim to match Ghostty
/// clipboard copy semantics. Returns null when there is no selection.
Future<String?> copySelectionText(
  GhosttyVtNative n,
  Pointer term, {
  Pointer<GhosttySelectionNative>? selection,
  int format = kFormatterFormatPlain,
  bool unwrap = true,
  bool trim = true,
}) async {
  final opts = mallocBytes<GhosttySelectionFormatOptionsNative>(
    1,
    sizeOf<GhosttySelectionFormatOptionsNative>(),
  );
  final outLen = mallocBytes<Size>(1, sizeOf<Size>());
  try {
    opts.ref
      ..size = sizeOf<GhosttySelectionFormatOptionsNative>()
      ..emit = format
      ..unwrap = unwrap
      ..trim = trim
      ..selection = selection ?? nullptr;

    // Query required size.
    var rc = n.selectionFormatBuf(
      term.cast(),
      opts,
      nullptr,
      0,
      outLen,
    );
    if (rc == kGhosttyNoValue) return null;
    if (rc != kGhosttyOutOfSpace && rc != kGhosttySuccess) {
      throw StateError('selection_format_buf size query failed: $rc');
    }
    final need = outLen.value;
    if (need <= 0) return '';

    final buf = mallocBytes<Uint8>(need, 1);
    try {
      rc = n.selectionFormatBuf(
        term.cast(),
        opts,
        buf,
        need,
        outLen,
      );
      if (rc == kGhosttyNoValue) return null;
      if (rc != kGhosttySuccess) {
        throw StateError('selection_format_buf failed: $rc');
      }
      final written = outLen.value;
      if (written <= 0) return '';
      final bytes = Uint8List.fromList(buf.asTypedList(written));
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      freePtr(buf);
    }
  } finally {
    freePtr(opts);
    freePtr(outLen);
  }
}

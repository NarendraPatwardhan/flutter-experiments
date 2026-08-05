import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'frame.dart';
import 'render.dart';
import 'theme.dart';

/// Defaults when the terminal has no OSC/theme colors set (Ghostty-like dark).
const Color kVtDefaultBg = VtTheme.background;
const Color kVtDefaultFg = VtTheme.foreground;
const Color kVtDefaultCursor = VtTheme.cursor;

/// Owns a Ghostty terminal + render state. Not thread-safe — call from one isolate.
class GhosttyVtSession {
  GhosttyVtSession._({
    required GhosttyVtNative native,
    required Pointer<Void> terminal,
    required Pointer<Void> renderState,
    required Pointer<Void> rowIter,
    required Pointer<Void> cells,
    required this.cols,
    required this.rows,
  })  : _native = native,
        _terminal = terminal,
        _renderState = renderState,
        _rowIter = rowIter,
        _cells = cells;

  final GhosttyVtNative _native;
  Pointer<Void> _terminal;
  Pointer<Void> _renderState;
  Pointer<Void> _rowIter;
  Pointer<Void> _cells;
  int cols;
  int rows;
  bool _closed = false;

  /// Open libghostty-vt and create a terminal of [cols]×[rows].
  factory GhosttyVtSession.open({
    String? libraryPath,
    int cols = 80,
    int rows = 24,
  }) {
    final native = GhosttyVtNative.open(libraryPath);
    final termOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final rsOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final rowOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final cellsOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    try {
      var rc = native.terminalNew(nullptr, termOut, cols, rows);
      if (rc != kGhosttySuccess) {
        throw StateError('ghostty_terminal_new failed: $rc');
      }
      final terminal = termOut.value;

      rc = native.renderStateNew(nullptr, rsOut);
      if (rc != kGhosttySuccess) {
        native.terminalFree(terminal);
        throw StateError('ghostty_render_state_new failed: $rc');
      }
      final renderState = rsOut.value;

      rc = native.rowIteratorNew(nullptr, rowOut);
      if (rc != kGhosttySuccess) {
        native.renderStateFree(renderState);
        native.terminalFree(terminal);
        throw StateError('ghostty_render_state_row_iterator_new failed: $rc');
      }
      final rowIter = rowOut.value;

      rc = native.rowCellsNew(nullptr, cellsOut);
      if (rc != kGhosttySuccess) {
        native.rowIteratorFree(rowIter);
        native.renderStateFree(renderState);
        native.terminalFree(terminal);
        throw StateError('ghostty_render_state_row_cells_new failed: $rc');
      }
      final cells = cellsOut.value;

      final session = GhosttyVtSession._(
        native: native,
        terminal: terminal,
        renderState: renderState,
        rowIter: rowIter,
        cells: cells,
        cols: cols,
        rows: rows,
      );
      session._applyDefaultTheme();
      return session;
    } finally {
      freePtr(termOut);
      freePtr(rsOut);
      freePtr(rowOut);
      freePtr(cellsOut);
    }
  }

  void _applyDefaultTheme() {
    final bg = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final fg = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final cur = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final palette =
        mallocBytes<GhosttyColorRgb>(256, sizeOf<GhosttyColorRgb>());
    try {
      bg.ref
        ..r = kVtDefaultBg.red
        ..g = kVtDefaultBg.green
        ..b = kVtDefaultBg.blue;
      fg.ref
        ..r = kVtDefaultFg.red
        ..g = kVtDefaultFg.green
        ..b = kVtDefaultFg.blue;
      cur.ref
        ..r = kVtDefaultCursor.red
        ..g = kVtDefaultCursor.green
        ..b = kVtDefaultCursor.blue;
      void check(int rc, String what) {
        if (rc != kGhosttySuccess) {
          throw StateError('ghostty_terminal_set($what) failed: $rc');
        }
      }

      check(
        _native.terminalSet(
          _terminal,
          kTerminalOptColorBackground,
          bg.cast(),
        ),
        'COLOR_BACKGROUND',
      );
      check(
        _native.terminalSet(
          _terminal,
          kTerminalOptColorForeground,
          fg.cast(),
        ),
        'COLOR_FOREGROUND',
      );
      check(
        _native.terminalSet(
          _terminal,
          kTerminalOptColorCursor,
          cur.cast(),
        ),
        'COLOR_CURSOR',
      );
      _native.colorPaletteDefault(palette);
      check(
        _native.terminalSet(
          _terminal,
          kTerminalOptColorPalette,
          palette.cast(),
        ),
        'COLOR_PALETTE',
      );
    } finally {
      freePtr(bg);
      freePtr(fg);
      freePtr(cur);
      freePtr(palette);
    }
  }

  /// Feed raw bytes (VT sequences or plain text) into the emulator.
  void write(Uint8List data) {
    _ensureOpen();
    if (data.isEmpty) return;
    final buf = mallocBytes<Uint8>(data.length, sizeOf<Uint8>());
    try {
      buf.asTypedList(data.length).setAll(0, data);
      _native.terminalVtWrite(_terminal, buf, data.length);
    } finally {
      freePtr(buf);
    }
  }

  /// Write UTF-8 text, normalizing lone LF → CRLF for TTY semantics.
  void writeText(String text) {
    write(normalizeNewlines(Uint8List.fromList(utf8.encode(text))));
  }

  /// Write guest bytes (AgentOS take_output / exec stdout), LF-normalized.
  void writeGuest(Uint8List data) {
    write(normalizeNewlines(data));
  }

  static Uint8List normalizeNewlines(Uint8List data) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i++) {
      final b = data[i];
      if (b == 0x0a && (i == 0 || data[i - 1] != 0x0d)) {
        out.addByte(0x0d);
      }
      out.addByte(b);
    }
    return out.toBytes();
  }

  /// Resize grid (and report pixel cell size for image protocols).
  void resize(int newCols, int newRows, {int cellW = 8, int cellH = 16}) {
    _ensureOpen();
    if (newCols < 1 || newRows < 1) return;
    final rc = _native.terminalResize(
      _terminal,
      newCols,
      newRows,
      cellW,
      cellH,
    );
    if (rc != kGhosttySuccess) {
      throw StateError('ghostty_terminal_resize failed: $rc');
    }
    cols = newCols;
    rows = newRows;
  }

  /// Snapshot viewport cells + cursor into a pure-Dart [VtFrame].
  ///
  /// Delegates to [projectRenderState] (G1 style + G4 partial dirty).
  VtFrame snapshot({VtFrame? previous}) {
    _ensureOpen();
    final frame = projectRenderState(
      native: _native,
      terminal: _terminal,
      renderState: _renderState,
      rowIter: _rowIter,
      cells: _cells,
      previous: previous,
      onHandles: (rowIter, cells) {
        _rowIter = rowIter.cast<Void>();
        _cells = cells.cast<Void>();
      },
    );
    cols = frame.cols;
    rows = frame.rows;
    return frame;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _native.rowCellsFree(_cells);
    _native.rowIteratorFree(_rowIter);
    _native.renderStateFree(_renderState);
    _native.terminalFree(_terminal);
    _cells = nullptr;
    _rowIter = nullptr;
    _renderState = nullptr;
    _terminal = nullptr;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('GhosttyVtSession is closed');
  }
}

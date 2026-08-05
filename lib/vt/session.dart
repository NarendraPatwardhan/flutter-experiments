import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'frame.dart';

/// Product defaults (Catppuccin-ish dark) when terminal theme is unset.
const Color kVtDefaultBg = Color(0xFF1E1E2E);
const Color kVtDefaultFg = Color(0xFFCDD6F4);
const Color kVtDefaultCursor = Color(0xFFF5E0DC);

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
      _native.terminalSet(
        _terminal,
        kTerminalOptColorBackground,
        bg.cast(),
      );
      _native.terminalSet(
        _terminal,
        kTerminalOptColorForeground,
        fg.cast(),
      );
      _native.terminalSet(
        _terminal,
        kTerminalOptColorCursor,
        cur.cast(),
      );
    } finally {
      freePtr(bg);
      freePtr(fg);
      freePtr(cur);
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
  VtFrame snapshot() {
    _ensureOpen();
    final rc = _native.renderStateUpdate(_renderState, _terminal);
    if (rc != kGhosttySuccess) {
      throw StateError('ghostty_render_state_update failed: $rc');
    }

    final colsPtr = mallocBytes<Uint16>(1, sizeOf<Uint16>());
    final rowsPtr = mallocBytes<Uint16>(1, sizeOf<Uint16>());
    final bgPtr = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final fgPtr = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final boolPtr = mallocBytes<Uint8>(1, sizeOf<Uint8>());
    final u16Ptr = mallocBytes<Uint16>(1, sizeOf<Uint16>());
    final i32Ptr = mallocBytes<Int32>(1, sizeOf<Int32>());
    final u32Ptr = mallocBytes<Uint32>(1, sizeOf<Uint32>());
    final rowIterSlot =
        mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final cellsSlot =
        mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final utf8Scratch = mallocBytes<Uint8>(64, sizeOf<Uint8>());
    final bufferPtr = mallocBytes<GhosttyBuffer>(1, sizeOf<GhosttyBuffer>());
    final codepoints = mallocBytes<Uint32>(16, sizeOf<Uint32>());

    try {
      _check(_native.renderStateGet(
        _renderState,
        kRenderDataCols,
        colsPtr.cast(),
      ));
      _check(_native.renderStateGet(
        _renderState,
        kRenderDataRows,
        rowsPtr.cast(),
      ));
      final c = colsPtr.value;
      final r = rowsPtr.value;

      Color bg = kVtDefaultBg;
      Color fg = kVtDefaultFg;
      var grc = _native.renderStateGet(
        _renderState,
        kRenderDataColorBackground,
        bgPtr.cast(),
      );
      if (grc == kGhosttySuccess) {
        bg = Color.fromARGB(255, bgPtr.ref.r, bgPtr.ref.g, bgPtr.ref.b);
      }
      grc = _native.renderStateGet(
        _renderState,
        kRenderDataColorForeground,
        fgPtr.cast(),
      );
      if (grc == kGhosttySuccess) {
        fg = Color.fromARGB(255, fgPtr.ref.r, fgPtr.ref.g, fgPtr.ref.b);
      }

      boolPtr.value = 0;
      _native.renderStateGet(
        _renderState,
        kRenderDataCursorVisible,
        boolPtr.cast(),
      );
      final cursorVisible = boolPtr.value != 0;

      boolPtr.value = 0;
      _native.renderStateGet(
        _renderState,
        kRenderDataCursorViewportHasValue,
        boolPtr.cast(),
      );
      final cursorInViewport = boolPtr.value != 0;

      int? cx;
      int? cy;
      var cursorStyle = VtCursorStyle.block;
      if (cursorVisible && cursorInViewport) {
        _native.renderStateGet(
          _renderState,
          kRenderDataCursorViewportX,
          u16Ptr.cast(),
        );
        cx = u16Ptr.value;
        _native.renderStateGet(
          _renderState,
          kRenderDataCursorViewportY,
          u16Ptr.cast(),
        );
        cy = u16Ptr.value;
        i32Ptr.value = kCursorStyleBlock;
        _native.renderStateGet(
          _renderState,
          kRenderDataCursorVisualStyle,
          i32Ptr.cast(),
        );
        cursorStyle = switch (i32Ptr.value) {
          kCursorStyleBar => VtCursorStyle.bar,
          kCursorStyleUnderline => VtCursorStyle.underline,
          kCursorStyleBlockHollow => VtCursorStyle.blockHollow,
          _ => VtCursorStyle.block,
        };
      }

      // Seed row iterator from render state (resets to before first row).
      rowIterSlot.value = _rowIter;
      _check(_native.renderStateGet(
        _renderState,
        kRenderDataRowIterator,
        rowIterSlot.cast(),
      ));
      // get may rewrite the handle; keep our field in sync.
      _rowIter = rowIterSlot.value;

      final cells = List<VtCell>.filled(c * r, const VtCell());
      var y = 0;
      while (_native.rowIteratorNext(_rowIter) && y < r) {
        cellsSlot.value = _cells;
        final cellRc = _native.rowGet(
          _rowIter,
          kRowDataCells,
          cellsSlot.cast(),
        );
        if (cellRc != kGhosttySuccess) {
          y++;
          continue;
        }
        _cells = cellsSlot.value;

        var x = 0;
        while (_native.rowCellsNext(_cells) && x < c) {
          cells[y * c + x] = _readCell(
            bg: bg,
            fg: fg,
            u32Ptr: u32Ptr,
            bgPtr: bgPtr,
            fgPtr: fgPtr,
            utf8Scratch: utf8Scratch,
            bufferPtr: bufferPtr,
            codepoints: codepoints,
          );
          x++;
        }
        // Pad remaining columns if iterator ended early.
        while (x < c) {
          cells[y * c + x] = const VtCell();
          x++;
        }

        // Clear row dirty.
        boolPtr.value = 0;
        _native.rowSet(_rowIter, kRowOptionDirty, boolPtr.cast());
        y++;
      }

      // Clear global dirty.
      i32Ptr.value = kRenderDirtyFalse;
      _native.renderStateSet(
        _renderState,
        kRenderOptionDirty,
        i32Ptr.cast(),
      );

      cols = c;
      rows = r;
      return VtFrame(
        cols: c,
        rows: r,
        cells: cells,
        background: bg,
        foreground: fg,
        cursorX: cx,
        cursorY: cy,
        cursorVisible: cursorVisible && cursorInViewport,
        cursorStyle: cursorStyle,
      );
    } finally {
      freePtr(colsPtr);
      freePtr(rowsPtr);
      freePtr(bgPtr);
      freePtr(fgPtr);
      freePtr(boolPtr);
      freePtr(u16Ptr);
      freePtr(i32Ptr);
      freePtr(u32Ptr);
      freePtr(rowIterSlot);
      freePtr(cellsSlot);
      freePtr(utf8Scratch);
      freePtr(bufferPtr);
      freePtr(codepoints);
    }
  }

  VtCell _readCell({
    required Color bg,
    required Color fg,
    required Pointer<Uint32> u32Ptr,
    required Pointer<GhosttyColorRgb> bgPtr,
    required Pointer<GhosttyColorRgb> fgPtr,
    required Pointer<Uint8> utf8Scratch,
    required Pointer<GhosttyBuffer> bufferPtr,
    required Pointer<Uint32> codepoints,
  }) {
    u32Ptr.value = 0;
    _native.rowCellsGet(_cells, kCellDataGraphemesLen, u32Ptr.cast());
    final glen = u32Ptr.value;
    if (glen == 0) {
      Color? cellBg;
      final bgRc = _native.rowCellsGet(
        _cells,
        kCellDataBgColor,
        bgPtr.cast(),
      );
      if (bgRc == kGhosttySuccess) {
        cellBg = Color.fromARGB(255, bgPtr.ref.r, bgPtr.ref.g, bgPtr.ref.b);
      }
      return VtCell(bg: cellBg);
    }

    // Prefer UTF-8 buffer path.
    bufferPtr.ref
      ..ptr = utf8Scratch
      ..cap = 64
      ..len = 0;
    var text = '';
    final utfRc = _native.rowCellsGet(
      _cells,
      kCellDataGraphemesUtf8,
      bufferPtr.cast(),
    );
    if (utfRc == kGhosttySuccess && bufferPtr.ref.len > 0) {
      text = utf8.decode(
        utf8Scratch.asTypedList(bufferPtr.ref.len),
        allowMalformed: true,
      );
    } else if (utfRc == kGhosttyOutOfSpace) {
      final need = bufferPtr.ref.len;
      final big = mallocBytes<Uint8>(need, sizeOf<Uint8>());
      try {
        bufferPtr.ref
          ..ptr = big
          ..cap = need
          ..len = 0;
        final rc2 = _native.rowCellsGet(
          _cells,
          kCellDataGraphemesUtf8,
          bufferPtr.cast(),
        );
        if (rc2 == kGhosttySuccess && bufferPtr.ref.len > 0) {
          text = utf8.decode(
            big.asTypedList(bufferPtr.ref.len),
            allowMalformed: true,
          );
        }
      } finally {
        freePtr(big);
      }
    } else {
      // Fallback: codepoint buffer (first codepoint only for paint).
      final n = glen > 16 ? 16 : glen;
      _native.rowCellsGet(
        _cells,
        kCellDataGraphemesBuf,
        codepoints.cast(),
      );
      final units = <int>[];
      for (var i = 0; i < n; i++) {
        final cp = codepoints[i];
        if (cp == 0) break;
        units.add(cp);
      }
      if (units.isNotEmpty) {
        text = String.fromCharCodes(units);
      }
    }

    Color? cellFg;
    Color? cellBg;
    final fgRc = _native.rowCellsGet(
      _cells,
      kCellDataFgColor,
      fgPtr.cast(),
    );
    if (fgRc == kGhosttySuccess) {
      cellFg = Color.fromARGB(255, fgPtr.ref.r, fgPtr.ref.g, fgPtr.ref.b);
    }
    final bgRc = _native.rowCellsGet(
      _cells,
      kCellDataBgColor,
      bgPtr.cast(),
    );
    if (bgRc == kGhosttySuccess) {
      cellBg = Color.fromARGB(255, bgPtr.ref.r, bgPtr.ref.g, bgPtr.ref.b);
    }

    return VtCell(text: text, fg: cellFg, bg: cellBg);
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

  void _check(int rc) {
    if (rc != kGhosttySuccess) {
      throw StateError('libghostty-vt error: $rc');
    }
  }
}

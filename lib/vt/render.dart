// Render-state → VtFrame projection (Ghostty VT embed G1 + G4 partial dirty).
// libghostty-vt owns terminal truth; this file only snapshots for Flutter paint.

import 'dart:convert';
import 'dart:ffi';
import 'dart:ui' show Color;

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'frame.dart';
import 'theme.dart';

/// Defaults when render state has no colors set.
const Color kVtRenderDefaultBg = VtTheme.background;
const Color kVtRenderDefaultFg = VtTheme.foreground;

/// Project libghostty-vt render state into an immutable [VtFrame].
///
/// Calls [renderStateUpdate], walks rows/cells (graphemes, colors, style,
/// selection), applies inverse at projection (swap fg/bg), then clears
/// per-row + global dirty flags.
///
/// Dirty policy (G4):
/// - [VtDirtyKind.clean] + [previous]: return [previous] without re-walking cells
///   (still refreshes cursor/colors and clears global dirty).
/// - [VtDirtyKind.partial] + [previous] same size: merge dirty rows into a copy
///   of [previous.cells] and set [VtFrame.dirtyRows].
/// - otherwise: full rebuild; [VtFrame.dirtyRows] is null.
///
/// [onHandles] is invoked when get APIs rewrite [rowIter] / [cells] so the
/// session owner can keep its fields in sync.
VtFrame projectRenderState({
  required GhosttyVtNative native,
  required Pointer terminal,
  required Pointer renderState,
  required Pointer rowIter,
  required Pointer cells,
  void Function(Pointer rowIter, Pointer cells)? onHandles,
  VtFrame? previous,
}) {
  final term = terminal.cast<Void>();
  final state = renderState.cast<Void>();

  final rc = native.renderStateUpdate(state, term);
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
  final rowIterSlot = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
  final cellsSlot = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
  final utf8Scratch = mallocBytes<Uint8>(64, sizeOf<Uint8>());
  final bufferPtr = mallocBytes<GhosttyBuffer>(1, sizeOf<GhosttyBuffer>());
  final codepoints = mallocBytes<Uint32>(16, sizeOf<Uint32>());
  final stylePtr =
      mallocBytes<GhosttyStyleNative>(1, sizeOf<GhosttyStyleNative>());

  var liveRowIter = rowIter.cast<Void>();
  var liveCells = cells.cast<Void>();

  try {
    _check(native.renderStateGet(state, kRenderDataCols, colsPtr.cast()));
    _check(native.renderStateGet(state, kRenderDataRows, rowsPtr.cast()));
    final c = colsPtr.value;
    final r = rowsPtr.value;

    Color bg = kVtRenderDefaultBg;
    Color fg = kVtRenderDefaultFg;
    var grc =
        native.renderStateGet(state, kRenderDataColorBackground, bgPtr.cast());
    if (grc == kGhosttySuccess) {
      bg = Color.fromARGB(255, bgPtr.ref.r, bgPtr.ref.g, bgPtr.ref.b);
    }
    grc =
        native.renderStateGet(state, kRenderDataColorForeground, fgPtr.cast());
    if (grc == kGhosttySuccess) {
      fg = Color.fromARGB(255, fgPtr.ref.r, fgPtr.ref.g, fgPtr.ref.b);
    }

    // Optional cursor color.
    Color? cursorColor;
    boolPtr.value = 0;
    native.renderStateGet(
      state,
      kRenderDataColorCursorHasValue,
      boolPtr.cast(),
    );
    if (boolPtr.value != 0) {
      grc = native.renderStateGet(state, kRenderDataColorCursor, bgPtr.cast());
      if (grc == kGhosttySuccess) {
        cursorColor =
            Color.fromARGB(255, bgPtr.ref.r, bgPtr.ref.g, bgPtr.ref.b);
      }
    }

    // Dirty kind first (snapshot before clear).
    i32Ptr.value = kRenderDirtyFull;
    native.renderStateGet(state, kRenderDataDirty, i32Ptr.cast());
    final dirty = switch (i32Ptr.value) {
      kRenderDirtyFalse => VtDirtyKind.clean,
      kRenderDirtyPartial => VtDirtyKind.partial,
      _ => VtDirtyKind.full,
    };

    boolPtr.value = 0;
    native.renderStateGet(state, kRenderDataCursorVisible, boolPtr.cast());
    final cursorVisible = boolPtr.value != 0;

    boolPtr.value = 0;
    native.renderStateGet(
      state,
      kRenderDataCursorViewportHasValue,
      boolPtr.cast(),
    );
    final cursorInViewport = boolPtr.value != 0;

    boolPtr.value = 0;
    native.renderStateGet(state, kRenderDataCursorBlinking, boolPtr.cast());
    final cursorBlink = boolPtr.value != 0;

    boolPtr.value = 0;
    native.renderStateGet(
      state,
      kRenderDataCursorViewportWideTail,
      boolPtr.cast(),
    );
    final cursorOnWideTail = boolPtr.value != 0;

    int? cx;
    int? cy;
    var cursorStyle = VtCursorStyle.block;
    if (cursorVisible && cursorInViewport) {
      native.renderStateGet(state, kRenderDataCursorViewportX, u16Ptr.cast());
      cx = u16Ptr.value;
      native.renderStateGet(state, kRenderDataCursorViewportY, u16Ptr.cast());
      cy = u16Ptr.value;
      i32Ptr.value = kCursorStyleBlock;
      native.renderStateGet(state, kRenderDataCursorVisualStyle, i32Ptr.cast());
      cursorStyle = switch (i32Ptr.value) {
        kCursorStyleBar => VtCursorStyle.bar,
        kCursorStyleUnderline => VtCursorStyle.underline,
        kCursorStyleBlockHollow => VtCursorStyle.blockHollow,
        _ => VtCursorStyle.block,
      };
    }

    final prev = previous;
    final sameSize = prev != null && prev.cols == c && prev.rows == r;

    // Clean: reuse previous cells without re-walking (still refresh meta).
    if (dirty == VtDirtyKind.clean && sameSize && prev != null) {
      i32Ptr.value = kRenderDirtyFalse;
      native.renderStateSet(state, kRenderOptionDirty, i32Ptr.cast());
      return prev.copyWithMeta(
        background: bg,
        foreground: fg,
        cursorColor: cursorColor,
        clearCursorColor: cursorColor == null,
        cursorX: cx,
        cursorY: cy,
        clearCursorPos: true,
        cursorVisible: cursorVisible && cursorInViewport,
        cursorStyle: cursorStyle,
        cursorBlink: cursorBlink,
        cursorOnWideTail: cursorOnWideTail,
        dirty: VtDirtyKind.clean,
        dirtyRows: const <int>{},
      );
    }

    // Seed row iterator from render state (resets to before first row).
    rowIterSlot.value = liveRowIter;
    _check(native.renderStateGet(
      state,
      kRenderDataRowIterator,
      rowIterSlot.cast(),
    ));
    liveRowIter = rowIterSlot.value;
    onHandles?.call(liveRowIter, liveCells);

    final partial = dirty == VtDirtyKind.partial && sameSize && prev != null;
    final List<VtCell> outCells;
    final Set<int>? dirtyRowsOut;
    if (partial && prev != null) {
      outCells = List<VtCell>.from(prev.cells);
      dirtyRowsOut = <int>{};
    } else {
      outCells = List<VtCell>.filled(c * r, const VtCell());
      dirtyRowsOut = null;
    }

    var y = 0;
    while (native.rowIteratorNext(liveRowIter) && y < r) {
      var rowDirty = true;
      if (partial) {
        boolPtr.value = 1;
        native.rowGet(liveRowIter, kRowDataDirty, boolPtr.cast());
        rowDirty = boolPtr.value != 0;
      }

      if (rowDirty) {
        cellsSlot.value = liveCells;
        final cellRc = native.rowGet(
          liveRowIter,
          kRowDataCells,
          cellsSlot.cast(),
        );
        if (cellRc == kGhosttySuccess) {
          liveCells = cellsSlot.value;
          onHandles?.call(liveRowIter, liveCells);

          var x = 0;
          while (native.rowCellsNext(liveCells) && x < c) {
            outCells[y * c + x] = _readCell(
              native: native,
              cells: liveCells,
              bgPtr: bgPtr,
              fgPtr: fgPtr,
              u32Ptr: u32Ptr,
              boolPtr: boolPtr,
              utf8Scratch: utf8Scratch,
              bufferPtr: bufferPtr,
              codepoints: codepoints,
              stylePtr: stylePtr,
            );
            x++;
          }
          while (x < c) {
            outCells[y * c + x] = const VtCell();
            x++;
          }
        }
        dirtyRowsOut?.add(y);
      }

      // Clear row dirty.
      boolPtr.value = 0;
      native.rowSet(liveRowIter, kRowOptionDirty, boolPtr.cast());
      y++;
    }

    // Clear global dirty.
    i32Ptr.value = kRenderDirtyFalse;
    native.renderStateSet(state, kRenderOptionDirty, i32Ptr.cast());

    return VtFrame(
      cols: c,
      rows: r,
      cells: outCells,
      background: bg,
      foreground: fg,
      cursorColor: cursorColor,
      cursorX: cx,
      cursorY: cy,
      cursorVisible: cursorVisible && cursorInViewport,
      cursorStyle: cursorStyle,
      cursorBlink: cursorBlink,
      cursorOnWideTail: cursorOnWideTail,
      dirty: dirty,
      dirtyRows: dirtyRowsOut,
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
    freePtr(stylePtr);
  }
}

VtCell _readCell({
  required GhosttyVtNative native,
  required Pointer<Void> cells,
  required Pointer<GhosttyColorRgb> bgPtr,
  required Pointer<GhosttyColorRgb> fgPtr,
  required Pointer<Uint32> u32Ptr,
  required Pointer<Uint8> boolPtr,
  required Pointer<Uint8> utf8Scratch,
  required Pointer<GhosttyBuffer> bufferPtr,
  required Pointer<Uint32> codepoints,
  required Pointer<GhosttyStyleNative> stylePtr,
}) {
  u32Ptr.value = 0;
  native.rowCellsGet(cells, kCellDataGraphemesLen, u32Ptr.cast());
  final glen = u32Ptr.value;

  var text = '';
  if (glen > 0) {
    text = _readGraphemes(
      native: native,
      cells: cells,
      glen: glen,
      utf8Scratch: utf8Scratch,
      bufferPtr: bufferPtr,
      codepoints: codepoints,
    );
  }

  Color? cellFg;
  Color? cellBg;
  final fgRc = native.rowCellsGet(cells, kCellDataFgColor, fgPtr.cast());
  if (fgRc == kGhosttySuccess) {
    cellFg = Color.fromARGB(255, fgPtr.ref.r, fgPtr.ref.g, fgPtr.ref.b);
  }
  final bgRc = native.rowCellsGet(cells, kCellDataBgColor, bgPtr.cast());
  if (bgRc == kGhosttySuccess) {
    cellBg = Color.fromARGB(255, bgPtr.ref.r, bgPtr.ref.g, bgPtr.ref.b);
  }

  // Style flags (GhosttyStyleNative). Size is set for ABI versioning.
  var bold = false;
  var italic = false;
  var faint = false;
  var inverse = false;
  var invisible = false;
  var strikethrough = false;
  var overline = false;
  var underline = VtUnderline.none;
  Color? underlineColor;

  stylePtr.ref.size = sizeOf<GhosttyStyleNative>();
  final styleRc = native.rowCellsGet(cells, kCellDataStyle, stylePtr.cast());
  if (styleRc == kGhosttySuccess) {
    final s = stylePtr.ref;
    bold = s.bold;
    italic = s.italic;
    faint = s.faint;
    inverse = s.inverse;
    invisible = s.invisible;
    strikethrough = s.strikethrough;
    overline = s.overline;
    underline = _mapUnderline(s.underline);
    underlineColor = _styleColorToDart(s.underlineColor);
  }

  boolPtr.value = 0;
  native.rowCellsGet(cells, kCellDataSelected, boolPtr.cast());
  final selected = boolPtr.value != 0;

  // Apply inverse at projection: swap resolved fg/bg.
  // Bold-as-bright is NOT applied — cell fg/bg are already RGB-resolved by lib-vt.
  if (inverse) {
    final tmp = cellFg;
    cellFg = cellBg;
    cellBg = tmp;
  }

  if (glen == 0 &&
      cellBg == null &&
      !bold &&
      !italic &&
      !faint &&
      !inverse &&
      !invisible &&
      !strikethrough &&
      !overline &&
      underline == VtUnderline.none &&
      !selected) {
    return const VtCell();
  }

  return VtCell(
    text: text,
    fg: cellFg,
    bg: cellBg,
    bold: bold,
    italic: italic,
    faint: faint,
    inverse: inverse,
    invisible: invisible,
    strikethrough: strikethrough,
    overline: overline,
    underline: underline,
    underlineColor: underlineColor,
    selected: selected,
  );
}

String _readGraphemes({
  required GhosttyVtNative native,
  required Pointer<Void> cells,
  required int glen,
  required Pointer<Uint8> utf8Scratch,
  required Pointer<GhosttyBuffer> bufferPtr,
  required Pointer<Uint32> codepoints,
}) {
  bufferPtr.ref
    ..ptr = utf8Scratch
    ..cap = 64
    ..len = 0;
  final utfRc = native.rowCellsGet(
    cells,
    kCellDataGraphemesUtf8,
    bufferPtr.cast(),
  );
  if (utfRc == kGhosttySuccess && bufferPtr.ref.len > 0) {
    return utf8.decode(
      utf8Scratch.asTypedList(bufferPtr.ref.len),
      allowMalformed: true,
    );
  }
  if (utfRc == kGhosttyOutOfSpace) {
    final need = bufferPtr.ref.len;
    final big = mallocBytes<Uint8>(need, sizeOf<Uint8>());
    try {
      bufferPtr.ref
        ..ptr = big
        ..cap = need
        ..len = 0;
      final rc2 = native.rowCellsGet(
        cells,
        kCellDataGraphemesUtf8,
        bufferPtr.cast(),
      );
      if (rc2 == kGhosttySuccess && bufferPtr.ref.len > 0) {
        return utf8.decode(
          big.asTypedList(bufferPtr.ref.len),
          allowMalformed: true,
        );
      }
    } finally {
      freePtr(big);
    }
  }

  // Fallback: codepoint buffer.
  final n = glen > 16 ? 16 : glen;
  native.rowCellsGet(cells, kCellDataGraphemesBuf, codepoints.cast());
  final units = <int>[];
  for (var i = 0; i < n; i++) {
    final cp = codepoints[i];
    if (cp == 0) break;
    units.add(cp);
  }
  if (units.isEmpty) return '';
  return String.fromCharCodes(units);
}

VtUnderline _mapUnderline(int v) {
  return switch (v) {
    kUnderlineSingle => VtUnderline.single,
    kUnderlineDouble => VtUnderline.double_,
    kUnderlineCurly => VtUnderline.curly,
    kUnderlineDotted => VtUnderline.dotted,
    kUnderlineDashed => VtUnderline.dashed,
    _ => VtUnderline.none,
  };
}

Color? _styleColorToDart(GhosttyStyleColorNative c) {
  switch (c.tag) {
    case kStyleColorRgb:
      return Color.fromARGB(255, c.rgbR, c.rgbG, c.rgbB);
    case kStyleColorPalette:
      // Palette indices are resolved into cell fg/bg by lib-vt for paint colors;
      // underline color may still be a palette tag — leave null so paint uses fg.
      return null;
    default:
      return null;
  }
}

void _check(int rc) {
  if (rc != kGhosttySuccess) {
    throw StateError('libghostty-vt error: $rc');
  }
}

// Hand-written dart:ffi bindings for libghostty-vt (ghostty C ABI).
// Keep enum values in sync with include/ghostty/vt/*.h @ pin 9e30f70.

import 'dart:ffi';
import 'dart:io';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;

// --- Result / data enums (c_int underlying) ---------------------------------

const int kGhosttySuccess = 0;
const int kGhosttyOutOfMemory = -1;
const int kGhosttyInvalidValue = -2;
const int kGhosttyOutOfSpace = -3;
const int kGhosttyNoValue = -4;

const int kRenderDataCols = 1;
const int kRenderDataRows = 2;
const int kRenderDataDirty = 3;
const int kRenderDataRowIterator = 4;
const int kRenderDataColorBackground = 5;
const int kRenderDataColorForeground = 6;
const int kRenderDataCursorVisible = 11;
const int kRenderDataCursorViewportHasValue = 14;
const int kRenderDataCursorViewportX = 15;
const int kRenderDataCursorViewportY = 16;
const int kRenderDataCursorVisualStyle = 10;

const int kRenderDirtyFalse = 0;
const int kRenderOptionDirty = 0;

const int kRowDataDirty = 1;
const int kRowDataCells = 3;
const int kRowOptionDirty = 0;

const int kCellDataGraphemesLen = 3;
const int kCellDataGraphemesBuf = 4;
const int kCellDataBgColor = 5;
const int kCellDataFgColor = 6;
const int kCellDataGraphemesUtf8 = 9;

const int kCursorStyleBar = 0;
const int kCursorStyleBlock = 1;
const int kCursorStyleUnderline = 2;
const int kCursorStyleBlockHollow = 3;

const int kTerminalOptColorForeground = 11;
const int kTerminalOptColorBackground = 12;
const int kTerminalOptColorCursor = 13;

// --- Native structs ---------------------------------------------------------

final class GhosttyColorRgb extends Struct {
  @Uint8()
  external int r;

  @Uint8()
  external int g;

  @Uint8()
  external int b;
}

final class GhosttyBuffer extends Struct {
  external Pointer<Uint8> ptr;

  @Size()
  external int cap;

  @Size()
  external int len;
}

// --- Typedefs ---------------------------------------------------------------

typedef _TerminalNewNative = Int32 Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
  Uint16 cols,
  Uint16 rows,
);
typedef _TerminalNewDart = int Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
  int cols,
  int rows,
);

typedef _TerminalFreeNative = Void Function(Pointer<Void> terminal);
typedef _TerminalFreeDart = void Function(Pointer<Void> terminal);

typedef _TerminalVtWriteNative = Void Function(
  Pointer<Void> terminal,
  Pointer<Uint8> data,
  Size len,
);
typedef _TerminalVtWriteDart = void Function(
  Pointer<Void> terminal,
  Pointer<Uint8> data,
  int len,
);

typedef _TerminalResizeNative = Int32 Function(
  Pointer<Void> terminal,
  Uint16 cols,
  Uint16 rows,
  Uint32 cellW,
  Uint32 cellH,
);
typedef _TerminalResizeDart = int Function(
  Pointer<Void> terminal,
  int cols,
  int rows,
  int cellW,
  int cellH,
);

typedef _TerminalSetNative = Int32 Function(
  Pointer<Void> terminal,
  Int32 option,
  Pointer<Void> value,
);
typedef _TerminalSetDart = int Function(
  Pointer<Void> terminal,
  int option,
  Pointer<Void> value,
);

typedef _RenderNewNative = Int32 Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
);
typedef _RenderNewDart = int Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
);

typedef _RenderFreeNative = Void Function(Pointer<Void> state);
typedef _RenderFreeDart = void Function(Pointer<Void> state);

typedef _RenderUpdateNative = Int32 Function(
  Pointer<Void> state,
  Pointer<Void> terminal,
);
typedef _RenderUpdateDart = int Function(
  Pointer<Void> state,
  Pointer<Void> terminal,
);

typedef _RenderGetNative = Int32 Function(
  Pointer<Void> state,
  Int32 data,
  Pointer<Void> out,
);
typedef _RenderGetDart = int Function(
  Pointer<Void> state,
  int data,
  Pointer<Void> out,
);

typedef _RenderSetNative = Int32 Function(
  Pointer<Void> state,
  Int32 option,
  Pointer<Void> value,
);
typedef _RenderSetDart = int Function(
  Pointer<Void> state,
  int option,
  Pointer<Void> value,
);

typedef _RowIterNewNative = Int32 Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
);
typedef _RowIterNewDart = int Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
);

typedef _RowIterFreeNative = Void Function(Pointer<Void> iter);
typedef _RowIterFreeDart = void Function(Pointer<Void> iter);

typedef _RowIterNextNative = Bool Function(Pointer<Void> iter);
typedef _RowIterNextDart = bool Function(Pointer<Void> iter);

typedef _RowGetNative = Int32 Function(
  Pointer<Void> iter,
  Int32 data,
  Pointer<Void> out,
);
typedef _RowGetDart = int Function(
  Pointer<Void> iter,
  int data,
  Pointer<Void> out,
);

typedef _RowSetNative = Int32 Function(
  Pointer<Void> iter,
  Int32 option,
  Pointer<Void> value,
);
typedef _RowSetDart = int Function(
  Pointer<Void> iter,
  int option,
  Pointer<Void> value,
);

typedef _CellsNewNative = Int32 Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
);
typedef _CellsNewDart = int Function(
  Pointer<Void> allocator,
  Pointer<Pointer<Void>> out,
);

typedef _CellsFreeNative = Void Function(Pointer<Void> cells);
typedef _CellsFreeDart = void Function(Pointer<Void> cells);

typedef _CellsNextNative = Bool Function(Pointer<Void> cells);
typedef _CellsNextDart = bool Function(Pointer<Void> cells);

typedef _CellsGetNative = Int32 Function(
  Pointer<Void> cells,
  Int32 data,
  Pointer<Void> out,
);
typedef _CellsGetDart = int Function(
  Pointer<Void> cells,
  int data,
  Pointer<Void> out,
);

/// Low-level bindings to `libghostty-vt`.
class GhosttyVtNative {
  GhosttyVtNative._(this._lib)
      : terminalNew = _lib.lookupFunction<_TerminalNewNative, _TerminalNewDart>(
          'ghostty_terminal_new',
        ),
        terminalFree =
            _lib.lookupFunction<_TerminalFreeNative, _TerminalFreeDart>(
          'ghostty_terminal_free',
        ),
        terminalVtWrite =
            _lib.lookupFunction<_TerminalVtWriteNative, _TerminalVtWriteDart>(
          'ghostty_terminal_vt_write',
        ),
        terminalResize =
            _lib.lookupFunction<_TerminalResizeNative, _TerminalResizeDart>(
          'ghostty_terminal_resize',
        ),
        terminalSet =
            _lib.lookupFunction<_TerminalSetNative, _TerminalSetDart>(
          'ghostty_terminal_set',
        ),
        renderStateNew =
            _lib.lookupFunction<_RenderNewNative, _RenderNewDart>(
          'ghostty_render_state_new',
        ),
        renderStateFree =
            _lib.lookupFunction<_RenderFreeNative, _RenderFreeDart>(
          'ghostty_render_state_free',
        ),
        renderStateUpdate =
            _lib.lookupFunction<_RenderUpdateNative, _RenderUpdateDart>(
          'ghostty_render_state_update',
        ),
        renderStateGet =
            _lib.lookupFunction<_RenderGetNative, _RenderGetDart>(
          'ghostty_render_state_get',
        ),
        renderStateSet =
            _lib.lookupFunction<_RenderSetNative, _RenderSetDart>(
          'ghostty_render_state_set',
        ),
        rowIteratorNew =
            _lib.lookupFunction<_RowIterNewNative, _RowIterNewDart>(
          'ghostty_render_state_row_iterator_new',
        ),
        rowIteratorFree =
            _lib.lookupFunction<_RowIterFreeNative, _RowIterFreeDart>(
          'ghostty_render_state_row_iterator_free',
        ),
        rowIteratorNext =
            _lib.lookupFunction<_RowIterNextNative, _RowIterNextDart>(
          'ghostty_render_state_row_iterator_next',
        ),
        rowGet = _lib.lookupFunction<_RowGetNative, _RowGetDart>(
          'ghostty_render_state_row_get',
        ),
        rowSet = _lib.lookupFunction<_RowSetNative, _RowSetDart>(
          'ghostty_render_state_row_set',
        ),
        rowCellsNew = _lib.lookupFunction<_CellsNewNative, _CellsNewDart>(
          'ghostty_render_state_row_cells_new',
        ),
        rowCellsFree =
            _lib.lookupFunction<_CellsFreeNative, _CellsFreeDart>(
          'ghostty_render_state_row_cells_free',
        ),
        rowCellsNext =
            _lib.lookupFunction<_CellsNextNative, _CellsNextDart>(
          'ghostty_render_state_row_cells_next',
        ),
        rowCellsGet = _lib.lookupFunction<_CellsGetNative, _CellsGetDart>(
          'ghostty_render_state_row_cells_get',
        );

  final DynamicLibrary _lib;

  final _TerminalNewDart terminalNew;
  final _TerminalFreeDart terminalFree;
  final _TerminalVtWriteDart terminalVtWrite;
  final _TerminalResizeDart terminalResize;
  final _TerminalSetDart terminalSet;
  final _RenderNewDart renderStateNew;
  final _RenderFreeDart renderStateFree;
  final _RenderUpdateDart renderStateUpdate;
  final _RenderGetDart renderStateGet;
  final _RenderSetDart renderStateSet;
  final _RowIterNewDart rowIteratorNew;
  final _RowIterFreeDart rowIteratorFree;
  final _RowIterNextDart rowIteratorNext;
  final _RowGetDart rowGet;
  final _RowSetDart rowSet;
  final _CellsNewDart rowCellsNew;
  final _CellsFreeDart rowCellsFree;
  final _CellsNextDart rowCellsNext;
  final _CellsGetDart rowCellsGet;

  static GhosttyVtNative open([String? path]) {
    final p = path ?? _defaultLibPath();
    return GhosttyVtNative._(DynamicLibrary.open(p));
  }

  static String _defaultLibPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir/lib/libghostty-vt.so',
      '$exeDir/libghostty-vt.so',
      'libghostty-vt.so',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return candidates.first;
  }

  static String? findLibraryPath([String? exeDir]) {
    final base = exeDir ?? File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$base/lib/libghostty-vt.so',
      '$base/libghostty-vt.so',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}

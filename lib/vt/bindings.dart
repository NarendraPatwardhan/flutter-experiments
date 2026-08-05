// Hand-written dart:ffi bindings for libghostty-vt (ghostty C ABI).
// Keep enum values in sync with include/ghostty/vt/*.h @ pin 9e30f70.
// Key codes: see keys.dart (generated from key/event.h).

import 'dart:ffi';
import 'dart:io';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'keys.dart';
export 'keys.dart';

// --- Result / data enums (c_int underlying) ---------------------------------

const int kGhosttySuccess = 0;
const int kGhosttyOutOfMemory = -1;
const int kGhosttyInvalidValue = -2;
const int kGhosttyOutOfSpace = -3;
const int kGhosttyNoValue = -4;

// Render state data
const int kRenderDataCols = 1;
const int kRenderDataRows = 2;
const int kRenderDataDirty = 3;
const int kRenderDataRowIterator = 4;
const int kRenderDataColorBackground = 5;
const int kRenderDataColorForeground = 6;
const int kRenderDataColorCursor = 7;
const int kRenderDataColorCursorHasValue = 8;
const int kRenderDataColorPalette = 9;
const int kRenderDataCursorVisualStyle = 10;
const int kRenderDataCursorVisible = 11;
const int kRenderDataCursorBlinking = 12;
const int kRenderDataCursorPasswordInput = 13;
const int kRenderDataCursorViewportHasValue = 14;
const int kRenderDataCursorViewportX = 15;
const int kRenderDataCursorViewportY = 16;
const int kRenderDataCursorViewportWideTail = 17;

const int kRenderDirtyFalse = 0;
const int kRenderDirtyPartial = 1;
const int kRenderDirtyFull = 2;
const int kRenderOptionDirty = 0;

const int kRowDataDirty = 1;
const int kRowDataCells = 3;
const int kRowDataSelection = 4;
const int kRowOptionDirty = 0;

const int kCellDataRaw = 1;
const int kCellDataStyle = 2;
const int kCellDataGraphemesLen = 3;
const int kCellDataGraphemesBuf = 4;
const int kCellDataBgColor = 5;
const int kCellDataFgColor = 6;
const int kCellDataSelected = 7;
const int kCellDataHasStyling = 8;
const int kCellDataGraphemesUtf8 = 9;

const int kCursorStyleBar = 0;
const int kCursorStyleBlock = 1;
const int kCursorStyleUnderline = 2;
const int kCursorStyleBlockHollow = 3;

// Terminal options / data
const int kTerminalOptUserdata = 0;
const int kTerminalOptWritePty = 1;
const int kTerminalOptBell = 2;
const int kTerminalOptTitleChanged = 5;
const int kTerminalOptColorForeground = 11;
const int kTerminalOptColorBackground = 12;
const int kTerminalOptColorCursor = 13;
const int kTerminalOptColorPalette = 14;
const int kTerminalOptKittyImageStorageLimit = 15;
const int kTerminalOptSelection = 21;
const int kTerminalOptPwdChanged = 25;
const int kTerminalOptClipboardWrite = 26;
const int kTerminalOptDesktopNotification = 29;
const int kTerminalOptProgressReport = 30;
const int kTerminalOptContinuationMaxBytes = 31;

const int kTerminalDataCols = 1;
const int kTerminalDataRows = 2;
const int kTerminalDataScrollbar = 9;
const int kTerminalDataTitle = 12;
const int kTerminalDataPwd = 13;
const int kTerminalDataTotalRows = 14;
const int kTerminalDataScrollbackRows = 15;
const int kTerminalDataMouseTracking = 11;
const int kTerminalDataKittyGraphics = 30;

// Kitty graphics storage / image / placement (kitty_graphics.h)
const int kKittyGraphicsDataPlacementIterator = 1;
const int kKittyGraphicsDataGeneration = 2;

const int kKittyImageDataWidth = 3;
const int kKittyImageDataHeight = 4;
const int kKittyImageDataFormat = 5;
const int kKittyImageDataDataPtr = 7;
const int kKittyImageDataDataLen = 8;
const int kKittyImageDataGeneration = 9;

const int kKittyPlacementDataImageId = 1;
const int kKittyPlacementDataPlacementId = 2;
const int kKittyPlacementDataIsVirtual = 3;
const int kKittyPlacementDataXOffset = 4;
const int kKittyPlacementDataYOffset = 5;
const int kKittyPlacementDataColumns = 10;
const int kKittyPlacementDataRows = 11;
const int kKittyPlacementDataZ = 12;

const int kKittyImageFormatRgb = 0;
const int kKittyImageFormatRgba = 1;
const int kKittyImageFormatPng = 2;
const int kKittyImageFormatGrayAlpha = 3;
const int kKittyImageFormatGray = 4;

// System interface (sys.h)
const int kSysOptUserdata = 0;
const int kSysOptDecodePng = 1;
const int kSysOptLog = 2;

// Scrollback compression (terminal.h)
const int kCompressModeIncremental = 0;
const int kCompressModeFull = 1;
const int kCompressionModeIncremental = 0; // alias
const int kCompressionModeFull = 1; // alias
const int kCompressResultUnsupported = 0;
const int kCompressResultPending = 1;
const int kCompressResultComplete = 2;
const int kCompressionResultUnsupported = 0;
const int kCompressionResultPending = 1;
const int kCompressionResultComplete = 2;

// Progress (OSC 9;4)
const int kProgressStateRemove = 0;
const int kProgressStateSet = 1;
const int kProgressStateError = 2;
const int kProgressStateIndeterminate = 3;
const int kProgressStatePause = 4;

// Style color tags
const int kStyleColorNone = 0;
const int kStyleColorPalette = 1;
const int kStyleColorRgb = 2;

// Underline
const int kUnderlineNone = 0;
const int kUnderlineSingle = 1;
const int kUnderlineDouble = 2;
const int kUnderlineCurly = 3;
const int kUnderlineDotted = 4;
const int kUnderlineDashed = 5;

// Key action / mods
const int kKeyActionRelease = 0;
const int kKeyActionPress = 1;
const int kKeyActionRepeat = 2;
const int kModsShift = 1 << 0;
const int kModsCtrl = 1 << 1;
const int kModsAlt = 1 << 2;
const int kModsSuper = 1 << 3;
const int kModsCapsLock = 1 << 4;
const int kModsNumLock = 1 << 5;

// Focus
const int kFocusGained = 0;
const int kFocusLost = 1;

// Scroll viewport tags
const int kScrollViewportTop = 0;
const int kScrollViewportBottom = 1;
const int kScrollViewportDelta = 2;
const int kScrollViewportRow = 3;

// Point tags (point.h)
const int kPointTagActive = 0;
const int kPointTagViewport = 1;
const int kPointTagScreen = 2;
const int kPointTagHistory = 3;

// Formatter formats (types.h) — used by selection_format_*
const int kFormatterFormatPlain = 0;
const int kFormatterFormatVt = 1;
const int kFormatterFormatHtml = 2;

// Selection gesture event kinds (see selection.h)
const int kSelectionGesturePress = 0;
const int kSelectionGestureRelease = 1;
const int kSelectionGestureDrag = 2;
const int kSelectionGestureAutoscrollTick = 3;
const int kSelectionGestureDeepPress = 4;

// Selection gesture event options
const int kSelectionGestureEventOptRef = 0;
const int kSelectionGestureEventOptPosition = 1;
const int kSelectionGestureEventOptRepeatDistance = 2;
const int kSelectionGestureEventOptTimeNs = 3;
const int kSelectionGestureEventOptRepeatIntervalNs = 4;
const int kSelectionGestureEventOptWordBoundaryCodepoints = 5;
const int kSelectionGestureEventOptBehaviors = 6;
const int kSelectionGestureEventOptRectangle = 7;
const int kSelectionGestureEventOptGeometry = 8;
const int kSelectionGestureEventOptViewport = 9;

// Mouse action / button (mouse/event.h)
const int kMouseActionPress = 0;
const int kMouseActionRelease = 1;
const int kMouseActionMotion = 2;
const int kMouseButtonUnknown = 0;
const int kMouseButtonLeft = 1;
const int kMouseButtonRight = 2;
const int kMouseButtonMiddle = 3;

// Native structs

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

/// GhosttyString { ptr, len }
final class GhosttyString extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int len;
}

/// GhosttyStyleColor: tag@0 (int), value@8 (u64 overlay)
final class GhosttyStyleColorNative extends Struct {
  @Int32()
  external int tag;
  @Int32()
  external int _pad;
  @Uint64()
  external int valueBits;

  int get paletteIndex => valueBits & 0xff;
  int get rgbR => valueBits & 0xff;
  int get rgbG => (valueBits >> 8) & 0xff;
  int get rgbB => (valueBits >> 16) & 0xff;
}

/// GhosttyStyle — 72 bytes on x86_64 (verified via matching layout).
final class GhosttyStyleNative extends Struct {
  @Size()
  external int size;
  external GhosttyStyleColorNative fgColor;
  external GhosttyStyleColorNative bgColor;
  external GhosttyStyleColorNative underlineColor;
  @Bool()
  external bool bold;
  @Bool()
  external bool italic;
  @Bool()
  external bool faint;
  @Bool()
  external bool blink;
  @Bool()
  external bool inverse;
  @Bool()
  external bool invisible;
  @Bool()
  external bool strikethrough;
  @Bool()
  external bool overline;
  @Int32()
  external int underline;
}

final class GhosttyTerminalScrollbarNative extends Struct {
  @Uint64()
  external int total;
  @Uint64()
  external int offset;
  @Uint64()
  external int len;
}

final class GhosttyScrollViewportNative extends Struct {
  @Int32()
  external int tag;
  @Int32()
  external int pad;
  @Int64()
  external int value0;
  @Int64()
  external int value1;
}

/// GhosttyPoint — tagged grid coordinate (24 bytes on x86_64).
final class GhosttyPointNative extends Struct {
  @Int32()
  external int tag;
  @Int32()
  external int pad;
  @Uint16()
  external int x;
  @Uint16()
  external int padXy;
  @Uint32()
  external int y;
  @Uint64()
  external int valuePad;
}

/// GhosttyGridRef — untracked cell snapshot (sized struct).
final class GhosttyGridRefNative extends Struct {
  @Size()
  external int size;
  external Pointer<Void> node;
  @Uint16()
  external int x;
  @Uint16()
  external int y;
}

/// GhosttySelection — snapshot range (sized struct).
final class GhosttySelectionNative extends Struct {
  @Size()
  external int size;
  external GhosttyGridRefNative start;
  external GhosttyGridRefNative end;
  @Bool()
  external bool rectangle;
}

/// GhosttySurfacePosition — surface-space pixels.
final class GhosttySurfacePositionNative extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

/// GhosttySelectionGestureGeometry — drag display geometry.
final class GhosttySelectionGestureGeometryNative extends Struct {
  @Uint32()
  external int columns;
  @Uint32()
  external int cellWidth;
  @Uint32()
  external int paddingLeft;
  @Uint32()
  external int screenHeight;
}

/// GhosttyTerminalSelectionFormatOptions (sized struct).
///
/// Layout: size_t + int emit + 2×bool + pad + pointer ≈ 24 bytes (SysV MEMORY).
final class GhosttySelectionFormatOptionsNative extends Struct {
  @Size()
  external int size;
  @Int32()
  external int emit;
  @Bool()
  external bool unwrap;
  @Bool()
  external bool trim;
  external Pointer<GhosttySelectionNative> selection;
}

/// GhosttyMousePosition — surface-space floats for mouse encode.
final class GhosttyMousePositionNative extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

/// GhosttySysImage — decoded RGBA image returned from sys PNG callback.
final class GhosttySysImage extends Struct {
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  external Pointer<Uint8> data;
  @Size()
  external int dataLen;
}

/// Alias used by some call sites.
typedef GhosttySysImageNative = GhosttySysImage;

/// GhosttyAllocator — opaque enough for pass-through (ctx + vtable).
final class GhosttyAllocator extends Struct {
  external Pointer<Void> ctx;
  external Pointer<Void> vtable;
}

/// Alias used by some call sites.
typedef GhosttyAllocatorNative = GhosttyAllocator;

/// GhosttyTerminalProgressReport (sized struct).
final class GhosttyProgressReportNative extends Struct {
  @Size()
  external int size;
  @Int32()
  external int state;
  @Int8()
  external int progress;
}

/// GhosttyTerminalDesktopNotification (sized struct).
final class GhosttyDesktopNotificationNative extends Struct {
  @Size()
  external int size;
  external GhosttyString title;
  external GhosttyString body;
}

/// One MIME representation in a clipboard write (borrowed for callback duration).
final class GhosttyClipboardContentNative extends Struct {
  external GhosttyString mime;
  external GhosttyString data;
}

/// GhosttyClipboardWrite — sized atomic clipboard write request.
final class GhosttyClipboardWriteNative extends Struct {
  @Size()
  external int size;
  @Int32()
  external int location;
  external Pointer<GhosttyClipboardContentNative> contents;
  @Size()
  external int contentsLen;
}

/// Clipboard write result (c_int enum; OSC 52 ignores it, still return honestly).
const int kClipboardWriteResultSuccess = 0;
const int kClipboardWriteResultDenied = 1;
const int kClipboardWriteResultUnsupported = 2;
const int kClipboardWriteResultBusy = 3;
const int kClipboardWriteResultInvalidData = 4;
const int kClipboardWriteResultIoError = 5;

const int kClipboardLocationStandard = 0;
const int kClipboardLocationSelection = 1;
const int kClipboardLocationPrimary = 2;

/// GhosttyKittyGraphicsPlacementRenderInfo — sized render geometry helper.
final class GhosttyKittyPlacementRenderInfoNative extends Struct {
  @Size()
  external int size;
  @Uint32()
  external int pixelWidth;
  @Uint32()
  external int pixelHeight;
  @Uint32()
  external int gridCols;
  @Uint32()
  external int gridRows;
  @Int32()
  external int viewportCol;
  @Int32()
  external int viewportRow;
  @Bool()
  external bool viewportVisible;
  @Uint32()
  external int sourceX;
  @Uint32()
  external int sourceY;
  @Uint32()
  external int sourceWidth;
  @Uint32()
  external int sourceHeight;
}

/// GhosttyFormatterScreenExtra (sized).
final class GhosttyFormatterScreenExtraNative extends Struct {
  @Size()
  external int size;
  @Bool()
  external bool cursor;
  @Bool()
  external bool style;
  @Bool()
  external bool hyperlink;
  @Bool()
  external bool protection;
  @Bool()
  external bool kittyKeyboard;
  @Bool()
  external bool charsets;
}

/// GhosttyFormatterTerminalExtra (sized).
final class GhosttyFormatterTerminalExtraNative extends Struct {
  @Size()
  external int size;
  @Bool()
  external bool palette;
  @Bool()
  external bool modes;
  @Bool()
  external bool scrollingRegion;
  @Bool()
  external bool tabstops;
  @Bool()
  external bool pwd;
  @Bool()
  external bool keyboard;
  external GhosttyFormatterScreenExtraNative screen;
}

/// GhosttyFormatterTerminalOptions (sized, by-value for formatter_terminal_new).
final class GhosttyFormatterTerminalOptionsNative extends Struct {
  @Size()
  external int size;
  @Int32()
  external int emit;
  @Bool()
  external bool unwrap;
  @Bool()
  external bool trim;
  external GhosttyFormatterTerminalExtraNative extra;
  external Pointer<GhosttySelectionNative> selection;
}


// --- Function typedefs ------------------------------------------------------

typedef _I32_AllocOut = Int32 Function(Pointer<Void> alloc, Pointer<Pointer<Void>> out);
typedef _I32_AllocOutDart = int Function(Pointer<Void> alloc, Pointer<Pointer<Void>> out);
typedef _TerminalNew = Int32 Function(
  Pointer<Void> alloc, Pointer<Pointer<Void>> out, Uint16 cols, Uint16 rows);
typedef _TerminalNewDart = int Function(
  Pointer<Void> alloc, Pointer<Pointer<Void>> out, int cols, int rows);
typedef _Void_Ptr = Void Function(Pointer<Void> p);
typedef _Void_PtrDart = void Function(Pointer<Void> p);
typedef _VtWrite = Void Function(Pointer<Void> term, Pointer<Uint8> data, Size len);
typedef _VtWriteDart = void Function(Pointer<Void> term, Pointer<Uint8> data, int len);
typedef _Resize = Int32 Function(Pointer<Void> term, Uint16 c, Uint16 r, Uint32 cw, Uint32 ch);
typedef _ResizeDart = int Function(Pointer<Void> term, int c, int r, int cw, int ch);
typedef _TermSet = Int32 Function(Pointer<Void> term, Int32 opt, Pointer<Void> val);
typedef _TermSetDart = int Function(Pointer<Void> term, int opt, Pointer<Void> val);
typedef _TermGet = Int32 Function(Pointer<Void> term, Int32 data, Pointer<Void> out);
typedef _TermGetDart = int Function(Pointer<Void> term, int data, Pointer<Void> out);
typedef _RenderUpdate = Int32 Function(Pointer<Void> state, Pointer<Void> term);
typedef _RenderUpdateDart = int Function(Pointer<Void> state, Pointer<Void> term);
typedef _StateGet = Int32 Function(Pointer<Void> state, Int32 data, Pointer<Void> out);
typedef _StateGetDart = int Function(Pointer<Void> state, int data, Pointer<Void> out);
typedef _StateSet = Int32 Function(Pointer<Void> state, Int32 opt, Pointer<Void> val);
typedef _StateSetDart = int Function(Pointer<Void> state, int opt, Pointer<Void> val);
typedef _Bool_Ptr = Bool Function(Pointer<Void> p);
typedef _Bool_PtrDart = bool Function(Pointer<Void> p);
typedef _RowGet = Int32 Function(Pointer<Void> iter, Int32 data, Pointer<Void> out);
typedef _RowGetDart = int Function(Pointer<Void> iter, int data, Pointer<Void> out);
typedef _RowSet = Int32 Function(Pointer<Void> iter, Int32 opt, Pointer<Void> val);
typedef _RowSetDart = int Function(Pointer<Void> iter, int opt, Pointer<Void> val);
typedef _CellsGet = Int32 Function(Pointer<Void> cells, Int32 data, Pointer<Void> out);
typedef _CellsGetDart = int Function(Pointer<Void> cells, int data, Pointer<Void> out);

typedef _KeyEventSetAction = Void Function(Pointer<Void> e, Int32 a);
typedef _KeyEventSetActionDart = void Function(Pointer<Void> e, int a);
typedef _KeyEventSetKey = Void Function(Pointer<Void> e, Int32 k);
typedef _KeyEventSetKeyDart = void Function(Pointer<Void> e, int k);
typedef _KeyEventSetMods = Void Function(Pointer<Void> e, Uint16 m);
typedef _KeyEventSetModsDart = void Function(Pointer<Void> e, int m);
typedef _KeyEventSetUtf8 = Void Function(Pointer<Void> e, Pointer<Uint8> p, Size n);
typedef _KeyEventSetUtf8Dart = void Function(Pointer<Void> e, Pointer<Uint8> p, int n);

typedef _EncoderSetoptTerm = Void Function(Pointer<Void> enc, Pointer<Void> term);
typedef _EncoderSetoptTermDart = void Function(Pointer<Void> enc, Pointer<Void> term);
typedef _EncoderEncode = Int32 Function(
  Pointer<Void> enc, Pointer<Void> event, Pointer<Uint8> buf, Size len, Pointer<Size> out);
typedef _EncoderEncodeDart = int Function(
  Pointer<Void> enc, Pointer<Void> event, Pointer<Uint8> buf, int len, Pointer<Size> out);

typedef _FocusEncode = Int32 Function(Int32 event, Pointer<Uint8> buf, Size len, Pointer<Size> out);
typedef _FocusEncodeDart = int Function(int event, Pointer<Uint8> buf, int len, Pointer<Size> out);

typedef _PasteSafe = Bool Function(Pointer<Uint8> data, Size len);
typedef _PasteSafeDart = bool Function(Pointer<Uint8> data, int len);
typedef _PasteEncode = Int32 Function(
  Pointer<Uint8> data, Size dataLen, Bool bracketed, Pointer<Uint8> buf, Size bufLen, Pointer<Size> out);
typedef _PasteEncodeDart = int Function(
  Pointer<Uint8> data, int dataLen, bool bracketed, Pointer<Uint8> buf, int bufLen, Pointer<Size> out);

// C API takes GhosttyTerminalScrollViewport by value.
typedef _ScrollViewport = Void Function(
    Pointer<Void> term, GhosttyScrollViewportNative beh);
typedef _ScrollViewportDart = void Function(
    Pointer<Void> term, GhosttyScrollViewportNative beh);

// GhosttyPoint is taken by value (same as ScrollViewport); Dart FFI lowers
// MEMORY-class aggregates correctly when the Struct is the parameter type.
typedef _GridRef = Int32 Function(
    Pointer<Void> term, GhosttyPointNative point, Pointer<GhosttyGridRefNative> out);
typedef _GridRefDart = int Function(
    Pointer<Void> term, GhosttyPointNative point, Pointer<GhosttyGridRefNative> out);

typedef _SelGestureNew = Int32 Function(Pointer<Void> alloc, Pointer<Pointer<Void>> out);
typedef _SelGestureNewDart = int Function(Pointer<Void> alloc, Pointer<Pointer<Void>> out);
typedef _SelGestureFree = Void Function(Pointer<Void> g, Pointer<Void> term);
typedef _SelGestureFreeDart = void Function(Pointer<Void> g, Pointer<Void> term);
typedef _SelGestureEventNew = Int32 Function(
    Pointer<Void> alloc, Pointer<Pointer<Void>> out, Int32 type);
typedef _SelGestureEventNewDart = int Function(
    Pointer<Void> alloc, Pointer<Pointer<Void>> out, int type);
typedef _SelGestureEvent = Int32 Function(
    Pointer<Void> g, Pointer<Void> term, Pointer<Void> ev, Pointer<GhosttySelectionNative> outSel);
typedef _SelGestureEventDart = int Function(
    Pointer<Void> g, Pointer<Void> term, Pointer<Void> ev, Pointer<GhosttySelectionNative> outSel);

// Format options are MEMORY-class (24B); pass pointer under SysV.
typedef _SelectionFormatBuf = Int32 Function(
    Pointer<Void> term,
    Pointer<GhosttySelectionFormatOptionsNative> opts,
    Pointer<Uint8> buf,
    Size cap,
    Pointer<Size> out);
typedef _SelectionFormatBufDart = int Function(
    Pointer<Void> term,
    Pointer<GhosttySelectionFormatOptionsNative> opts,
    Pointer<Uint8> buf,
    int cap,
    Pointer<Size> out);

typedef _MouseEventSetAction = Void Function(Pointer<Void> e, Int32 a);
typedef _MouseEventSetActionDart = void Function(Pointer<Void> e, int a);
typedef _MouseEventSetButton = Void Function(Pointer<Void> e, Int32 b);
typedef _MouseEventSetButtonDart = void Function(Pointer<Void> e, int b);
typedef _MouseEventSetMods = Void Function(Pointer<Void> e, Uint16 m);
typedef _MouseEventSetModsDart = void Function(Pointer<Void> e, int m);
typedef _MouseEventSetPosition = Void Function(
    Pointer<Void> e, GhosttyMousePositionNative pos);
typedef _MouseEventSetPositionDart = void Function(
    Pointer<Void> e, GhosttyMousePositionNative pos);
typedef _MouseEncode = Int32 Function(
    Pointer<Void> enc, Pointer<Void> event, Pointer<Uint8> buf, Size len, Pointer<Size> out);
typedef _MouseEncodeDart = int Function(
    Pointer<Void> enc, Pointer<Void> event, Pointer<Uint8> buf, int len, Pointer<Size> out);

// Effect callbacks (NativeCallable targets)
typedef WritePtyNative = Void Function(
  Pointer<Void> term, Pointer<Void> userdata, Pointer<Uint8> data, Size len);
typedef BellNative = Void Function(Pointer<Void> term, Pointer<Void> userdata);
typedef TitleChangedNative = Void Function(Pointer<Void> term, Pointer<Void> userdata);
typedef PwdChangedNative = Void Function(Pointer<Void> term, Pointer<Void> userdata);
typedef ProgressReportNative = Void Function(
  Pointer<Void> term,
  Pointer<Void> userdata,
  Pointer<GhosttyProgressReportNative> report,
);
typedef DesktopNotificationNative = Void Function(
  Pointer<Void> term,
  Pointer<Void> userdata,
  Pointer<GhosttyDesktopNotificationNative> notification,
);
/// Returns [GhosttyClipboardWriteResult] (c_int).
typedef ClipboardWriteNative = Int32 Function(
  Pointer<Void> term,
  Pointer<Void> userdata,
  Pointer<GhosttyClipboardWriteNative> write,
);

// Sys PNG decode callback (sys.h)
typedef DecodePngNative = Bool Function(
  Pointer<Void> userdata,
  Pointer<GhosttyAllocator> allocator,
  Pointer<Uint8> data,
  Size dataLen,
  Pointer<GhosttySysImage> out,
);

// Allocator helpers
typedef _GhosttyAlloc = Pointer<Uint8> Function(
    Pointer<GhosttyAllocator> allocator, Size len);
typedef _GhosttyAllocDart = Pointer<Uint8> Function(
    Pointer<GhosttyAllocator> allocator, int len);
typedef _GhosttyFree = Void Function(
    Pointer<GhosttyAllocator> allocator, Pointer<Uint8> ptr, Size len);
typedef _GhosttyFreeDart = void Function(
    Pointer<GhosttyAllocator> allocator, Pointer<Uint8> ptr, int len);

typedef _SysSet = Int32 Function(Int32 option, Pointer<Void> value);
typedef _SysSetDart = int Function(int option, Pointer<Void> value);

typedef _CompressActivity = Int32 Function(
    Pointer<Void> term, Pointer<Uint64> out);
typedef _CompressActivityDart = int Function(
    Pointer<Void> term, Pointer<Uint64> out);
typedef _Compress = Int32 Function(
    Pointer<Void> term, Int32 mode, Pointer<Int32> out);
typedef _CompressDart = int Function(
    Pointer<Void> term, int mode, Pointer<Int32> out);

// Kitty graphics
typedef _KittyGraphicsGet = Int32 Function(
    Pointer<Void> graphics, Int32 data, Pointer<Void> out);
typedef _KittyGraphicsGetDart = int Function(
    Pointer<Void> graphics, int data, Pointer<Void> out);
typedef _KittyImageLookup = Pointer<Void> Function(
    Pointer<Void> graphics, Uint32 imageId);
typedef _KittyImageLookupDart = Pointer<Void> Function(
    Pointer<Void> graphics, int imageId);
typedef _KittyImageGet = Int32 Function(
    Pointer<Void> image, Int32 data, Pointer<Void> out);
typedef _KittyImageGetDart = int Function(
    Pointer<Void> image, int data, Pointer<Void> out);
typedef _KittyPlacementIterNew = Int32 Function(
    Pointer<GhosttyAllocator> alloc, Pointer<Pointer<Void>> out);
typedef _KittyPlacementIterNewDart = int Function(
    Pointer<GhosttyAllocator> alloc, Pointer<Pointer<Void>> out);
typedef _KittyPlacementIterSet = Int32 Function(
    Pointer<Void> iter, Int32 option, Pointer<Void> value);
typedef _KittyPlacementIterSetDart = int Function(
    Pointer<Void> iter, int option, Pointer<Void> value);
typedef _KittyPlacementGet = Int32 Function(
    Pointer<Void> iter, Int32 data, Pointer<Void> out);
typedef _KittyPlacementGetDart = int Function(
    Pointer<Void> iter, int data, Pointer<Void> out);
typedef _KittyPlacementPixelSize = Int32 Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<Uint32> outW,
    Pointer<Uint32> outH);
typedef _KittyPlacementPixelSizeDart = int Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<Uint32> outW,
    Pointer<Uint32> outH);
typedef _KittyPlacementGridSize = Int32 Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<Uint32> outCols,
    Pointer<Uint32> outRows);
typedef _KittyPlacementGridSizeDart = int Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<Uint32> outCols,
    Pointer<Uint32> outRows);
typedef _KittyPlacementViewportPos = Int32 Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<Int32> outCol,
    Pointer<Int32> outRow);
typedef _KittyPlacementViewportPosDart = int Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<Int32> outCol,
    Pointer<Int32> outRow);
typedef _KittyPlacementRenderInfo = Int32 Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<GhosttyKittyPlacementRenderInfoNative> out);
typedef _KittyPlacementRenderInfoDart = int Function(
    Pointer<Void> iter,
    Pointer<Void> image,
    Pointer<Void> terminal,
    Pointer<GhosttyKittyPlacementRenderInfoNative> out);

typedef _SnapshotEncodeBuf = Int32 Function(
    Pointer<Void> term, Pointer<Uint8> buf, Size cap, Pointer<Size> out);
typedef _SnapshotEncodeBufDart = int Function(
    Pointer<Void> term, Pointer<Uint8> buf, int cap, Pointer<Size> out);
typedef _SnapshotEncodeAlloc = Int32 Function(
    Pointer<Void> term,
    Pointer<GhosttyAllocator> alloc,
    Pointer<Pointer<Uint8>> outPtr,
    Pointer<Size> outLen);
typedef _SnapshotEncodeAllocDart = int Function(
    Pointer<Void> term,
    Pointer<GhosttyAllocator> alloc,
    Pointer<Pointer<Uint8>> outPtr,
    Pointer<Size> outLen);

// formatter_terminal_new takes options by value (MEMORY-class on SysV).
typedef _FormatterTerminalNew = Int32 Function(
    Pointer<GhosttyAllocator> alloc,
    Pointer<Pointer<Void>> out,
    Pointer<Void> terminal,
    GhosttyFormatterTerminalOptionsNative options);
typedef _FormatterTerminalNewDart = int Function(
    Pointer<GhosttyAllocator> alloc,
    Pointer<Pointer<Void>> out,
    Pointer<Void> terminal,
    GhosttyFormatterTerminalOptionsNative options);
typedef _FormatterFormatBuf = Int32 Function(
    Pointer<Void> formatter, Pointer<Uint8> buf, Size cap, Pointer<Size> out);
typedef _FormatterFormatBufDart = int Function(
    Pointer<Void> formatter, Pointer<Uint8> buf, int cap, Pointer<Size> out);
typedef _FormatterFormatAlloc = Int32 Function(
    Pointer<Void> formatter,
    Pointer<GhosttyAllocator> alloc,
    Pointer<Pointer<Uint8>> outPtr,
    Pointer<Size> outLen);
typedef _FormatterFormatAllocDart = int Function(
    Pointer<Void> formatter,
    Pointer<GhosttyAllocator> alloc,
    Pointer<Pointer<Uint8>> outPtr,
    Pointer<Size> outLen);

/// Low-level bindings to `libghostty-vt`.
class GhosttyVtNative {
  GhosttyVtNative._(this._lib)
      : terminalNew = _lib.lookupFunction<_TerminalNew, _TerminalNewDart>(
            'ghostty_terminal_new'),
        terminalFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_terminal_free'),
        terminalVtWrite = _lib.lookupFunction<_VtWrite, _VtWriteDart>(
            'ghostty_terminal_vt_write'),
        terminalResize = _lib.lookupFunction<_Resize, _ResizeDart>(
            'ghostty_terminal_resize'),
        terminalSet = _lib.lookupFunction<_TermSet, _TermSetDart>(
            'ghostty_terminal_set'),
        terminalGet = _lib.lookupFunction<_TermGet, _TermGetDart>(
            'ghostty_terminal_get'),
        terminalScrollViewport =
            _lib.lookupFunction<_ScrollViewport, _ScrollViewportDart>(
                'ghostty_terminal_scroll_viewport'),
        terminalGridRef = _lib.lookupFunction<_GridRef, _GridRefDart>(
            'ghostty_terminal_grid_ref'),
        renderStateNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_render_state_new'),
        renderStateFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_render_state_free'),
        renderStateUpdate =
            _lib.lookupFunction<_RenderUpdate, _RenderUpdateDart>(
                'ghostty_render_state_update'),
        renderStateGet = _lib.lookupFunction<_StateGet, _StateGetDart>(
            'ghostty_render_state_get'),
        renderStateSet = _lib.lookupFunction<_StateSet, _StateSetDart>(
            'ghostty_render_state_set'),
        rowIteratorNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_render_state_row_iterator_new'),
        rowIteratorFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_render_state_row_iterator_free'),
        rowIteratorNext = _lib.lookupFunction<_Bool_Ptr, _Bool_PtrDart>(
            'ghostty_render_state_row_iterator_next'),
        rowGet = _lib.lookupFunction<_RowGet, _RowGetDart>(
            'ghostty_render_state_row_get'),
        rowSet = _lib.lookupFunction<_RowSet, _RowSetDart>(
            'ghostty_render_state_row_set'),
        rowCellsNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_render_state_row_cells_new'),
        rowCellsFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_render_state_row_cells_free'),
        rowCellsNext = _lib.lookupFunction<_Bool_Ptr, _Bool_PtrDart>(
            'ghostty_render_state_row_cells_next'),
        rowCellsGet = _lib.lookupFunction<_CellsGet, _CellsGetDart>(
            'ghostty_render_state_row_cells_get'),
        keyEncoderNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_key_encoder_new'),
        keyEncoderFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_key_encoder_free'),
        keyEncoderSetoptFromTerminal =
            _lib.lookupFunction<_EncoderSetoptTerm, _EncoderSetoptTermDart>(
                'ghostty_key_encoder_setopt_from_terminal'),
        keyEncoderEncode =
            _lib.lookupFunction<_EncoderEncode, _EncoderEncodeDart>(
                'ghostty_key_encoder_encode'),
        keyEventNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_key_event_new'),
        keyEventFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_key_event_free'),
        keyEventSetAction =
            _lib.lookupFunction<_KeyEventSetAction, _KeyEventSetActionDart>(
                'ghostty_key_event_set_action'),
        keyEventSetKey =
            _lib.lookupFunction<_KeyEventSetKey, _KeyEventSetKeyDart>(
                'ghostty_key_event_set_key'),
        keyEventSetMods =
            _lib.lookupFunction<_KeyEventSetMods, _KeyEventSetModsDart>(
                'ghostty_key_event_set_mods'),
        keyEventSetUtf8 =
            _lib.lookupFunction<_KeyEventSetUtf8, _KeyEventSetUtf8Dart>(
                'ghostty_key_event_set_utf8'),
        focusEncode = _lib.lookupFunction<_FocusEncode, _FocusEncodeDart>(
            'ghostty_focus_encode'),
        pasteIsSafe = _lib.lookupFunction<_PasteSafe, _PasteSafeDart>(
            'ghostty_paste_is_safe'),
        pasteEncode = _lib.lookupFunction<_PasteEncode, _PasteEncodeDart>(
            'ghostty_paste_encode'),
        mouseEncoderNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_mouse_encoder_new'),
        mouseEncoderFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_mouse_encoder_free'),
        mouseEncoderSetoptFromTerminal =
            _lib.lookupFunction<_EncoderSetoptTerm, _EncoderSetoptTermDart>(
                'ghostty_mouse_encoder_setopt_from_terminal'),
        mouseEncoderEncode =
            _lib.lookupFunction<_MouseEncode, _MouseEncodeDart>(
                'ghostty_mouse_encoder_encode'),
        mouseEventNew = _lib.lookupFunction<_I32_AllocOut, _I32_AllocOutDart>(
            'ghostty_mouse_event_new'),
        mouseEventFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_mouse_event_free'),
        mouseEventSetAction =
            _lib.lookupFunction<_MouseEventSetAction, _MouseEventSetActionDart>(
                'ghostty_mouse_event_set_action'),
        mouseEventSetButton =
            _lib.lookupFunction<_MouseEventSetButton, _MouseEventSetButtonDart>(
                'ghostty_mouse_event_set_button'),
        mouseEventClearButton = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_mouse_event_clear_button'),
        mouseEventSetMods =
            _lib.lookupFunction<_MouseEventSetMods, _MouseEventSetModsDart>(
                'ghostty_mouse_event_set_mods'),
        mouseEventSetPosition = _lib.lookupFunction<_MouseEventSetPosition,
            _MouseEventSetPositionDart>('ghostty_mouse_event_set_position'),
        selectionGestureNew =
            _lib.lookupFunction<_SelGestureNew, _SelGestureNewDart>(
                'ghostty_selection_gesture_new'),
        selectionGestureFree =
            _lib.lookupFunction<_SelGestureFree, _SelGestureFreeDart>(
                'ghostty_selection_gesture_free'),
        selectionGestureReset =
            _lib.lookupFunction<_SelGestureFree, _SelGestureFreeDart>(
                'ghostty_selection_gesture_reset'),
        selectionGestureEventNew =
            _lib.lookupFunction<_SelGestureEventNew, _SelGestureEventNewDart>(
                'ghostty_selection_gesture_event_new'),
        selectionGestureEventFree =
            _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
                'ghostty_selection_gesture_event_free'),
        selectionGestureEventSet =
            _lib.lookupFunction<_TermSet, _TermSetDart>(
                'ghostty_selection_gesture_event_set'),
        selectionGestureEvent =
            _lib.lookupFunction<_SelGestureEvent, _SelGestureEventDart>(
                'ghostty_selection_gesture_event'),
        selectionFormatBuf = _lib
            .lookupFunction<_SelectionFormatBuf, _SelectionFormatBufDart>(
                'ghostty_terminal_selection_format_buf'),
        ghosttyAlloc =
            _lib.lookupFunction<_GhosttyAlloc, _GhosttyAllocDart>('ghostty_alloc'),
        ghosttyFree =
            _lib.lookupFunction<_GhosttyFree, _GhosttyFreeDart>('ghostty_free'),
        sysSet = _lib.lookupFunction<_SysSet, _SysSetDart>('ghostty_sys_set'),
        terminalCompress =
            _lib.lookupFunction<_Compress, _CompressDart>('ghostty_terminal_compress'),
        terminalCompressionActivity = _lib.lookupFunction<_CompressActivity,
            _CompressActivityDart>('ghostty_terminal_compression_activity'),
        kittyGraphicsGet = _lib.lookupFunction<_KittyGraphicsGet,
            _KittyGraphicsGetDart>('ghostty_kitty_graphics_get'),
        kittyGraphicsImage = _lib.lookupFunction<_KittyImageLookup,
            _KittyImageLookupDart>('ghostty_kitty_graphics_image'),
        kittyGraphicsImageGet = _lib.lookupFunction<_KittyImageGet,
            _KittyImageGetDart>('ghostty_kitty_graphics_image_get'),
        kittyPlacementIteratorNew = _lib.lookupFunction<_KittyPlacementIterNew,
                _KittyPlacementIterNewDart>(
            'ghostty_kitty_graphics_placement_iterator_new'),
        kittyPlacementIteratorFree =
            _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
                'ghostty_kitty_graphics_placement_iterator_free'),
        kittyPlacementIteratorSet = _lib.lookupFunction<_KittyPlacementIterSet,
                _KittyPlacementIterSetDart>(
            'ghostty_kitty_graphics_placement_iterator_set'),
        kittyPlacementNext = _lib.lookupFunction<_Bool_Ptr, _Bool_PtrDart>(
            'ghostty_kitty_graphics_placement_next'),
        kittyPlacementGet = _lib.lookupFunction<_KittyPlacementGet,
            _KittyPlacementGetDart>('ghostty_kitty_graphics_placement_get'),
        kittyPlacementPixelSize = _lib.lookupFunction<_KittyPlacementPixelSize,
                _KittyPlacementPixelSizeDart>(
            'ghostty_kitty_graphics_placement_pixel_size'),
        kittyPlacementGridSize = _lib.lookupFunction<_KittyPlacementGridSize,
                _KittyPlacementGridSizeDart>(
            'ghostty_kitty_graphics_placement_grid_size'),
        kittyPlacementViewportPos = _lib.lookupFunction<_KittyPlacementViewportPos,
                _KittyPlacementViewportPosDart>(
            'ghostty_kitty_graphics_placement_viewport_pos'),
        kittyPlacementRenderInfo = _lib.lookupFunction<_KittyPlacementRenderInfo,
                _KittyPlacementRenderInfoDart>(
            'ghostty_kitty_graphics_placement_render_info'),
        snapshotEncodeBuf = _lib.lookupFunction<_SnapshotEncodeBuf,
            _SnapshotEncodeBufDart>('ghostty_snapshot_encode_buf'),
        snapshotEncodeAlloc = _lib.lookupFunction<_SnapshotEncodeAlloc,
            _SnapshotEncodeAllocDart>('ghostty_snapshot_encode_alloc'),
        formatterTerminalNew = _lib.lookupFunction<_FormatterTerminalNew,
            _FormatterTerminalNewDart>('ghostty_formatter_terminal_new'),
        formatterFormatBuf = _lib.lookupFunction<_FormatterFormatBuf,
            _FormatterFormatBufDart>('ghostty_formatter_format_buf'),
        formatterFormatAlloc = _lib.lookupFunction<_FormatterFormatAlloc,
            _FormatterFormatAllocDart>('ghostty_formatter_format_alloc'),
        formatterFree = _lib.lookupFunction<_Void_Ptr, _Void_PtrDart>(
            'ghostty_formatter_free'),
        colorPaletteDefault = _lib.lookupFunction<
            Void Function(Pointer<GhosttyColorRgb> palette),
            void Function(Pointer<GhosttyColorRgb> palette)>(
          'ghostty_color_palette_default',
        );

  final DynamicLibrary _lib;

  /// Fill a 256-entry [GhosttyColorRgb] array with Ghostty's default palette.
  final void Function(Pointer<GhosttyColorRgb> palette) colorPaletteDefault;

  final _TerminalNewDart terminalNew;
  final _Void_PtrDart terminalFree;
  final _VtWriteDart terminalVtWrite;
  final _ResizeDart terminalResize;
  final _TermSetDart terminalSet;
  final _TermGetDart terminalGet;
  final _ScrollViewportDart terminalScrollViewport;
  final _GridRefDart terminalGridRef;
  final _I32_AllocOutDart renderStateNew;
  final _Void_PtrDart renderStateFree;
  final _RenderUpdateDart renderStateUpdate;
  final _StateGetDart renderStateGet;
  final _StateSetDart renderStateSet;
  final _I32_AllocOutDart rowIteratorNew;
  final _Void_PtrDart rowIteratorFree;
  final _Bool_PtrDart rowIteratorNext;
  final _RowGetDart rowGet;
  final _RowSetDart rowSet;
  final _I32_AllocOutDart rowCellsNew;
  final _Void_PtrDart rowCellsFree;
  final _Bool_PtrDart rowCellsNext;
  final _CellsGetDart rowCellsGet;
  final _I32_AllocOutDart keyEncoderNew;
  final _Void_PtrDart keyEncoderFree;
  final _EncoderSetoptTermDart keyEncoderSetoptFromTerminal;
  final _EncoderEncodeDart keyEncoderEncode;
  final _I32_AllocOutDart keyEventNew;
  final _Void_PtrDart keyEventFree;
  final _KeyEventSetActionDart keyEventSetAction;
  final _KeyEventSetKeyDart keyEventSetKey;
  final _KeyEventSetModsDart keyEventSetMods;
  final _KeyEventSetUtf8Dart keyEventSetUtf8;
  final _FocusEncodeDart focusEncode;
  final _PasteSafeDart pasteIsSafe;
  final _PasteEncodeDart pasteEncode;
  final _I32_AllocOutDart mouseEncoderNew;
  final _Void_PtrDart mouseEncoderFree;
  final _EncoderSetoptTermDart mouseEncoderSetoptFromTerminal;
  final _MouseEncodeDart mouseEncoderEncode;
  final _I32_AllocOutDart mouseEventNew;
  final _Void_PtrDart mouseEventFree;
  final _MouseEventSetActionDart mouseEventSetAction;
  final _MouseEventSetButtonDart mouseEventSetButton;
  final _Void_PtrDart mouseEventClearButton;
  final _MouseEventSetModsDart mouseEventSetMods;
  final _MouseEventSetPositionDart mouseEventSetPosition;
  final _SelGestureNewDart selectionGestureNew;
  final _SelGestureFreeDart selectionGestureFree;
  final _SelGestureFreeDart selectionGestureReset;
  final _SelGestureEventNewDart selectionGestureEventNew;
  final _Void_PtrDart selectionGestureEventFree;
  final _TermSetDart selectionGestureEventSet;
  final _SelGestureEventDart selectionGestureEvent;
  final _SelectionFormatBufDart selectionFormatBuf;

  // Allocator / sys / compression
  final _GhosttyAllocDart ghosttyAlloc;
  final _GhosttyFreeDart ghosttyFree;
  final _SysSetDart sysSet;
  final _CompressDart terminalCompress;
  final _CompressActivityDart terminalCompressionActivity;

  // Kitty graphics
  final _KittyGraphicsGetDart kittyGraphicsGet;
  final _KittyImageLookupDart kittyGraphicsImage;
  final _KittyImageGetDart kittyGraphicsImageGet;
  final _KittyPlacementIterNewDart kittyPlacementIteratorNew;
  final _Void_PtrDart kittyPlacementIteratorFree;
  final _KittyPlacementIterSetDart kittyPlacementIteratorSet;
  final _Bool_PtrDart kittyPlacementNext;
  final _KittyPlacementGetDart kittyPlacementGet;
  final _KittyPlacementPixelSizeDart kittyPlacementPixelSize;
  final _KittyPlacementGridSizeDart kittyPlacementGridSize;
  final _KittyPlacementViewportPosDart kittyPlacementViewportPos;
  final _KittyPlacementRenderInfoDart kittyPlacementRenderInfo;

  // Snapshot / formatter
  final _SnapshotEncodeBufDart snapshotEncodeBuf;
  final _SnapshotEncodeAllocDart snapshotEncodeAlloc;
  final _FormatterTerminalNewDart formatterTerminalNew;
  final _FormatterFormatBufDart formatterFormatBuf;
  final _FormatterFormatAllocDart formatterFormatAlloc;
  final _Void_PtrDart formatterFree;

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
    for (final c in ['$base/lib/libghostty-vt.so', '$base/libghostty-vt.so']) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}

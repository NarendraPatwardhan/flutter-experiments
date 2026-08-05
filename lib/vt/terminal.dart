// Ghostty terminal ownership + effect queues (G2 stream plane + G4 chrome).

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'frame.dart';
import 'graphics.dart';
import 'render.dart';
import 'theme.dart';

export 'graphics.dart'
    show
        VtImageLayer,
        VtPaintImage,
        collectImageLayers,
        snapshotKittyGraphics,
        installPngDecoderOnce;

/// Owns a [GhosttyTerminal] + optional render iterators, and queues effects
/// fired during [write] (WRITE_PTY, bell, title, pwd, progress, notifications).
///
/// Not thread-safe — call from one isolate. Effect callbacks enqueue only;
/// drain with [takePtyOutput] / [takeChromeEvents] after each write batch.
class VtTerminal {
  VtTerminal._({
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

  final List<Uint8List> _ptyOut = <Uint8List>[];
  final List<VtChromeEvent> _chrome = <VtChromeEvent>[];

  NativeCallable<WritePtyNative>? _writePtyCall;
  NativeCallable<BellNative>? _bellCall;
  NativeCallable<TitleChangedNative>? _titleCall;
  NativeCallable<PwdChangedNative>? _pwdCall;
  NativeCallable<ProgressReportNative>? _progressCall;
  NativeCallable<DesktopNotificationNative>? _notifyCall;
  NativeCallable<ClipboardWriteNative>? _clipboardCall;

  /// Opaque Ghostty terminal handle for encoder / render APIs.
  Pointer<Void> get handle => _terminal;

  Pointer<Void> get renderState => _renderState;
  Pointer<Void> get rowIter => _rowIter;
  Pointer<Void> get cells => _cells;

  GhosttyVtNative get native => _native;

  bool get isOpen => !_closed;

  /// Open libghostty-vt and create a terminal of [cols]×[rows].
  ///
  /// Installs default theme colors, Kitty graphics storage, PNG decoder,
  /// and effect callbacks.
  factory VtTerminal.open(int cols, int rows, [String? libPath]) {
    if (cols < 1 || rows < 1) {
      throw ArgumentError('cols and rows must be >= 1');
    }
    final native = GhosttyVtNative.open(libPath);
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

      final term = VtTerminal._(
        native: native,
        terminal: terminal,
        renderState: renderState,
        rowIter: rowIter,
        cells: cells,
        cols: cols,
        rows: rows,
      );
      try {
        // Process-global PNG decoder + per-terminal Kitty storage + effects.
        installPngDecoderOnce(native);
        term.enableKittyGraphics();
        term.setDefaultTheme();
        term.installEffects();
        return term;
      } catch (_) {
        term.close();
        rethrow;
      }
    } finally {
      freePtr(termOut);
      freePtr(rsOut);
      freePtr(rowOut);
      freePtr(cellsOut);
    }
  }

  /// Apply default FG / BG / cursor / 256-color palette from [VtTheme].
  void setDefaultTheme({
    Color fg = VtTheme.foreground,
    Color bg = VtTheme.background,
    Color cursor = VtTheme.cursor,
  }) {
    _ensureOpen();
    final bgPtr = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final fgPtr = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    final curPtr = mallocBytes<GhosttyColorRgb>(1, sizeOf<GhosttyColorRgb>());
    // GhosttyColorRgb is 3 bytes; array of 256 is 768 bytes (no padding on packed rgb).
    final palette = mallocBytes<GhosttyColorRgb>(256, sizeOf<GhosttyColorRgb>());
    try {
      bgPtr.ref
        ..r = bg.red
        ..g = bg.green
        ..b = bg.blue;
      fgPtr.ref
        ..r = fg.red
        ..g = fg.green
        ..b = fg.blue;
      curPtr.ref
        ..r = cursor.red
        ..g = cursor.green
        ..b = cursor.blue;
      _check(_native.terminalSet(
        _terminal,
        kTerminalOptColorBackground,
        bgPtr.cast(),
      ));
      _check(_native.terminalSet(
        _terminal,
        kTerminalOptColorForeground,
        fgPtr.cast(),
      ));
      _check(_native.terminalSet(
        _terminal,
        kTerminalOptColorCursor,
        curPtr.cast(),
      ));
      // Default xterm/Ghostty 256-color cube so SGR palette colors are honest.
      _native.colorPaletteDefault(palette);
      _check(_native.terminalSet(
        _terminal,
        kTerminalOptColorPalette,
        palette.cast(),
      ));
    } finally {
      freePtr(bgPtr);
      freePtr(fgPtr);
      freePtr(curPtr);
      freePtr(palette);
    }
  }

  void _check(int rc, [String what = 'terminal_set']) {
    if (rc != kGhosttySuccess) {
      throw StateError('libghostty-vt $what failed: $rc');
    }
  }

  /// Enable Kitty graphics storage (64 MiB default).
  void enableKittyGraphics({int limitBytes = 64 * 1024 * 1024}) {
    _ensureOpen();
    if (limitBytes <= 0) {
      throw ArgumentError.value(limitBytes, 'limitBytes', 'must be > 0');
    }
    final lim = mallocBytes<Uint64>(1, sizeOf<Uint64>());
    try {
      lim.value = limitBytes;
      _check(_native.terminalSet(
        _terminal,
        kTerminalOptKittyImageStorageLimit,
        lim.cast(),
      ));
    } finally {
      freePtr(lim);
    }
  }

  /// Register WRITE_PTY / BELL / TITLE / PWD / CLIPBOARD / PROGRESS / NOTIFY.
  ///
  /// Idempotent: clears prior callables first. Callbacks only enqueue; they
  /// never re-enter [write] and never touch the platform clipboard.
  void installEffects() {
    _ensureOpen();
    _clearEffectOpts();
    _closeCallables();

    _writePtyCall = NativeCallable<WritePtyNative>.isolateLocal(_onWritePty);
    _bellCall = NativeCallable<BellNative>.isolateLocal(_onBell);
    _titleCall =
        NativeCallable<TitleChangedNative>.isolateLocal(_onTitleChanged);
    _pwdCall = NativeCallable<PwdChangedNative>.isolateLocal(_onPwdChanged);
    _progressCall =
        NativeCallable<ProgressReportNative>.isolateLocal(_onProgress);
    _notifyCall =
        NativeCallable<DesktopNotificationNative>.isolateLocal(_onNotification);
    // Returning callback: must supply exceptionalReturn (io_error).
    _clipboardCall = NativeCallable<ClipboardWriteNative>.isolateLocal(
      _onClipboardWrite,
      exceptionalReturn: kClipboardWriteResultIoError,
    );

    _check(_native.terminalSet(_terminal, kTerminalOptUserdata, nullptr));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptWritePty,
      _writePtyCall!.nativeFunction.cast(),
    ));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptBell,
      _bellCall!.nativeFunction.cast(),
    ));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptTitleChanged,
      _titleCall!.nativeFunction.cast(),
    ));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptPwdChanged,
      _pwdCall!.nativeFunction.cast(),
    ));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptClipboardWrite,
      _clipboardCall!.nativeFunction.cast(),
    ));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptProgressReport,
      _progressCall!.nativeFunction.cast(),
    ));
    _check(_native.terminalSet(
      _terminal,
      kTerminalOptDesktopNotification,
      _notifyCall!.nativeFunction.cast(),
    ));
  }

  void _onWritePty(
    Pointer<Void> term,
    Pointer<Void> userdata,
    Pointer<Uint8> data,
    int len,
  ) {
    if (len <= 0 || data == nullptr) return;
    _ptyOut.add(Uint8List.fromList(data.asTypedList(len)));
  }

  void _onBell(Pointer<Void> term, Pointer<Void> userdata) {
    _chrome.add(const VtChromeBell());
  }

  void _onTitleChanged(Pointer<Void> term, Pointer<Void> userdata) {
    _chrome.add(const VtChromeTitleChanged());
  }

  void _onPwdChanged(Pointer<Void> term, Pointer<Void> userdata) {
    _chrome.add(const VtChromePwdChanged());
  }

  void _onProgress(
    Pointer<Void> term,
    Pointer<Void> userdata,
    Pointer<GhosttyProgressReportNative> report,
  ) {
    if (report == nullptr) return;
    final r = report.ref;
    final state = switch (r.state) {
      kProgressStateRemove => VtProgressState.remove,
      kProgressStateSet => VtProgressState.set,
      kProgressStateError => VtProgressState.error,
      kProgressStateIndeterminate => VtProgressState.indeterminate,
      kProgressStatePause => VtProgressState.pause,
      _ => VtProgressState.remove,
    };
    _chrome.add(VtChromeProgress(state: state, progress: r.progress));
  }

  void _onNotification(
    Pointer<Void> term,
    Pointer<Void> userdata,
    Pointer<GhosttyDesktopNotificationNative> notification,
  ) {
    if (notification == nullptr) return;
    final n = notification.ref;
    final title = _ghosttyString(n.title);
    final body = _ghosttyString(n.body);
    _chrome.add(VtChromeNotification(title: title, body: body));
  }

  /// OSC 52 / OSC 1337 clipboard write — copy payload into chrome queue.
  ///
  /// Must not touch Flutter/platform APIs here (runs inside [write]).
  int _onClipboardWrite(
    Pointer<Void> term,
    Pointer<Void> userdata,
    Pointer<GhosttyClipboardWriteNative> write,
  ) {
    if (write == nullptr) return kClipboardWriteResultInvalidData;
    final w = write.ref;
    final len = w.contentsLen;
    final parts = <({String mime, List<int> data})>[];
    if (len > 0 && w.contents != nullptr) {
      for (var i = 0; i < len; i++) {
        final c = w.contents[i];
        parts.add((
          mime: _ghosttyString(c.mime),
          data: _ghosttyBytes(c.data),
        ));
      }
    }
    _chrome.add(VtChromeClipboardWrite(
      location: w.location,
      parts: parts,
    ));
    return kClipboardWriteResultSuccess;
  }

  static String _ghosttyString(GhosttyString s) {
    if (s.len <= 0 || s.ptr == nullptr) return '';
    return utf8.decode(s.ptr.asTypedList(s.len), allowMalformed: true);
  }

  static List<int> _ghosttyBytes(GhosttyString s) {
    if (s.len <= 0 || s.ptr == nullptr) return const <int>[];
    return Uint8List.fromList(s.ptr.asTypedList(s.len));
  }

  /// Drain queued WRITE_PTY response bytes (for AgentOS send_input).
  List<Uint8List> takePtyOutput() {
    if (_ptyOut.isEmpty) return const <Uint8List>[];
    final out = List<Uint8List>.from(_ptyOut);
    _ptyOut.clear();
    return out;
  }

  /// Drain queued chrome effects (bell / title / pwd / progress / notify).
  List<VtChromeEvent> takeChromeEvents() {
    if (_chrome.isEmpty) return const <VtChromeEvent>[];
    final out = List<VtChromeEvent>.from(_chrome);
    _chrome.clear();
    return out;
  }

  /// Borrowed terminal title as a Dart [String] (empty if unset).
  String get title => _getString(kTerminalDataTitle) ?? '';

  /// Borrowed terminal pwd as a Dart [String] (empty if unset).
  String get pwd => _getString(kTerminalDataPwd) ?? '';

  String? _getString(int dataId) {
    _ensureOpen();
    final out = mallocBytes<GhosttyString>(1, sizeOf<GhosttyString>());
    try {
      final rc = _native.terminalGet(_terminal, dataId, out.cast());
      if (rc != kGhosttySuccess) return null;
      final len = out.ref.len;
      if (len == 0 || out.ref.ptr == nullptr) return '';
      return utf8.decode(
        out.ref.ptr.asTypedList(len),
        allowMalformed: true,
      );
    } finally {
      freePtr(out);
    }
  }

  /// Feed raw bytes into the emulator. Effects may fire and enqueue work.
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

  /// Write guest bytes with LF → CRLF normalization.
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

  /// Scroll viewport. [deltaRows] negative = up into history, positive = down.
  void scrollViewport({int? deltaRows, bool top = false, bool bottom = false}) {
    _ensureOpen();
    final slot = mallocBytes<GhosttyScrollViewportNative>(
      1,
      sizeOf<GhosttyScrollViewportNative>(),
    );
    try {
      if (top) {
        slot.ref
          ..tag = kScrollViewportTop
          ..pad = 0
          ..value0 = 0
          ..value1 = 0;
      } else if (bottom) {
        slot.ref
          ..tag = kScrollViewportBottom
          ..pad = 0
          ..value0 = 0
          ..value1 = 0;
      } else {
        slot.ref
          ..tag = kScrollViewportDelta
          ..pad = 0
          ..value0 = deltaRows ?? 0
          ..value1 = 0;
      }
      _native.terminalScrollViewport(_terminal, slot.ref);
    } finally {
      freePtr(slot);
    }
  }

  /// Project render state into an immutable [VtFrame].
  ///
  /// Pass [previous] for G4 partial dirty merge / clean short-circuit.
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

  /// Snapshot Kitty graphics placements as owned [VtImageLayer]s (RGBA).
  ///
  /// Empty when no images are placed, graphics are disabled, or payloads are
  /// still pending. Does not mutate terminal state.
  List<VtImageLayer> snapshotImages() {
    _ensureOpen();
    return snapshotKittyGraphics(_native, _terminal);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _clearEffectOpts();
    _closeCallables();
    if (_cells != nullptr) {
      _native.rowCellsFree(_cells);
      _cells = nullptr;
    }
    if (_rowIter != nullptr) {
      _native.rowIteratorFree(_rowIter);
      _rowIter = nullptr;
    }
    if (_renderState != nullptr) {
      _native.renderStateFree(_renderState);
      _renderState = nullptr;
    }
    if (_terminal != nullptr) {
      _native.terminalFree(_terminal);
      _terminal = nullptr;
    }
    _ptyOut.clear();
    _chrome.clear();
  }

  void _clearEffectOpts() {
    if (_terminal == nullptr) return;
    _native.terminalSet(_terminal, kTerminalOptWritePty, nullptr);
    _native.terminalSet(_terminal, kTerminalOptBell, nullptr);
    _native.terminalSet(_terminal, kTerminalOptTitleChanged, nullptr);
    _native.terminalSet(_terminal, kTerminalOptPwdChanged, nullptr);
    _native.terminalSet(_terminal, kTerminalOptClipboardWrite, nullptr);
    _native.terminalSet(_terminal, kTerminalOptProgressReport, nullptr);
    _native.terminalSet(_terminal, kTerminalOptDesktopNotification, nullptr);
    _native.terminalSet(_terminal, kTerminalOptUserdata, nullptr);
  }

  void _closeCallables() {
    _writePtyCall?.close();
    _writePtyCall = null;
    _bellCall?.close();
    _bellCall = null;
    _titleCall?.close();
    _titleCall = null;
    _pwdCall?.close();
    _pwdCall = null;
    _clipboardCall?.close();
    _clipboardCall = null;
    _progressCall?.close();
    _progressCall = null;
    _notifyCall?.close();
    _notifyCall = null;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('VtTerminal is closed');
  }
}

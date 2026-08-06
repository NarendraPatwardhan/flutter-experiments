import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard, KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;

import '../agent_os/vm.dart';
import '../vt/bindings.dart';
import '../vt/compress.dart';
import '../vt/encoder.dart';
import '../vt/format.dart';
import '../vt/frame.dart';
import '../vt/graphics.dart';
import '../vt/image_cache.dart';
import '../vt/keys.dart' show kKeyUNIDENTIFIED;
import '../vt/selection.dart';
import '../vt/snapshot.dart';
import '../vt/terminal.dart';

/// Dual-host live product session: AgentOS (guest) + Ghostty lib-vt (terminal).
///
/// Closed loop:
/// ```text
///   tick → take_output → vt_write → effects (WRITE_PTY → send_input)
///   keys/focus/paste → encode → send_input
///   projectRenderState → VtFrame → UI
/// ```
///
/// Both hosts stay open until [disposeAsync]. No close-after-demo.
class ProductSession extends ChangeNotifier {
  ProductSession();

  VtTerminal? _vt;
  VtEncoder? _encoder;
  VtSelectionController? _selection;
  AgentOsVm? _vm;
  Timer? _loop;
  bool _ticking = false;
  /// Completes when the current [_tickOnce] finishes (for orderly shutdown).
  Completer<void>? _tickIdle;
  bool _closed = false;
  bool _started = false;
  bool _nativeReleased = false;
  int _cellW = 8;
  int _cellH = 16;
  int _padL = 8;
  int _padT = 8;

  VtFrame _frame = VtFrame.empty();
  String _statusLine = '';
  bool _busy = false;
  bool _bellFlash = false;
  Timer? _bellTimer;
  String? _lastError;
  bool _atPrompt = false;
  bool _shellReady = false;
  int _readyTicks = 0;
  /// Partial line buffer for boot-noise filtering across take_output chunks.
  String _bootLineCarry = '';
  AgentOsTickState? _lastTick;
  String _title = '';
  String _pwd = '';

  final VtCompressScheduler _compress = VtCompressScheduler();
  final VtImageCache _imageCache = VtImageCache();
  List<VtImageLayer> _imageLayers = const [];
  VtChromeProgress? _progress;
  String? _lastNotification;

  /// Host→guest bytes coalesced onto the tick loop (avoids racing Isolate.run).
  final BytesBuilder _pendingInput = BytesBuilder(copy: false);

  VtFrame get frame => _frame;
  /// Quiet host status for chrome (errors / short lifecycle only — no metrics).
  String get statusLine => _statusLine;
  bool get busy => _busy;
  bool get bellFlash => _bellFlash;
  bool get started => _started;
  bool get closed => _closed;
  /// Guest shell is interactive; hide boot dump until this is true.
  bool get shellReady => _shellReady;
  bool get atPrompt => _atPrompt;
  VtTerminal? get vt => _vt;
  AgentOsVm? get vm => _vm;

  /// OSC title for host chrome (may be empty).
  String get windowTitle => _title;

  /// OSC pwd for host chrome (may be empty).
  String get pwd => _pwd;

  /// Pre-decoded Kitty images for the painter (z < 0).
  List<VtPaintImage> get imagesBelow => _imageCache.belowText;

  /// Pre-decoded Kitty images for the painter (z >= 0).
  List<VtPaintImage> get imagesAbove => _imageCache.aboveText;

  VtChromeProgress? get progress => _progress;
  String? get lastNotification => _lastNotification;

  /// Boot VT + encoder + AgentOS and start the ~50 Hz live loop.
  Future<void> start({
    required String hostLib,
    required String vtLib,
    required String kernel,
    required String image,
    int cols = 80,
    int rows = 24,
    int cellW = 8,
    int cellH = 16,
  }) async {
    if (_closed) {
      throw StateError('ProductSession already disposed');
    }
    await disposeAsync(notify: false);

    _closed = false;
    _nativeReleased = false;
    _busy = true;
    _shellReady = false;
    _readyTicks = 0;
    _bootLineCarry = '';
    _atPrompt = false;
    _statusLine = 'Starting…';
    _frame = VtFrame.empty(cols: cols, rows: rows);
    _lastError = null;
    _title = '';
    _pwd = '';
    _progress = null;
    _lastNotification = null;
    _imageLayers = const [];
    _compress.reset();
    notifyListeners();

    try {
      final vt = VtTerminal.open(cols, rows, vtLib);
      vt.resize(cols, rows, cellW: cellW, cellH: cellH);
      final encoder = VtEncoder.open(vtLib);
      _vt = vt;
      _encoder = encoder;
      _cellW = cellW;
      _cellH = cellH;
      _selection = VtSelectionController.open(vt.native);

      // No host banner / grid metrics — end users never need that.
      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      _statusLine = 'Starting…';
      notifyListeners();

      final vm = await AgentOsVm.bootFromFiles(
        kernelPath: kernel,
        imagePath: image,
        libraryPath: hostLib,
      );
      _vm = vm;
      _started = true;
      _busy = false;
      _statusLine = '';
      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      notifyListeners();

      _loop = Timer.periodic(const Duration(milliseconds: 20), (_) {
        unawaited(_tickOnce());
      });
      unawaited(_tickOnce());
    } catch (e) {
      _lastError = e.toString();
      _statusLine = 'error: $e';
      _busy = false;
      // Best-effort: paint the failure into the terminal if VT opened.
      final vt = _vt;
      if (vt != null) {
        try {
          vt.writeText('\r\n\x1b[1;31merror: $e\x1b[0m\r\n');
          _frame = vt.snapshot(previous: _frame);
        } catch (paintErr) {
          _lastError = '$_lastError; paint: $paintErr';
          _statusLine = 'error: $_lastError';
        }
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _tickOnce() async {
    if (_closed || _ticking) return;
    final vt = _vt;
    final vm = _vm;
    if (vt == null || vm == null) return;
    _ticking = true;
    try {
      final pending = _pendingInput.takeBytes();
      if (pending.isNotEmpty) {
        await vm.sendInput(pending);
        if (_closed) return;
      }

      try {
        _lastTick = await vm.tickN(8);
      } catch (e) {
        if (_closed) return;
        _lastError = 'tick: $e';
        _statusLine = _composeStatus(vt);
        _safeNotify();
        return;
      }
      if (_closed) return;

      if (_lastTick == AgentOsTickState.exited) {
        _loop?.cancel();
        _loop = null;
      }

      // Status before output so we know whether this tick is past boot.
      try {
        final st = await vm.status();
        if (_closed) return;
        _atPrompt = st.atPrompt;
        if (_lastError != null && _lastError!.startsWith('status:')) {
          _lastError = null;
        }
      } catch (e) {
        if (!_closed) _lastError = 'status: $e';
      }
      if (_closed) return;

      try {
        final out = await vm.takeOutput(capacity: 128 * 1024);
        if (_closed) return;
        if (out.isNotEmpty) {
          // Strip memcontainers boot diary only — keep `$` and real shell I/O.
          final cleaned = _stripBootNoise(out);
          if (cleaned.isNotEmpty) {
            vt.writeGuest(cleaned);
            _compress.onWrite(vt.native, vt.handle);
          }
        }
        if (_lastError != null && _lastError!.startsWith('take_output:')) {
          _lastError = null;
        }
      } catch (e) {
        if (!_closed) _lastError = 'take_output: $e';
      }
      if (_closed) return;

      _readyTicks += 1;
      if (!_shellReady && (_atPrompt || _readyTicks >= 100)) {
        // Flush any held non-boot partial line (often the first `$ `).
        _flushBootCarry(vt);
        _shellReady = true;
      }

      // WRITE_PTY (query answers) → guest input path.
      final ptyChunks = vt.takePtyOutput();
      if (ptyChunks.isNotEmpty) {
        final b = BytesBuilder(copy: false);
        for (final c in ptyChunks) {
          b.add(c);
        }
        final pty = b.takeBytes();
        if (pty.isNotEmpty) {
          try {
            await vm.sendInput(pty);
            if (_closed) return;
            if (_lastError != null && _lastError!.startsWith('pty reply:')) {
              _lastError = null;
            }
          } catch (e) {
            if (!_closed) _lastError = 'pty reply: $e';
          }
        }
      }
      if (_closed) return;

      var chromeDirty = false;
      for (final ev in vt.takeChromeEvents()) {
        chromeDirty = true;
        switch (ev) {
          case VtChromeBell():
            _flashBell();
          case VtChromeTitleChanged():
          case VtChromePwdChanged():
            break;
          case VtChromeClipboardWrite(:final parts):
            try {
              await _applyClipboardWrite(parts);
            } catch (e) {
              if (!_closed) _lastError = 'clipboard: $e';
            }
            if (_closed) return;
          case VtChromeProgress(:final state, :final progress):
            if (state == VtProgressState.remove) {
              _progress = null;
            } else {
              _progress = VtChromeProgress(state: state, progress: progress);
            }
          case VtChromeNotification(:final title, :final body):
            _lastNotification =
                title.isEmpty ? body : (body.isEmpty ? title : '$title — $body');
        }
      }
      if (_closed) return;
      if (chromeDirty) {
        _title = vt.title;
        _pwd = vt.pwd;
      }

      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      if (_closed) return;
      _statusLine = _composeStatus(vt);
      _safeNotify();
    } finally {
      _ticking = false;
      final waiter = _tickIdle;
      if (waiter != null && !waiter.isCompleted) {
        waiter.complete();
      }
      _tickIdle = null;
    }
  }

  void _safeNotify() {
    if (_closed) return;
    notifyListeners();
  }

  /// Apply an OSC 52 / OSC 1337 clipboard write to the platform clipboard.
  ///
  /// Empty [parts] clears the text clipboard (Ghostty semantics). Prefer
  /// text/plain; fall back to any empty-or-text MIME.
  Future<void> _applyClipboardWrite(
    List<({String mime, List<int> data})> parts,
  ) async {
    if (parts.isEmpty) {
      await Clipboard.setData(const ClipboardData(text: ''));
      return;
    }
    ({String mime, List<int> data})? preferred;
    for (final p in parts) {
      final mime = p.mime.toLowerCase();
      if (mime.isEmpty || mime == 'text/plain' || mime.contains('text')) {
        preferred = p;
        if (mime == 'text/plain' || mime.isEmpty) break;
      }
    }
    if (preferred == null) {
      // Non-text only (image/…): unsupported on this host path.
      _lastError = 'clipboard: unsupported MIME '
          '(${parts.map((p) => p.mime).join(', ')})';
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: utf8.decode(preferred.data, allowMalformed: true),
      ),
    );
  }

  Future<void> _syncImages(VtTerminal vt) async {
    try {
      _imageLayers = vt.snapshotImages();
      await _imageCache.sync(
        _imageLayers,
        originX: _padL.toDouble(),
        originY: _padT.toDouble(),
        cellW: _cellW.toDouble(),
        cellH: _cellH.toDouble(),
      );
      if (_lastError != null && _lastError!.startsWith('graphics:')) {
        _lastError = null;
      }
    } catch (e) {
      _lastError = 'graphics: $e';
    }
  }

  /// Quiet chrome string: errors, exit, optional pwd. Never grid or tick soup.
  String _composeStatus(VtTerminal vt) {
    if (_lastError != null) return _lastError!;
    if (_lastTick == AgentOsTickState.exited) return 'Session ended';
    if (_pwd.isNotEmpty) {
      var p = _pwd;
      if (p.startsWith('file://')) {
        final idx = p.indexOf('/', 7);
        p = idx >= 0 ? p.substring(idx) : p;
      }
      if (p.isNotEmpty && p != '/') return p;
    }
    return '';
  }

  /// Drop complete guest boot-banner lines only.
  ///
  /// Incomplete trailing text is always kept — holding it (old bug) swallowed
  /// every keystroke echo until Enter, so the terminal looked dead.
  bool _isBootNoiseLine(String line) {
    final t = line.trimLeft();
    if (t.isEmpty) return false;
    if (t.startsWith('memcontainers')) return true;
    if (t.startsWith('Booting')) return true;
    if (t.startsWith('Loading image')) return true;
    if (t.startsWith('Mounting ')) return true;
    return false;
  }

  /// True if [partial] is a long-enough prefix of a known boot banner line.
  bool _isIncompleteBootPrefix(String partial) {
    final t = partial.trimLeft();
    if (t.length < 6) return false;
    const heads = [
      'memcontainers',
      'Booting',
      'Loading image',
      'Mounting ',
    ];
    for (final h in heads) {
      if (h.startsWith(t)) return true;
    }
    return false;
  }

  Uint8List _stripBootNoise(Uint8List raw) {
    final chunk = utf8.decode(raw, allowMalformed: true);
    final text = '$_bootLineCarry$chunk';
    _bootLineCarry = '';

    final out = StringBuffer();
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x0a /* \n */) continue;
      final line = text.substring(start, i + 1);
      start = i + 1;
      if (!_isBootNoiseLine(line)) {
        out.write(line);
      }
    }
    if (start < text.length) {
      final partial = text.substring(start);
      if (_isIncompleteBootPrefix(partial)) {
        // Hold only clear boot-banner prefixes across chunks.
        _bootLineCarry = partial;
      } else {
        // Prompts, echoes, user text — paint immediately.
        out.write(partial);
      }
    }
    if (out.isEmpty) return Uint8List(0);
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  void _flushBootCarry(VtTerminal vt) {
    if (_bootLineCarry.isEmpty) return;
    if (_isBootNoiseLine(_bootLineCarry) ||
        _isIncompleteBootPrefix(_bootLineCarry)) {
      _bootLineCarry = '';
      return;
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(_bootLineCarry));
      _bootLineCarry = '';
      if (bytes.isNotEmpty) {
        vt.writeGuest(bytes);
        _compress.onWrite(vt.native, vt.handle);
      }
    } catch (_) {
      _bootLineCarry = '';
    }
  }

  String _formatProgress(VtChromeProgress p) {
    return switch (p.state) {
      VtProgressState.remove => '',
      VtProgressState.set => p.progress >= 0 ? 'prog ${p.progress}%' : 'prog',
      VtProgressState.error =>
        p.progress >= 0 ? 'prog err ${p.progress}%' : 'prog err',
      VtProgressState.indeterminate => 'prog …',
      VtProgressState.pause =>
        p.progress >= 0 ? 'prog pause ${p.progress}%' : 'prog pause',
    };
  }

  void _flashBell() {
    if (_closed) return;
    _bellFlash = true;
    _safeNotify();
    _bellTimer?.cancel();
    _bellTimer = Timer(const Duration(milliseconds: 180), () {
      if (_closed) return;
      _bellFlash = false;
      _safeNotify();
    });
  }

  void _enqueueInput(Uint8List data) {
    if (data.isEmpty || _closed || _vm == null) return;
    _pendingInput.add(data);
  }

  /// Clear the **live VT display only** after a timeline freeze.
  ///
  /// AgentOS guest is untouched (same machine, cwd, processes). The next
  /// terminal cell starts visually empty so frozen history is not repeated.
  void clearDisplayForNewCell() {
    final vt = _vt;
    if (vt == null || _closed) return;
    try {
      // Erase screen + scrollback; home cursor. Does not reset the guest shell.
      vt.writeText('\x1b[2J\x1b[3J\x1b[H');
      _compress.onWrite(vt.native, vt.handle);
      try {
        vt.scrollViewport(bottom: true);
      } catch (_) {}
      _frame = vt.snapshot(previous: _frame).copyWithMeta(
            cursorVisible: true,
          );
      _safeNotify();
    } catch (e) {
      _lastError = 'clear display: $e';
      _safeNotify();
    }
  }

  /// Map Flutter [KeyEvent] → Ghostty encoder → AgentOS send_input.
  ///
  /// Does **not** hand-roll CSI. Unmapped keys use [kKeyUNIDENTIFIED] with UTF-8.
  Future<void> onKey(KeyEvent event) async {
    if (_closed || _vt == null || _vm == null || _encoder == null) return;

    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return;

    final action = event is KeyDownEvent
        ? kKeyActionPress
        : event is KeyRepeatEvent
            ? kKeyActionRepeat
            : kKeyActionRelease;

    final mods = VtEncoder.modsFromHardware();
    final mapped = VtEncoder.logicalKeyToGhostty(event.logicalKey);
    final utf8Text = isDown ? event.character : null;
    final ghosttyKey = mapped ?? kKeyUNIDENTIFIED;

    // Bare unidentified with no text produces nothing useful — skip.
    if (mapped == null &&
        (utf8Text == null || utf8Text.isEmpty) &&
        isDown) {
      return;
    }

    try {
      final bytes = _encoder!.encodeKey(
        terminal: _vt!.handle,
        ghosttyKey: ghosttyKey,
        mods: mods,
        action: action,
        utf8: utf8Text,
      );
      // Empty is normal (e.g. unmodified Shift alone).
      if (bytes.isNotEmpty) _enqueueInput(bytes);
      if (_lastError != null && _lastError!.startsWith('key ')) {
        _lastError = null;
      }
    } catch (e) {
      _lastError = 'key encode: $e';
      _statusLine = _composeStatus(_vt!);
      notifyListeners();
    }
  }

  Future<void> onFocus(bool gained) async {
    if (_closed || _vt == null || _vm == null || _encoder == null) return;
    try {
      final bytes = _encoder!.encodeFocus(gained: gained);
      if (bytes.isNotEmpty) _enqueueInput(bytes);
      if (_lastError != null && _lastError!.startsWith('focus ')) {
        _lastError = null;
        _statusLine = _composeStatus(_vt!);
        notifyListeners();
      }
    } catch (e) {
      _lastError = 'focus encode: $e';
      _statusLine = _composeStatus(_vt!);
      notifyListeners();
    }
  }

  Future<void> onPaste(String text) async {
    if (_closed || _vt == null || _vm == null || _encoder == null) return;
    if (text.isEmpty) return;
    try {
      // pasteEncode strips unsafe control bytes; always use it.
      final bytes = _encoder!.encodePaste(text, bracketed: true);
      if (bytes.isNotEmpty) _enqueueInput(bytes);
      if (_lastError != null && _lastError!.startsWith('paste ')) {
        _lastError = null;
        _statusLine = _composeStatus(_vt!);
        notifyListeners();
      }
    } catch (e) {
      _lastError = 'paste encode: $e';
      _statusLine = _composeStatus(_vt!);
      notifyListeners();
    }
  }

  /// Surface pixel pointer → selection gesture (cell space).
  Future<void> onPointer({
    required int kind,
    double x = 0,
    double y = 0,
    int padL = 8,
    int padT = 8,
  }) async {
    if (_closed || _vt == null || _selection == null) return;
    _padL = padL;
    _padT = padT;
    final cellX = ((x - padL) / _cellW).floor();
    final cellY = ((y - padT) / _cellH).floor();
    if (cellX < 0 || cellY < 0 || cellX >= _vt!.cols || cellY >= _vt!.rows) {
      return;
    }
    try {
      final ok = _selection!.onPointer(
        _vt!.handle,
        kind: kind,
        cellX: cellX,
        cellY: cellY,
        surfaceX: x,
        surfaceY: y,
        columns: _vt!.cols,
        cellWidth: _cellW,
        paddingLeft: padL,
        screenHeight: _vt!.rows * _cellH + padT,
      );
      if (ok) {
        _frame = _vt!.snapshot(previous: _frame);
        notifyListeners();
      }
    } catch (e) {
      _lastError = 'selection: $e';
      notifyListeners();
    }
  }

  /// Copy current selection as plain text (null if none / error).
  Future<String?> copySelection() async {
    if (_closed || _vt == null) return null;
    try {
      return await copySelectionText(_vt!.native, _vt!.handle);
    } catch (e) {
      _lastError = 'copy: $e';
      notifyListeners();
      return null;
    }
  }

  /// Scroll viewport by pixel [dy] (negative = wheel up → history).
  /// Used for **in-cell** scroll of the live terminal (not notebook page scroll).
  Future<void> onScroll(double dy) async {
    if (_closed || _vt == null || dy == 0) return;
    // Trackpad/mouse: dy > 0 is wheel down (toward present); dy < 0 is up (history).
    final rows = (dy.abs() / widgetCellScrollPx()).ceil().clamp(1, 48);
    final delta = dy < 0 ? -rows : rows;
    try {
      _vt!.scrollViewport(deltaRows: delta);
      _frame = _vt!.snapshot(previous: _frame);
      await _syncImages(_vt!);
      notifyListeners();
    } catch (e) {
      _lastError = 'scroll: $e';
      notifyListeners();
    }
  }

  /// Pixels per scroll row — roughly one mono line.
  double widgetCellScrollPx() => _cellH > 0 ? _cellH.toDouble() : 14.0;

  Future<void> resize(
    int cols,
    int rows,
    int cellW,
    int cellH, {
    int? padL,
    int? padT,
  }) async {
    if (_closed || _vt == null) return;
    if (cols < 1 || rows < 1) return;
    final vt = _vt!;
    _cellW = cellW;
    _cellH = cellH;
    if (padL != null) _padL = padL;
    if (padT != null) _padT = padT;
    try {
      vt.resize(cols, rows, cellW: cellW, cellH: cellH);
      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      _statusLine = _composeStatus(vt);
      notifyListeners();
    } catch (e) {
      _lastError = 'resize: $e';
      _statusLine = _composeStatus(vt);
      notifyListeners();
    }
  }

  /// Debug: encode full terminal snapshot blob.
  ///
  /// Throws on encode failure so callers can surface the error.
  Uint8List debugSnapshotEncode() {
    final vt = _vt;
    if (vt == null || _closed) {
      throw StateError('session not open');
    }
    return snapshotEncode(vt.native, vt.handle);
  }

  /// Debug: format active screen as plain / vt / html.
  ///
  /// Throws on format failure so callers can surface the error.
  String debugFormat({VtFormatKind format = VtFormatKind.plain}) {
    final vt = _vt;
    if (vt == null || _closed) {
      throw StateError('session not open');
    }
    return formatTerminal(vt.native, vt.handle, format: format);
  }

  /// Close VM + VT + encoder and stop the loop.
  ///
  /// Waits for any in-flight tick so native handles are never freed under a
  /// concurrent [vt_write] / snapshot (that race corrupted the heap and
  /// surfaced as GTK CRITICAL + SIGSEGV on window close).
  Future<void> disposeAsync({bool notify = true}) async {
    _closed = true;
    _loop?.cancel();
    _loop = null;
    _bellTimer?.cancel();
    _bellTimer = null;
    _compress.dispose();
    _pendingInput.clear();
    _started = false;
    _busy = false;
    _shellReady = false;
    _readyTicks = 0;
    _bootLineCarry = '';
    _atPrompt = false;

    await _waitForTickIdle();
    final tears = _releaseNative();
    _imageCache.dispose();
    _imageLayers = const [];

    if (tears.isNotEmpty) {
      _lastError = 'dispose: ${tears.join('; ')}';
    }
    if (notify) {
      _statusLine = tears.isEmpty ? '' : 'Session error';
      // ChangeNotifier may already be disposed on widget teardown — guard.
      try {
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> _waitForTickIdle() async {
    if (!_ticking) return;
    final existing = _tickIdle;
    if (existing != null) {
      await existing.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      return;
    }
    final c = Completer<void>();
    _tickIdle = c;
    if (!_ticking) {
      if (!c.isCompleted) c.complete();
      _tickIdle = null;
      return;
    }
    await c.future.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {},
    );
  }

  /// Drop Dart refs and free native hosts. Idempotent.
  List<String> _releaseNative() {
    if (_nativeReleased) return const [];
    _nativeReleased = true;

    final vm = _vm;
    final enc = _encoder;
    final sel = _selection;
    final vt = _vt;
    _vm = null;
    _encoder = null;
    _selection = null;
    _vt = null;

    final tears = <String>[];
    // Clear effects before closing callables / terminal so lib-vt never
    // re-enters Dart during teardown.
    try {
      if (vt != null) {
        sel?.close(vt.handle);
      } else {
        sel?.close();
      }
    } catch (e) {
      tears.add('selection: $e');
    }
    try {
      enc?.close();
    } catch (e) {
      tears.add('encoder: $e');
    }
    try {
      vt?.close();
    } catch (e) {
      tears.add('vt: $e');
    }
    if (vm != null) {
      // Fire-and-forget: isolate close can block; process exit reclaims.
      unawaited(() async {
        try {
          await vm.close();
        } catch (_) {}
      }());
    }
    return tears;
  }

  @override
  void dispose() {
    _closed = true;
    _loop?.cancel();
    _loop = null;
    _bellTimer?.cancel();
    _bellTimer = null;
    _compress.dispose();
    // If a tick is in flight, do **not** free native under it — schedule
    // release for when the tick completes (or after a short grace). Freeing
    // libghostty-vt / AgentOS mid-await corrupted GObject memory and crashed
    // GTK on window close.
    if (_ticking) {
      final c = _tickIdle ?? Completer<void>();
      _tickIdle = c;
      unawaited(() async {
        await c.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
        _releaseNative();
        _imageCache.dispose();
      }());
    } else {
      _releaseNative();
      _imageCache.dispose();
    }
    super.dispose();
  }
}

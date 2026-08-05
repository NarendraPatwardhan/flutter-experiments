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
  bool _closed = false;
  bool _started = false;
  int _cellW = 8;
  int _cellH = 16;
  int _padL = 8;
  int _padT = 8;

  VtFrame _frame = VtFrame.empty();
  String _statusLine = 'idle';
  bool _busy = false;
  bool _bellFlash = false;
  Timer? _bellTimer;
  String? _lastError;
  bool _atPrompt = false;
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
  String get statusLine => _statusLine;
  bool get busy => _busy;
  bool get bellFlash => _bellFlash;
  bool get started => _started;
  bool get closed => _closed;
  VtTerminal? get vt => _vt;
  AgentOsVm? get vm => _vm;

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
    _busy = true;
    _statusLine = 'opening vt…';
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
      try {
        _selection = VtSelectionController.open(vt.native);
      } catch (_) {
        _selection = null;
      }

      // Short banner via VT only — not exec spam.
      vt.writeText(
        '\x1b[1;32magentos\x1b[0m · flutter · live session\r\n'
        '\x1b[90mgrid ${vt.cols}×${vt.rows}  '
        'cell ${cellW}×$cellH\x1b[0m\r\n',
      );
      _compress.onWrite(vt.native, vt.handle);
      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      _statusLine = 'booting agentos…';
      notifyListeners();

      final vm = await AgentOsVm.bootFromFiles(
        kernelPath: kernel,
        imagePath: image,
        libraryPath: hostLib,
      );
      _vm = vm;
      _started = true;
      _busy = false;
      _statusLine = 'live  ${vt.cols}×${vt.rows}';
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
      try {
        _vt?.writeText('\r\n\x1b[1;31merror: $e\x1b[0m\r\n');
        if (_vt != null) {
          _frame = _vt!.snapshot(previous: _frame);
        }
      } catch (_) {}
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
      }

      try {
        _lastTick = await vm.tickN(8);
      } catch (e) {
        _lastError = e.toString();
        _statusLine = 'tick error: $e';
        notifyListeners();
        return;
      }

      Uint8List out = Uint8List(0);
      try {
        out = await vm.takeOutput(capacity: 128 * 1024);
      } catch (e) {
        _lastError = e.toString();
      }
      if (out.isNotEmpty) {
        vt.writeGuest(out);
        _compress.onWrite(vt.native, vt.handle);
      }

      // WRITE_PTY → guest.
      final ptyChunks = vt.takePtyOutput();
      if (ptyChunks.isNotEmpty) {
        final b = BytesBuilder(copy: false);
        for (final c in ptyChunks) {
          b.add(c);
        }
        final pty = b.takeBytes();
        if (pty.isNotEmpty) {
          await vm.sendInput(pty);
        }
      }

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
            for (final p in parts) {
              if (p.data.isEmpty) continue;
              final mime = p.mime.toLowerCase();
              if (mime.isEmpty ||
                  mime.contains('text') ||
                  mime == 'text/plain') {
                try {
                  unawaited(Clipboard.setData(
                    ClipboardData(
                      text: utf8.decode(p.data, allowMalformed: true),
                    ),
                  ));
                } catch (_) {}
                break;
              }
            }
          case VtChromeProgress(:final state, :final progress):
            _progress = VtChromeProgress(state: state, progress: progress);
            if (state == VtProgressState.remove) {
              _progress = null;
            }
          case VtChromeNotification(:final title, :final body):
            _lastNotification =
                title.isEmpty ? body : (body.isEmpty ? title : '$title — $body');
        }
      }
      if (chromeDirty) {
        try {
          _title = vt.title;
          _pwd = vt.pwd;
        } catch (_) {}
      }

      try {
        final st = await vm.status();
        _atPrompt = st.atPrompt;
      } catch (_) {}

      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      _statusLine = _composeStatus(vt);
      notifyListeners();
    } finally {
      _ticking = false;
    }
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
    } catch (_) {
      // Graphics optional at runtime if build disabled them.
    }
  }

  String _composeStatus(VtTerminal vt) {
    if (_lastError != null) return 'error: $_lastError';
    final parts = <String>[];
    if (_title.isNotEmpty) {
      parts.add(_title);
    } else {
      parts.add('agentos');
    }
    if (_pwd.isNotEmpty) {
      var p = _pwd;
      if (p.startsWith('file://')) {
        final idx = p.indexOf('/', 7);
        p = idx >= 0 ? p.substring(idx) : p;
      }
      parts.add(p);
    }
    parts.add('${vt.cols}×${vt.rows}');
    if (_atPrompt) parts.add('prompt');
    if (_lastTick == AgentOsTickState.exited) parts.add('exited');
    if (_lastTick == AgentOsTickState.waiting) parts.add('wait');
    final prog = _progress;
    if (prog != null) {
      parts.add(_formatProgress(prog));
    }
    if (_lastNotification != null && _lastNotification!.isNotEmpty) {
      parts.add('notify: $_lastNotification');
    }
    return parts.join('  ·  ');
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
    _bellFlash = true;
    notifyListeners();
    _bellTimer?.cancel();
    _bellTimer = Timer(const Duration(milliseconds: 180), () {
      _bellFlash = false;
      notifyListeners();
    });
  }

  void _enqueueInput(Uint8List data) {
    if (data.isEmpty || _closed || _vm == null) return;
    _pendingInput.add(data);
  }

  /// Map Flutter [KeyEvent] → terminal bytes → AgentOS send_input.
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
    final keyCode = VtEncoder.logicalKeyToGhostty(event.logicalKey);
    final utf8Text = isDown ? event.character : null;

    try {
      if (keyCode != null) {
        final bytes = _encoder!.encodeKey(
          terminal: _vt!.handle,
          ghosttyKey: keyCode,
          mods: mods,
          action: action,
          utf8: utf8Text,
        );
        if (bytes.isNotEmpty) {
          _enqueueInput(bytes);
          return;
        }
      }
    } catch (_) {
      // Fall through to temporary fallback encoder.
    }

    // Fallback: enter → \r; backspace/tab/esc; printable UTF-8 only.
    if (!isDown) return;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _enqueueInput(Uint8List.fromList(const [0x0d]));
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _enqueueInput(Uint8List.fromList(const [0x7f]));
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _enqueueInput(Uint8List.fromList(const [0x09]));
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _enqueueInput(Uint8List.fromList(const [0x1b]));
      return;
    }
    final ch = event.character;
    if (ch != null && ch.isNotEmpty) {
      if (ch.codeUnitAt(0) >= 0x20 || ch == '\n' || ch == '\r' || ch == '\t') {
        _enqueueInput(Uint8List.fromList(utf8.encode(ch)));
      }
    }
  }

  Future<void> onFocus(bool gained) async {
    if (_closed || _vt == null || _vm == null || _encoder == null) return;
    try {
      final bytes = _encoder!.encodeFocus(gained: gained);
      if (bytes.isNotEmpty) _enqueueInput(bytes);
    } catch (_) {}
  }

  Future<void> onPaste(String text) async {
    if (_closed || _vt == null || _vm == null || _encoder == null) return;
    if (text.isEmpty) return;
    try {
      final bytes = _encoder!.encodePaste(text, bracketed: true);
      if (bytes.isNotEmpty) {
        _enqueueInput(bytes);
        return;
      }
    } catch (_) {}
    _enqueueInput(Uint8List.fromList(utf8.encode(text)));
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
    } catch (_) {}
  }

  /// Copy current selection as plain text (empty if none).
  Future<String?> copySelection() async {
    if (_closed || _vt == null) return null;
    try {
      return await copySelectionText(_vt!.native, _vt!.handle);
    } catch (_) {
      return null;
    }
  }

  /// Scroll viewport by pixel [dy] (negative = wheel up → history).
  Future<void> onScroll(double dy) async {
    if (_closed || _vt == null || dy == 0) return;
    final rows = (dy.abs() / 12).ceil().clamp(1, 32);
    final delta = dy < 0 ? -rows : rows;
    try {
      _vt!.scrollViewport(deltaRows: delta);
      _frame = _vt!.snapshot(previous: _frame);
      await _syncImages(_vt!);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> resize(int cols, int rows, int cellW, int cellH) async {
    if (_closed || _vt == null) return;
    if (cols < 1 || rows < 1) return;
    final vt = _vt!;
    _cellW = cellW;
    _cellH = cellH;
    try {
      vt.resize(cols, rows, cellW: cellW, cellH: cellH);
      _frame = vt.snapshot(previous: _frame);
      await _syncImages(vt);
      _statusLine = _composeStatus(vt);
      notifyListeners();
    } catch (_) {}
  }

  /// Debug: encode full terminal snapshot blob.
  Uint8List? debugSnapshotEncode() {
    final vt = _vt;
    if (vt == null || _closed) return null;
    try {
      return snapshotEncode(vt.native, vt.handle);
    } catch (_) {
      return null;
    }
  }

  /// Debug: format active screen as plain / vt / html.
  String? debugFormat({VtFormatKind format = VtFormatKind.plain}) {
    final vt = _vt;
    if (vt == null || _closed) return null;
    try {
      return formatTerminal(vt.native, vt.handle, format: format);
    } catch (_) {
      return null;
    }
  }

  /// Close VM + VT + encoder and stop the loop.
  Future<void> disposeAsync({bool notify = true}) async {
    _loop?.cancel();
    _loop = null;
    _bellTimer?.cancel();
    _bellTimer = null;
    _compress.dispose();
    _imageCache.dispose();
    _started = false;
    _pendingInput.clear();
    _imageLayers = const [];

    final vm = _vm;
    _vm = null;
    final enc = _encoder;
    _encoder = null;
    final sel = _selection;
    _selection = null;
    final vt = _vt;
    _vt = null;

    if (vm != null) {
      try {
        await vm.close();
      } catch (_) {}
    }
    try {
      if (vt != null) {
        sel?.close(vt.handle);
      } else {
        sel?.close();
      }
    } catch (_) {}
    try {
      enc?.close();
    } catch (_) {}
    try {
      vt?.close();
    } catch (_) {}

    _busy = false;
    if (notify && !_closed) {
      _statusLine = 'stopped';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _loop?.cancel();
    _loop = null;
    _bellTimer?.cancel();
    _bellTimer = null;
    _compress.dispose();
    _imageCache.dispose();
    try {
      _encoder?.close();
    } catch (_) {}
    _encoder = null;
    try {
      final t = _vt;
      if (t != null) {
        _selection?.close(t.handle);
      } else {
        _selection?.close();
      }
    } catch (_) {}
    _selection = null;
    try {
      _vt?.close();
    } catch (_) {}
    _vt = null;
    final vm = _vm;
    _vm = null;
    if (vm != null) {
      unawaited(vm.close());
    }
    super.dispose();
  }
}

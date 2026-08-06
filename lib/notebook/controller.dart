// Notebook controller — mode, freeze, history, palette open (SYSTEM H1).

import 'package:flutter/foundation.dart';

import '../session/product_session.dart';
import 'host_keys.dart';
import 'model.dart';

/// Owns notebook UI state; does not own ProductSession lifecycle.
class NotebookController extends ChangeNotifier {
  NotebookController();

  NotebookViewState _state = const NotebookViewState();
  int _seq = 0;
  DateTime? _lastFreezeAt;

  NotebookViewState get state => _state;
  InputMode get mode => _state.mode;
  bool get paletteOpen => _state.paletteOpen;
  List<NotebookHistoryEntry> get history => _state.history;
  int get historyRevision => _state.historyRevision;
  String? get statusFlash => _state.statusFlash;

  void setMode(InputMode mode) {
    if (_state.mode == mode) return;
    _state = _state.copyWith(mode: mode, clearStatusFlash: true);
    notifyListeners();
  }

  void toggleMode() {
    setMode(
      _state.mode == InputMode.terminal
          ? InputMode.naturalLanguage
          : InputMode.terminal,
    );
  }

  void setPaletteOpen(bool open) {
    if (_state.paletteOpen == open) return;
    _state = _state.copyWith(paletteOpen: open);
    notifyListeners();
  }

  /// Capture live frame into history; guest keeps running.
  /// Returns false if nothing was frozen (not started / debounce / empty).
  bool freezeLive(ProductSession session) {
    if (!session.started) {
      _flash('terminal not ready');
      return false;
    }
    final now = DateTime.now();
    if (_lastFreezeAt != null &&
        now.difference(_lastFreezeAt!) < const Duration(milliseconds: 350)) {
      return false;
    }
    final frame = session.frame.clone();
    if (frame.cols <= 0 || frame.rows <= 0) {
      _flash('nothing to freeze');
      return false;
    }
    _lastFreezeAt = now;
    _seq += 1;
    final cell = FrozenTerminalCell(
      id: 'freeze-$_seq',
      frame: frame,
      label: 'terminal',
    );
    final next = List<NotebookHistoryEntry>.of(_state.history)
      ..add(FrozenTerminalEntry(cell));
    _state = _state.copyWith(
      history: next,
      historyRevision: _state.historyRevision + 1,
      statusFlash: 'frozen ${frame.cols}×${frame.rows}',
    );
    notifyListeners();
    return true;
  }

  /// Record a user ask in history and return to terminal mode.
  bool submitUserMessage(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _flash('empty message');
      return false;
    }
    _seq += 1;
    final cell = UserMessageCell(id: 'ask-$_seq', text: t);
    final next = List<NotebookHistoryEntry>.of(_state.history)
      ..add(UserMessageEntry(cell));
    _state = _state.copyWith(
      history: next,
      historyRevision: _state.historyRevision + 1,
      mode: InputMode.terminal,
      statusFlash: 'sent',
    );
    notifyListeners();
    return true;
  }

  void clearStatusFlash() {
    if (_state.statusFlash == null) return;
    _state = _state.copyWith(clearStatusFlash: true);
    notifyListeners();
  }

  void _flash(String msg) {
    _state = _state.copyWith(statusFlash: msg);
    notifyListeners();
  }

  /// Bottom-bar hints for current mode.
  List<HintItem> hintsForCurrent() {
    if (_state.paletteOpen) {
      return const [
        HintItem(keyLabel: 'Esc', action: 'close'),
        HintItem(keyLabel: '↑↓', action: 'move'),
        HintItem(keyLabel: '↵', action: 'run'),
      ];
    }
    switch (_state.mode) {
      case InputMode.terminal:
        return [
          HintItem(
            keyLabel: hostChordKeyLabel(HostChord.toggleMode),
            action: 'ask',
          ),
          HintItem(
            keyLabel: hostChordKeyLabel(HostChord.controlPlane),
            action: 'control plane',
          ),
        ];
      case InputMode.naturalLanguage:
        return [
          HintItem(
            keyLabel: hostChordKeyLabel(HostChord.nlSubmit),
            action: 'send',
          ),
          HintItem(
            keyLabel: hostChordKeyLabel(HostChord.toggleMode),
            action: 'terminal',
          ),
          HintItem(
            keyLabel: hostChordKeyLabel(HostChord.escape),
            action: 'clear / back',
          ),
        ];
    }
  }

  String? modeChipLabel() {
    switch (_state.mode) {
      case InputMode.terminal:
        return null;
      case InputMode.naturalLanguage:
        return 'ask';
    }
  }
}

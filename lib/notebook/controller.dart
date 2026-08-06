import 'package:flutter/foundation.dart';

import 'model.dart';

/// Notebook UI state: mode, timeline, control-plane open.
class NotebookController extends ChangeNotifier {
  NotebookController();

  NotebookViewState _state = const NotebookViewState();
  int _seq = 0;

  NotebookViewState get state => _state;
  InputMode get mode => _state.mode;
  bool get paletteOpen => _state.paletteOpen;
  List<TimelineEntry> get timeline => _state.timeline;
  int get timelineRevision => _state.timelineRevision;
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

  /// Append a user message and return to terminal mode.
  bool submitUserMessage(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _flash('empty message');
      return false;
    }
    _seq += 1;
    final msg = UserMessage(id: 'msg-$_seq', text: t);
    final next = List<TimelineEntry>.of(_state.timeline)
      ..add(UserMessageEntry(msg));
    _state = _state.copyWith(
      timeline: next,
      timelineRevision: _state.timelineRevision + 1,
      mode: InputMode.terminal,
      clearStatusFlash: true,
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
        return const [
          HintItem(keyLabel: 'Shift+Tab', action: 'ask'),
          HintItem(keyLabel: 'Ctrl+K', action: 'control plane'),
        ];
      case InputMode.naturalLanguage:
        return const [
          HintItem(keyLabel: 'Ctrl+Enter', action: 'send'),
          HintItem(keyLabel: 'Shift+Tab', action: 'terminal'),
          HintItem(keyLabel: 'Esc', action: 'clear / back'),
        ];
    }
  }

  String? modeChipLabel() {
    return _state.mode == InputMode.naturalLanguage ? 'ask' : null;
  }
}

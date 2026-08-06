import 'package:flutter/foundation.dart';

import '../vt/frame.dart';
import 'document.dart';
import 'freeze_policy.dart';

/// Notebook UI state machine — docs/notebook-components.md §5.
class NotebookController extends ChangeNotifier {
  NotebookController();

  NotebookDocument _doc = const NotebookDocument();
  int _seq = 0;

  NotebookDocument get document => _doc;
  InputMode get mode => _doc.mode;
  bool get paletteOpen => _doc.paletteOpen;
  List<NotebookCell> get timeline => _doc.timeline;
  bool get hasTimeline => _doc.hasTimeline;
  int get revision => _doc.revision;
  String? get statusFlash => _doc.statusFlash;

  void setMode(InputMode mode) {
    if (_doc.mode == mode) return;
    _doc = _doc.copyWith(
      active: _doc.active.copyWith(mode: mode),
      clearStatusFlash: true,
    );
    notifyListeners();
  }

  /// Terminal → ask: freeze live VT into timeline if it has ink.
  /// Caller must then [ProductSession.beginNewTerminalSurface].
  /// Returns true if a freeze cell was appended.
  bool enterAsk({VtFrame? liveFrame}) {
    if (_doc.mode == InputMode.naturalLanguage) return false;
    final next = List<NotebookCell>.of(_doc.timeline);
    var froze = false;
    // Only freeze real work — bare reattached `$ ` is not a history cell.
    if (liveFrame != null && FreezePolicy.isWorthFreezing(liveFrame)) {
      _seq += 1;
      next.add(
        TerminalFreezeCell(
          id: 'term-$_seq',
          frame: FreezePolicy.apply(liveFrame),
        ),
      );
      froze = true;
    }
    _doc = _doc.copyWith(
      timeline: next,
      revision: froze ? _doc.revision + 1 : _doc.revision,
      active: _doc.active.copyWith(mode: InputMode.naturalLanguage),
      clearStatusFlash: true,
    );
    notifyListeners();
    return froze;
  }

  void enterTerminal() {
    setMode(InputMode.terminal);
  }

  void setPaletteOpen(bool open) {
    if (_doc.paletteOpen == open) return;
    _doc = _doc.copyWith(paletteOpen: open);
    notifyListeners();
  }

  bool submitUserMessage(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _flash('empty message');
      return false;
    }
    _seq += 1;
    final you = UserMessageCell(id: 'msg-$_seq', text: t);
    _seq += 1;
    final agent = AgentTurnCell(
      id: 'agent-$_seq',
      summary: 'Agent not connected yet — message recorded on this machine.',
    );
    final next = List<NotebookCell>.of(_doc.timeline)
      ..add(you)
      ..add(agent);
    _doc = _doc.copyWith(
      timeline: next,
      revision: _doc.revision + 1,
      active: _doc.active.copyWith(
        mode: InputMode.naturalLanguage,
        askDraft: '',
      ),
      clearStatusFlash: true,
    );
    notifyListeners();
    return true;
  }

  void clearStatusFlash() {
    if (_doc.statusFlash == null) return;
    _doc = _doc.copyWith(clearStatusFlash: true);
    notifyListeners();
  }

  void _flash(String msg) {
    _doc = _doc.copyWith(statusFlash: msg);
    notifyListeners();
  }

  List<HintItem> hintsForCurrent() {
    if (_doc.paletteOpen) {
      return const [
        HintItem(keyLabel: 'Esc', action: 'close'),
        HintItem(keyLabel: '↑↓', action: 'move'),
        HintItem(keyLabel: '↵', action: 'run'),
      ];
    }
    switch (_doc.mode) {
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
}

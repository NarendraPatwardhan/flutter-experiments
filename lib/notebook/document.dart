// Domain model — docs/notebook-components.md §3

import '../vt/frame.dart';

/// Active input mode on the bottom [ActiveSlot].
enum InputMode {
  terminal,
  naturalLanguage,
}

/// Immutable history cell kinds.
sealed class NotebookCell {
  const NotebookCell();
  String get id;
  DateTime get at;
}

class TerminalFreezeCell extends NotebookCell {
  TerminalFreezeCell({
    required this.id,
    required this.frame,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  @override
  final String id;
  final VtFrame frame;
  @override
  final DateTime at;
}

class UserMessageCell extends NotebookCell {
  UserMessageCell({
    required this.id,
    required this.text,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  @override
  final String id;
  final String text;
  @override
  final DateTime at;
}

class AgentTurnCell extends NotebookCell {
  AgentTurnCell({
    required this.id,
    required this.summary,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  @override
  final String id;
  final String summary;
  @override
  final DateTime at;
}

/// Active slot state (mode + ask draft). Live VT lives on [ProductSession].
class ActiveCell {
  const ActiveCell({
    this.mode = InputMode.terminal,
    this.askDraft = '',
  });

  final InputMode mode;
  final String askDraft;

  ActiveCell copyWith({InputMode? mode, String? askDraft}) {
    return ActiveCell(
      mode: mode ?? this.mode,
      askDraft: askDraft ?? this.askDraft,
    );
  }
}

/// Full notebook document: timeline + active slot.
class NotebookDocument {
  const NotebookDocument({
    this.timeline = const [],
    this.active = const ActiveCell(),
    this.paletteOpen = false,
    this.statusFlash,
    this.revision = 0,
  });

  final List<NotebookCell> timeline;
  final ActiveCell active;
  final bool paletteOpen;
  final String? statusFlash;
  final int revision;

  bool get hasTimeline => timeline.isNotEmpty;
  InputMode get mode => active.mode;

  NotebookDocument copyWith({
    List<NotebookCell>? timeline,
    ActiveCell? active,
    bool? paletteOpen,
    String? statusFlash,
    bool clearStatusFlash = false,
    int? revision,
  }) {
    return NotebookDocument(
      timeline: timeline ?? this.timeline,
      active: active ?? this.active,
      paletteOpen: paletteOpen ?? this.paletteOpen,
      statusFlash:
          clearStatusFlash ? null : (statusFlash ?? this.statusFlash),
      revision: revision ?? this.revision,
    );
  }
}

/// Bottom-bar hint.
class HintItem {
  const HintItem({required this.keyLabel, required this.action});
  final String keyLabel;
  final String action;
}

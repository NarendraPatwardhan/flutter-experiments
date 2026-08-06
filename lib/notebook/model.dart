// Notebook spine model — pure types (SYSTEM H1 / docs/ui-northstar.md).

import '../vt/frame.dart';

/// Active input mode on the bottom surface.
enum InputMode {
  /// Keys go to the live Ghostty/AgentOS terminal cell.
  terminal,

  /// Host multiline composer; submit records a user turn (agent runtime later).
  naturalLanguage,
}

/// One frozen terminal snapshot above the live surface.
class FrozenTerminalCell {
  FrozenTerminalCell({
    required this.id,
    required this.frame,
    DateTime? frozenAt,
    this.label,
  }) : frozenAt = frozenAt ?? DateTime.now();

  final String id;
  final VtFrame frame;
  final DateTime frozenAt;
  final String? label;
}

/// User natural-language turn in history (before agent runtime exists).
class UserMessageCell {
  UserMessageCell({
    required this.id,
    required this.text,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String text;
  final DateTime at;
}

/// Quiet host notice (freeze confirmation, errors) — short, user-facing.
class SystemNoticeCell {
  SystemNoticeCell({
    required this.id,
    required this.message,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String message;
  final DateTime at;
}

/// History entry above the active region.
sealed class NotebookHistoryEntry {
  const NotebookHistoryEntry();
  String get id;
}

class FrozenTerminalEntry extends NotebookHistoryEntry {
  const FrozenTerminalEntry(this.cell);
  final FrozenTerminalCell cell;
  @override
  String get id => cell.id;
}

class UserMessageEntry extends NotebookHistoryEntry {
  const UserMessageEntry(this.cell);
  final UserMessageCell cell;
  @override
  String get id => cell.id;
}

class SystemNoticeEntry extends NotebookHistoryEntry {
  const SystemNoticeEntry(this.cell);
  final SystemNoticeCell cell;
  @override
  String get id => cell.id;
}

/// One row of bottom-bar live hints.
class HintItem {
  const HintItem({required this.keyLabel, required this.action});
  final String keyLabel;
  final String action;
}

/// Immutable notebook view-state snapshot for widgets.
class NotebookViewState {
  const NotebookViewState({
    this.history = const [],
    this.mode = InputMode.terminal,
    this.paletteOpen = false,
    this.statusFlash,
    this.historyRevision = 0,
  });

  final List<NotebookHistoryEntry> history;
  final InputMode mode;
  final bool paletteOpen;

  /// Brief bottom/top flash copy (freeze ok, empty draft, …).
  final String? statusFlash;

  /// Bumps when history grows so the shell can scroll to end.
  final int historyRevision;

  NotebookViewState copyWith({
    List<NotebookHistoryEntry>? history,
    InputMode? mode,
    bool? paletteOpen,
    String? statusFlash,
    bool clearStatusFlash = false,
    int? historyRevision,
  }) {
    return NotebookViewState(
      history: history ?? this.history,
      mode: mode ?? this.mode,
      paletteOpen: paletteOpen ?? this.paletteOpen,
      statusFlash:
          clearStatusFlash ? null : (statusFlash ?? this.statusFlash),
      historyRevision: historyRevision ?? this.historyRevision,
    );
  }
}

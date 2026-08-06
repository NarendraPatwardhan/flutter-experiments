// Notebook model — machine notebook (docs/ui-northstar.md).

import '../vt/frame.dart';

/// Active input mode on the bottom surface.
enum InputMode {
  /// Keys go to the live Ghostty / AgentOS terminal.
  terminal,

  /// Natural-language composer on the same machine.
  naturalLanguage,
}

/// User message on the timeline.
class UserMessage {
  UserMessage({
    required this.id,
    required this.text,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String text;
  final DateTime at;
}

/// Agent turn stub / blocks on the timeline (H1: stub text only).
class AgentTurn {
  AgentTurn({
    required this.id,
    required this.summary,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String summary;
  final DateTime at;
}

/// Frozen terminal snapshot (completed / left terminal cell).
class FrozenTerminal {
  FrozenTerminal({
    required this.id,
    required this.frame,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final VtFrame frame;
  final DateTime at;
}

/// Timeline entry above the active surface (oldest → newest).
sealed class TimelineEntry {
  const TimelineEntry();
  String get id;
}

class UserMessageEntry extends TimelineEntry {
  const UserMessageEntry(this.message);
  final UserMessage message;
  @override
  String get id => message.id;
}

class AgentTurnEntry extends TimelineEntry {
  const AgentTurnEntry(this.turn);
  final AgentTurn turn;
  @override
  String get id => turn.id;
}

class FrozenTerminalEntry extends TimelineEntry {
  const FrozenTerminalEntry(this.cell);
  final FrozenTerminal cell;
  @override
  String get id => cell.id;
}

/// Bottom-bar hint row.
class HintItem {
  const HintItem({required this.keyLabel, required this.action});
  final String keyLabel;
  final String action;
}

/// Immutable UI snapshot for the shell.
class NotebookViewState {
  const NotebookViewState({
    this.timeline = const [],
    this.mode = InputMode.terminal,
    this.paletteOpen = false,
    this.statusFlash,
    this.timelineRevision = 0,
  });

  final List<TimelineEntry> timeline;
  final InputMode mode;
  final bool paletteOpen;
  final String? statusFlash;
  final int timelineRevision;

  NotebookViewState copyWith({
    List<TimelineEntry>? timeline,
    InputMode? mode,
    bool? paletteOpen,
    String? statusFlash,
    bool clearStatusFlash = false,
    int? timelineRevision,
  }) {
    return NotebookViewState(
      timeline: timeline ?? this.timeline,
      mode: mode ?? this.mode,
      paletteOpen: paletteOpen ?? this.paletteOpen,
      statusFlash:
          clearStatusFlash ? null : (statusFlash ?? this.statusFlash),
      timelineRevision: timelineRevision ?? this.timelineRevision,
    );
  }
}

/// True if the frame has any printable content (not blank grid).
bool frameHasInk(VtFrame frame) {
  for (final c in frame.cells) {
    if (c.text.isNotEmpty) return true;
  }
  return false;
}

// Notebook model — machine notebook (docs/ui-northstar.md).

/// Active input mode on the bottom surface.
enum InputMode {
  /// Keys go to the live Ghostty / AgentOS terminal.
  terminal,

  /// Natural-language composer on the same machine.
  naturalLanguage,
}

/// User message recorded in the timeline.
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

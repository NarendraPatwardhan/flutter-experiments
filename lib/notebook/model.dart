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

/// Text of row [y] (0-based), trailing spaces stripped.
String frameRowText(VtFrame frame, int y) {
  final cols = frame.cols;
  if (cols <= 0 || y < 0 || y >= frame.rows) return '';
  final base = y * cols;
  final buf = StringBuffer();
  for (var x = 0; x < cols; x++) {
    buf.write(frame.cells[base + x].text);
  }
  return buf.toString().replaceAll(RegExp(r'\s+$'), '');
}

/// True if the row is only a shell prompt waiting for input (`$`, `#`, …).
bool frameRowIsBarePrompt(VtFrame frame, int y) {
  final t = frameRowText(frame, y).trim();
  if (t.isEmpty) return true;
  // Bare prompt only — keep `$ pwd` / `# ls` (prompt + command).
  return RegExp(r'^[\$#%❯>]{1,3}$').hasMatch(t);
}

/// 1-based count of rows that have ink (at least 1 if any ink).
int frameUsedRows(VtFrame frame) {
  var last = -1;
  final cols = frame.cols;
  if (cols <= 0) return 0;
  for (var y = 0; y < frame.rows; y++) {
    final base = y * cols;
    for (var x = 0; x < cols; x++) {
      if (frame.cells[base + x].text.isNotEmpty) {
        last = y;
        break;
      }
    }
  }
  return last < 0 ? 0 : last + 1;
}

/// Drop trailing bare-prompt / blank lines so freezes do not end on a lonely `$`.
int frameUsedRowsForFreeze(VtFrame frame) {
  var used = frameUsedRows(frame);
  while (used > 1 && frameRowIsBarePrompt(frame, used - 1)) {
    used -= 1;
  }
  // If everything was bare prompts, keep one row of real content if any.
  if (used <= 0) return frameUsedRows(frame);
  return used;
}

/// Immutable timeline freeze: no cursor, no trailing `$`, cropped to content.
VtFrame frameForTimelineFreeze(VtFrame src) {
  final used = frameUsedRowsForFreeze(src);
  if (used <= 0) {
    return src.clone().copyWithMeta(
      cursorVisible: false,
      clearCursorPos: true,
      clearCursorColor: true,
    );
  }
  final cols = src.cols;
  final n = used * cols;
  final cells =
      List<VtCell>.of(src.cells.sublist(0, n.clamp(0, src.cells.length)));
  while (cells.length < n) {
    cells.add(const VtCell());
  }
  return VtFrame(
    cols: cols,
    rows: used,
    cells: cells,
    background: src.background,
    foreground: src.foreground,
    cursorColor: null,
    cursorX: null,
    cursorY: null,
    cursorVisible: false,
    cursorStyle: src.cursorStyle,
    cursorBlink: false,
    cursorOnWideTail: false,
    dirty: VtDirtyKind.full,
    dirtyRows: null,
  );
}

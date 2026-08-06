import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';
import 'cell_frame.dart';

/// Outlined user turn — stacks just above the active cell.
class UserMessageCell extends StatelessWidget {
  const UserMessageCell({
    super.key,
    required this.message,
    this.fontFamily,
  });

  final UserMessage message;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: NotebookCellFrame(
        kindLabel: 'you',
        active: false,
        expandBody: false,
        metaRight: NotebookChrome.formatTime(message.at),
        fontFamily: fam,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SelectableText(
            message.text,
            style: NotebookChrome.mono(fam, size: 13, height: 1.35),
          ),
        ),
      ),
    );
  }
}

/// Outlined agent turn (H1 stub).
class AgentTurnCell extends StatelessWidget {
  const AgentTurnCell({
    super.key,
    required this.turn,
    this.fontFamily,
  });

  final AgentTurn turn;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: NotebookCellFrame(
        kindLabel: 'agent',
        active: false,
        expandBody: false,
        metaRight: NotebookChrome.formatTime(turn.at),
        fontFamily: fam,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SelectableText(
            turn.summary,
            style: NotebookChrome.mono(
              fam,
              size: 13,
              height: 1.35,
              color: VtTheme.chromeDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// History: reverse list so newest sits on the bottom of this pane
/// (glued to the active cell). Empty space stays above the oldest cell.
class TimelinePane extends StatelessWidget {
  const TimelinePane({
    super.key,
    required this.entries,
    required this.scrollController,
    this.fontFamily,
  });

  final List<TimelineEntry> entries;
  final ScrollController scrollController;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.expand();

    // reverse: true → first child sits at the visual bottom of the pane.
    final visual = entries.reversed.toList(growable: false);

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      itemCount: visual.length,
      itemBuilder: (context, i) {
        final e = visual[i];
        return switch (e) {
          UserMessageEntry(:final message) => UserMessageCell(
              message: message,
              fontFamily: fontFamily,
            ),
          AgentTurnEntry(:final turn) => AgentTurnCell(
              turn: turn,
              fontFamily: fontFamily,
            ),
        };
      },
    );
  }
}

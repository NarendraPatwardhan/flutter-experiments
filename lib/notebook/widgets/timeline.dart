import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';

/// Compact user turn — stacks just above the active surface.
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              NotebookChrome.modeChip('you', fam, emphasize: true),
              const Spacer(),
              Text(
                NotebookChrome.formatTime(message.at),
                style: NotebookChrome.dim(fam, size: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            message.text,
            style: NotebookChrome.mono(fam, size: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Agent turn (H1 stub).
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              NotebookChrome.modeChip('agent', fam),
              const Spacer(),
              Text(
                NotebookChrome.formatTime(turn.at),
                style: NotebookChrome.dim(fam, size: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            turn.summary,
            style: NotebookChrome.mono(
              fam,
              size: 13,
              height: 1.35,
              color: VtTheme.chromeDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// History column: content-sized cells, list reversed so newest sits on bottom
/// of this region (glued to the active surface). Empty space stays above.
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
      padding: EdgeInsets.zero,
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

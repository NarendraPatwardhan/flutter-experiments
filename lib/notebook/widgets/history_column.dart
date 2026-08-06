import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../document.dart';
import 'cell_chrome.dart';
import 'frozen_terminal_surface.dart';

/// Reverse-glued history — notebook-level scroll only (no per-cell scroll).
class HistoryColumn extends StatelessWidget {
  const HistoryColumn({
    super.key,
    required this.cells,
    required this.scrollController,
    required this.metrics,
  });

  final List<NotebookCell> cells;
  final ScrollController scrollController;
  final VtMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.expand();

    final fam = metrics.fontFamily;
    final visual = cells.reversed.toList(growable: false);

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.only(top: 8),
      // Allow scroll even when content is short (trackpad habit).
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      itemCount: visual.length,
      itemBuilder: (context, i) {
        final c = visual[i];
        return switch (c) {
          TerminalFreezeCell() => FrozenTerminalSurface(
              cell: c,
              metrics: metrics,
            ),
          UserMessageCell() => _TextHistoryCell(
              kind: 'you',
              text: c.text,
              at: c.at,
              fontFamily: fam,
            ),
          AgentTurnCell() => _TextHistoryCell(
              kind: 'agent',
              text: c.summary,
              at: c.at,
              fontFamily: fam,
              dimBody: true,
            ),
        };
      },
    );
  }
}

class _TextHistoryCell extends StatelessWidget {
  const _TextHistoryCell({
    required this.kind,
    required this.text,
    required this.at,
    this.fontFamily,
    this.dimBody = false,
  });

  final String kind;
  final String text;
  final DateTime at;
  final String? fontFamily;
  final bool dimBody;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CellChrome(
        kindLabel: kind,
        metaRight: CellChrome.formatTime(at),
        fontFamily: fontFamily,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SelectableText(
            text,
            style: CellChrome.mono(
              fontFamily,
              size: 13,
              height: 1.35,
              color: dimBody ? VtTheme.chromeDim : VtTheme.chromeFg,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';
import 'cell_frame.dart';

String formatNotebookTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// History terminal snapshot (immutable grid).
class FrozenTerminalCellView extends StatelessWidget {
  const FrozenTerminalCellView({
    super.key,
    required this.cell,
    required this.metrics,
    this.maxHeight = 280,
  });

  final FrozenTerminalCell cell;
  final VtMetrics metrics;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final frame = cell.frame;
    const pad = EdgeInsets.fromLTRB(8, 4, 8, 8);
    final gridH = frame.rows * metrics.cellHeight + pad.vertical;
    final needsScroll = gridH > maxHeight - NotebookCellFrame.headerHeight;
    final bodyH = (needsScroll
            ? maxHeight - NotebookCellFrame.headerHeight
            : gridH)
        .clamp(48.0, maxHeight);

    return SizedBox(
      height: bodyH + NotebookCellFrame.headerHeight,
      child: NotebookCellFrame(
        kindLabel: cell.label ?? 'terminal',
        metaRight:
            '${formatNotebookTime(cell.frozenAt)} · ${frame.cols}×${frame.rows}',
        active: false,
        fontFamily: metrics.fontFamily,
        child: ColoredBox(
          color: frame.background,
          child: ClipRect(
            child: SingleChildScrollView(
              physics: needsScroll
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: SizedBox(
                height: gridH,
                width: double.infinity,
                child: VtView(
                  frame: frame,
                  metrics: metrics,
                  padding: pad,
                  focused: false,
                  blinkPhase: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// User ask in history.
class UserMessageCellView extends StatelessWidget {
  const UserMessageCellView({
    super.key,
    required this.cell,
    this.fontFamily,
  });

  final UserMessageCell cell;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    // Intrinsic height: header + padded text (no Expanded parent).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VtTheme.background,
        border: Border(
          top: const BorderSide(color: VtTheme.chromeBorder),
          bottom: const BorderSide(color: VtTheme.chromeBorder),
          left: BorderSide(color: VtTheme.chromeAccent, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: NotebookCellFrame.headerHeight,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: VtTheme.chromeBg,
                border: Border(
                  bottom: BorderSide(color: VtTheme.chromeBorder),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    NotebookChrome.modeChip('you', fam, emphasize: true),
                    const Spacer(),
                    Text(
                      formatNotebookTime(cell.at),
                      style: NotebookChrome.dim(fam, size: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(
              cell.text,
              style: NotebookChrome.mono(fam, size: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet host notice in history.
class SystemNoticeCellView extends StatelessWidget {
  const SystemNoticeCellView({
    super.key,
    required this.cell,
    this.fontFamily,
  });

  final SystemNoticeCell cell;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: VtTheme.chromeBg,
        border: Border(
          top: BorderSide(color: VtTheme.chromeBorder),
          bottom: BorderSide(color: VtTheme.chromeBorder),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          cell.message,
          style: NotebookChrome.dim(fam, size: 12).copyWith(height: 1.3),
        ),
      ),
    );
  }
}

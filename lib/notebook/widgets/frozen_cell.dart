import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';

/// Immutable terminal snapshot in the history stack (crisp 1:1 cells, no scale).
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
    final needsScroll = gridH > maxHeight;
    final viewportH = needsScroll ? maxHeight : gridH.clamp(48.0, maxHeight);
    final time = formatNotebookTime(cell.frozenAt);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: VtTheme.chromeBorder, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 22,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  NotebookChrome.modeChip(
                    cell.label ?? 'terminal',
                    metrics.fontFamily,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: NotebookChrome.dim(metrics.fontFamily, size: 10),
                  ),
                  const Spacer(),
                  Text(
                    '${frame.cols}×${frame.rows}',
                    style: NotebookChrome.dim(metrics.fontFamily, size: 10),
                  ),
                ],
              ),
            ),
          ),
          ColoredBox(
            color: frame.background,
            child: SizedBox(
              height: viewportH,
              width: double.infinity,
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
        ],
      ),
    );
  }
}

/// Shared timestamp for history chrome.
String formatNotebookTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF121412),
        border: Border(
          bottom: BorderSide(color: VtTheme.chromeBorder, width: 1),
          left: BorderSide(color: VtTheme.chromeAccent, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NotebookChrome.modeChip('you', fam, emphasize: true),
                const Spacer(),
                Text(
                  formatNotebookTime(cell.at),
                  style: NotebookChrome.dim(fam, size: 10),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              cell.text,
              style: NotebookChrome.mono(fam, size: 13, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet host notice.
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
          bottom: BorderSide(color: VtTheme.chromeBorder, width: 1),
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

import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../document.dart';
import 'cell_chrome.dart';

/// Frozen terminal history cell — **full content height**.
///
/// No internal scroll: tall freezes grow and the notebook [HistoryColumn]
/// ListView scrolls the page.
class FrozenTerminalSurface extends StatelessWidget {
  const FrozenTerminalSurface({
    super.key,
    required this.cell,
    required this.metrics,
  });

  final TerminalFreezeCell cell;
  final VtMetrics metrics;

  static const EdgeInsets pad = EdgeInsets.fromLTRB(8, 6, 8, 6);

  @override
  Widget build(BuildContext context) {
    final frame = cell.frame;
    final fam = metrics.fontFamily;
    final rows = frame.rows < 1 ? 1 : frame.rows;
    final contentH = rows * metrics.cellHeight + pad.vertical;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CellChrome(
        kindLabel: 'terminal',
        metaRight: CellChrome.formatTime(cell.at),
        fontFamily: fam,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 400.0;
            return SizedBox(
              width: w,
              height: contentH,
              child: ClipRect(
                child: CustomPaint(
                  size: Size(w, contentH),
                  painter: VtPainter(
                    frame: frame,
                    metrics: metrics,
                    padding: pad,
                    focused: false,
                    blinkPhase: false,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

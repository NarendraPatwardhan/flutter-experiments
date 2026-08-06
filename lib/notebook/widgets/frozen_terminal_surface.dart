import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../document.dart';
import 'cell_chrome.dart';

/// Frozen terminal — hard-cap + **guaranteed** internal scroll when tall.
class FrozenTerminalSurface extends StatelessWidget {
  const FrozenTerminalSurface({
    super.key,
    required this.cell,
    required this.metrics,
  });

  final TerminalFreezeCell cell;
  final VtMetrics metrics;

  /// ~8 mono rows before scroll (forces in-cell scroll for long freezes).
  static const double maxBodyPx = 140;
  static const EdgeInsets pad = EdgeInsets.fromLTRB(8, 4, 8, 4);

  @override
  Widget build(BuildContext context) {
    final frame = cell.frame;
    final fam = metrics.fontFamily;
    final rows = frame.rows < 1 ? 1 : frame.rows;
    final contentH = rows * metrics.cellHeight + pad.vertical;
    final bodyH =
        contentH.clamp(metrics.cellHeight + pad.vertical, maxBodyPx);
    final needsScroll = contentH > bodyH + 0.5;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CellChrome(
        kindLabel: 'terminal',
        metaRight: CellChrome.formatTime(cell.at),
        fontFamily: fam,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            // Explicit size so CustomPaint participates in scroll extent.
            final paint = SizedBox(
              width: w,
              height: contentH,
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
            );

            return SizedBox(
              height: bodyH,
              width: w,
              child: ClipRect(
                child: needsScroll
                    ? ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: true,
                        ),
                        child: SingleChildScrollView(
                          primary: false,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: ClampingScrollPhysics(),
                          ),
                          child: paint,
                        ),
                      )
                    : paint,
              ),
            );
          },
        ),
      ),
    );
  }
}

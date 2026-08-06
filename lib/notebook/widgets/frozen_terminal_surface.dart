import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../document.dart';
import 'cell_chrome.dart';

/// Frozen terminal — hard-cap + internal scroll; fully clipped to rounded cell.
class FrozenTerminalSurface extends StatelessWidget {
  const FrozenTerminalSurface({
    super.key,
    required this.cell,
    required this.metrics,
  });

  final TerminalFreezeCell cell;
  final VtMetrics metrics;

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
            final w = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 400.0;
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

            // ClipRect + Material so scroll paint never escapes the cell.
            return SizedBox(
              height: bodyH,
              width: w,
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: needsScroll
                    ? SingleChildScrollView(
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        child: paint,
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

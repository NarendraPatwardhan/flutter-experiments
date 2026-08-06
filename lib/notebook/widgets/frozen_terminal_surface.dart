import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../document.dart';
import 'cell_chrome.dart';

/// Frozen terminal history cell — docs/notebook-components.md §4.6.
///
/// Always overflow-safe: hard-cap body + **internal** scroll when needed.
class FrozenTerminalSurface extends StatelessWidget {
  const FrozenTerminalSurface({
    super.key,
    required this.cell,
    required this.metrics,
  });

  final TerminalFreezeCell cell;
  final VtMetrics metrics;

  /// Paint cap (~10 rows). Longer freezes scroll inside the cell.
  static const double maxBodyPx = 180;
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

    final paint = CustomPaint(
      size: Size(double.infinity, contentH),
      painter: VtPainter(
        frame: frame,
        metrics: metrics,
        padding: pad,
        focused: false,
        blinkPhase: false,
      ),
    );

    final body = SizedBox(
      height: bodyH,
      width: double.infinity,
      child: ClipRect(
        child: needsScroll
            ? SingleChildScrollView(
                primary: false,
                physics: const ClampingScrollPhysics(),
                child: paint,
              )
            : paint,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CellChrome(
        kindLabel: 'terminal',
        active: false,
        expandBody: false,
        metaRight: CellChrome.formatTime(cell.at),
        fontFamily: fam,
        child: body,
      ),
    );
  }
}

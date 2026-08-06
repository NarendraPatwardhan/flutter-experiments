import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../chrome.dart';
import '../model.dart';
import 'cell_frame.dart';

/// Outlined frozen terminal cell — tight to content, no live cursor.
/// Tall freezes scroll **inside** the cell (not the notebook page).
class FrozenTerminalCell extends StatelessWidget {
  const FrozenTerminalCell({
    super.key,
    required this.cell,
    required this.metrics,
  });

  final FrozenTerminal cell;
  final VtMetrics metrics;

  static const double _maxBody = 160;
  static const EdgeInsets _pad = EdgeInsets.fromLTRB(8, 4, 8, 4);

  @override
  Widget build(BuildContext context) {
    final frame = cell.frame;
    final fam = metrics.fontFamily;
    final rows = frame.rows < 1 ? 1 : frame.rows;
    final contentH = rows * metrics.cellHeight + _pad.vertical;
    final bodyH = contentH.clamp(metrics.cellHeight + _pad.vertical, _maxBody);
    final needsScroll = contentH > bodyH + 0.5;

    final paint = CustomPaint(
      size: Size(double.infinity, contentH),
      painter: VtPainter(
        frame: frame,
        metrics: metrics,
        padding: _pad,
        focused: false,
        blinkPhase: false,
      ),
    );

    final body = needsScroll
        ? SizedBox(
            height: bodyH,
            width: double.infinity,
            child: ClipRect(
              child: SingleChildScrollView(
                primary: false,
                child: paint,
              ),
            ),
          )
        : SizedBox(
            height: bodyH,
            width: double.infinity,
            child: ClipRect(child: paint),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: NotebookCellFrame(
        kindLabel: 'terminal',
        active: false,
        expandBody: false,
        metaRight: NotebookChrome.formatTime(cell.at),
        fontFamily: fam,
        child: body,
      ),
    );
  }
}

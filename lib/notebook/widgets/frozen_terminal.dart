import 'package:flutter/material.dart';

import '../../vt/frame.dart';
import '../../vt/metrics.dart';
import '../../vt/painter.dart';
import '../chrome.dart';
import '../model.dart';
import 'cell_frame.dart';

/// Outlined frozen terminal cell on the timeline.
class FrozenTerminalCell extends StatelessWidget {
  const FrozenTerminalCell({
    super.key,
    required this.cell,
    required this.metrics,
  });

  final FrozenTerminal cell;
  final VtMetrics metrics;

  static const double _maxBody = 220;

  @override
  Widget build(BuildContext context) {
    final frame = cell.frame;
    final fam = metrics.fontFamily;
    final pad = const EdgeInsets.all(8);
    final gridH = frame.rows * metrics.cellHeight + pad.vertical;
    final bodyH = gridH.clamp(48.0, _maxBody);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NotebookCellFrame(
        kindLabel: 'terminal',
        active: false,
        expandBody: false,
        metaRight: NotebookChrome.formatTime(cell.at),
        fontFamily: fam,
        child: SizedBox(
          height: bodyH,
          width: double.infinity,
          child: ClipRect(
            child: CustomPaint(
              painter: VtPainter(
                frame: frame,
                metrics: metrics,
                padding: pad,
                focused: false,
                blinkPhase: false,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

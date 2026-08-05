import 'package:flutter/material.dart';

import 'frame.dart';
import 'metrics.dart';

/// Ghostty-style cell painter.
///
/// Layout rules from `src/renderer/size.zig` + `src/font/Metrics.zig` +
/// `src/renderer/cursor.zig`:
/// - Grid origin = padding; cell (x,y) at (padL + x·cellW, padT + y·cellH).
/// - Glyphs share the measured mono advance so a run of N cells is N·cellW.
/// - Baseline is [VtMetrics.topToBaseline] from the cell top.
/// - Block cursor under text (inverted glyph); bar/underline/hollow after.
class VtPainter extends CustomPainter {
  VtPainter({
    required this.frame,
    required this.metrics,
    required this.padding,
    this.focused = true,
  });

  final VtFrame frame;
  final VtMetrics metrics;
  final EdgeInsets padding;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = frame.background);

    if (frame.cols <= 0 || frame.rows <= 0) return;

    final cellW = metrics.cellWidth;
    final cellH = metrics.cellHeight;
    final origin = Offset(padding.left, padding.top);

    final gridW = frame.cols * cellW;
    final gridH = frame.rows * cellH;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(origin.dx, origin.dy, gridW, gridH));

    // --- backgrounds (full cell, Ghostty cell_bg pass) ---
    for (var y = 0; y < frame.rows; y++) {
      for (var x = 0; x < frame.cols; x++) {
        final bg = frame.cellAt(x, y).bg;
        if (bg != null && bg != frame.background) {
          canvas.drawRect(
            Rect.fromLTWH(
              origin.dx + x * cellW,
              origin.dy + y * cellH,
              cellW,
              cellH,
            ),
            Paint()..color = bg,
          );
        }
      }
    }

    final showCursor = frame.cursorVisible &&
        frame.cursorX != null &&
        frame.cursorY != null &&
        frame.cursorX! >= 0 &&
        frame.cursorY! >= 0 &&
        frame.cursorX! < frame.cols &&
        frame.cursorY! < frame.rows;

    // Unfocused → hollow block (cursor.zig).
    final cursorStyle =
        focused ? frame.cursorStyle : VtCursorStyle.blockHollow;

    // Block cursor first (under glyphs), matching Contents.setCursor.
    if (showCursor && cursorStyle == VtCursorStyle.block) {
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx + frame.cursorX! * cellW,
          origin.dy + frame.cursorY! * cellH,
          cellW,
          cellH,
        ),
        Paint()..color = frame.foreground,
      );
    }

    // --- text: same-color runs as one string (true mono packing) ---
    // cellW MUST equal the face advance; then N chars in a run span N·cellW.
    final baseStyle = metrics.style.copyWith(
      color: frame.foreground,
      letterSpacing: 0,
      wordSpacing: 0,
    );

    for (var y = 0; y < frame.rows; y++) {
      final cellTop = origin.dy + y * cellH;
      final baselineY = cellTop + metrics.topToBaseline;

      var x = 0;
      while (x < frame.cols) {
        final cell = frame.cellAt(x, y);
        if (cell.text.isEmpty) {
          x++;
          continue;
        }

        final blockHere = showCursor &&
            cursorStyle == VtCursorStyle.block &&
            frame.cursorX == x &&
            frame.cursorY == y;
        final fg = blockHere
            ? frame.background
            : (cell.fg ?? frame.foreground);

        final buf = StringBuffer(cell.text);
        var end = x + 1;
        while (end < frame.cols) {
          final next = frame.cellAt(end, y);
          if (next.text.isEmpty) break;
          final nextBlock = showCursor &&
              cursorStyle == VtCursorStyle.block &&
              frame.cursorX == end &&
              frame.cursorY == y;
          final nextFg = nextBlock
              ? frame.background
              : (next.fg ?? frame.foreground);
          if (nextFg != fg) break;
          buf.write(next.text);
          end++;
        }

        final tp = TextPainter(
          text: TextSpan(
            text: buf.toString(),
            style: baseStyle.copyWith(color: fg),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        )..layout();

        final measuredBaseline = tp.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        // Place so the string’s baseline sits on the cell baseline.
        // X = left edge of the first cell in the run (Ghostty grid_pos).
        tp.paint(
          canvas,
          Offset(
            origin.dx + x * cellW,
            baselineY - measuredBaseline,
          ),
        );

        x = end;
      }
    }

    // --- bar / underline / hollow after text ---
    if (showCursor && cursorStyle != VtCursorStyle.block) {
      final rect = Rect.fromLTWH(
        origin.dx + frame.cursorX! * cellW,
        origin.dy + frame.cursorY! * cellH,
        cellW,
        cellH,
      );
      final paint = Paint()..color = frame.foreground;
      switch (cursorStyle) {
        case VtCursorStyle.bar:
          canvas.drawRect(
            Rect.fromLTWH(
              rect.left,
              rect.top,
              metrics.cursorThickness,
              rect.height,
            ),
            paint,
          );
        case VtCursorStyle.underline:
          canvas.drawRect(
            Rect.fromLTWH(
              rect.left,
              rect.top + metrics.underlinePosition,
              rect.width,
              metrics.underlineThickness,
            ),
            paint,
          );
        case VtCursorStyle.blockHollow:
          canvas.drawRect(
            rect.deflate(0.5),
            Paint()
              ..color = frame.foreground
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        case VtCursorStyle.block:
          break;
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VtPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.metrics != metrics ||
        oldDelegate.padding != padding ||
        oldDelegate.focused != focused;
  }
}

class VtView extends StatelessWidget {
  const VtView({
    super.key,
    required this.frame,
    required this.metrics,
    this.padding = EdgeInsets.zero,
    this.focused = true,
  });

  final VtFrame frame;
  final VtMetrics metrics;
  final EdgeInsets padding;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: frame.background,
      child: CustomPaint(
        painter: VtPainter(
          frame: frame,
          metrics: metrics,
          padding: padding,
          focused: focused,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

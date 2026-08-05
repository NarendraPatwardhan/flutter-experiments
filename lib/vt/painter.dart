import 'package:flutter/material.dart';

import 'frame.dart';
import 'metrics.dart';

/// Paints a [VtFrame] with Ghostty geometry: fixed mono cells, baseline glyphs,
/// balanced padding, cursor styles from `src/renderer/cursor.zig`.
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
    final bg = Paint()..color = frame.background;
    canvas.drawRect(Offset.zero & size, bg);

    if (frame.cols <= 0 || frame.rows <= 0) return;

    final cellW = metrics.cellWidth;
    final cellH = metrics.cellHeight;
    final origin = Offset(padding.left, padding.top);

    final gridRect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      frame.cols * cellW,
      frame.rows * cellH,
    );
    canvas.save();
    canvas.clipRect(gridRect);

    // --- cell backgrounds ---
    for (var y = 0; y < frame.rows; y++) {
      for (var x = 0; x < frame.cols; x++) {
        final cellBg = frame.cellAt(x, y).bg;
        if (cellBg != null && cellBg != frame.background) {
          canvas.drawRect(
            Rect.fromLTWH(
              origin.dx + x * cellW,
              origin.dy + y * cellH,
              cellW,
              cellH,
            ),
            Paint()..color = cellBg,
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

    final cursorStyle =
        focused ? frame.cursorStyle : VtCursorStyle.blockHollow;

    if (showCursor && cursorStyle == VtCursorStyle.block) {
      final rect = Rect.fromLTWH(
        origin.dx + frame.cursorX! * cellW,
        origin.dy + frame.cursorY! * cellH,
        cellW,
        cellH,
      );
      canvas.drawRect(rect, Paint()..color = frame.foreground);
    }

    // --- glyphs: one TextPainter per run of same-colored cells on a row ---
    // Same advance as metrics.cellWidth → natural mono packing.
    final baseStyle = metrics.style.copyWith(
      color: frame.foreground,
      height: 1.0,
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

        final isBlockCursorCell = showCursor &&
            cursorStyle == VtCursorStyle.block &&
            frame.cursorX == x &&
            frame.cursorY == y;
        final fg = isBlockCursorCell
            ? frame.background
            : (cell.fg ?? frame.foreground);

        // Extend run while fg matches and cells are non-empty single-width text.
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
          // Keep runs short if a cell has multi-codepoint grapheme — still OK.
          buf.write(next.text);
          end++;
        }

        final runText = buf.toString();
        final tp = TextPainter(
          text: TextSpan(
            text: runText,
            style: baseStyle.copyWith(color: fg),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
          strutStyle: StrutStyle(
            fontFamily: metrics.fontFamily,
            fontFamilyFallback: VtMetrics.fontFamilyFallback,
            fontSize: metrics.fontSize,
            height: 1.0,
            forceStrutHeight: true,
            letterSpacing: 0,
          ),
        )..layout();

        // If the run width drifted from cellW * n (font mismatch), fall back
        // to per-cell paint so we never double-space a whole line again.
        final expected = cellW * (end - x);
        final cellLeft = origin.dx + x * cellW;
        final measuredBaseline = tp.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        final dy = baselineY - measuredBaseline;

        if ((tp.width - expected).abs() <= cellW * 0.35 || (end - x) == 1) {
          // Natural mono run — paint as one string (best look).
          // If slightly short/long, still OK; terminal grid is authoritative.
          tp.paint(canvas, Offset(cellLeft, dy));
        } else {
          // Per-cell fallback when the face is not truly mono.
          for (var cx = x; cx < end; cx++) {
            final c = frame.cellAt(cx, y);
            if (c.text.isEmpty) continue;
            final ctp = TextPainter(
              text: TextSpan(
                text: c.text,
                style: baseStyle.copyWith(color: fg),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            )..layout(maxWidth: cellW);
            final cBase = ctp.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            );
            ctp.paint(
              canvas,
              Offset(origin.dx + cx * cellW, baselineY - cBase),
            );
          }
        }

        x = end;
      }
    }

    // --- bar / underline / hollow (after text) ---
    if (showCursor && cursorStyle != VtCursorStyle.block) {
      final rect = Rect.fromLTWH(
        origin.dx + frame.cursorX! * cellW,
        origin.dy + frame.cursorY! * cellH,
        cellW,
        cellH,
      );
      final cursorPaint = Paint()..color = frame.foreground;
      switch (cursorStyle) {
        case VtCursorStyle.bar:
          canvas.drawRect(
            Rect.fromLTWH(
              rect.left,
              rect.top,
              metrics.cursorThickness,
              rect.height,
            ),
            cursorPaint,
          );
        case VtCursorStyle.underline:
          canvas.drawRect(
            Rect.fromLTWH(
              rect.left,
              rect.top + metrics.underlinePosition,
              rect.width,
              metrics.underlineThickness,
            ),
            cursorPaint,
          );
        case VtCursorStyle.blockHollow:
          canvas.drawRect(
            rect.deflate(0.5),
            Paint()
              ..color = frame.foreground
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0,
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

/// Terminal surface: font-sized grid + Ghostty padding.
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

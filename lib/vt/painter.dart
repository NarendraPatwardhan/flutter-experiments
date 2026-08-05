import 'package:flutter/material.dart';

import 'frame.dart';
import 'metrics.dart';

/// Paints a [VtFrame] using Ghostty-style geometry (`src/renderer/size.zig`,
/// `src/font/Metrics.zig`, `src/renderer/cursor.zig`).
///
/// Rules taken from Ghostty:
/// - Cell size is font-derived, never stretched to fill the surface.
/// - Leftover space is padding (balanced, top-capped).
/// - Glyphs sit on [VtMetrics.cellBaseline] from the cell bottom, left edge.
/// - Block cursor draws first (under text invert); bar/underline last.
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
    // Full surface = terminal background (padding shares bg — window-padding-color).
    final bg = Paint()..color = frame.background;
    canvas.drawRect(Offset.zero & size, bg);

    if (frame.cols <= 0 || frame.rows <= 0) return;

    final cellW = metrics.cellWidth;
    final cellH = metrics.cellHeight;
    final origin = Offset(padding.left, padding.top);

    // Clip to grid so partial cells at edges never paint.
    final gridRect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      frame.cols * cellW,
      frame.rows * cellH,
    );
    canvas.save();
    canvas.clipRect(gridRect);

    // --- backgrounds (full cell rects) ---
    for (var y = 0; y < frame.rows; y++) {
      for (var x = 0; x < frame.cols; x++) {
        final cell = frame.cellAt(x, y);
        final cellBg = cell.bg;
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

    // --- block cursor under glyphs (Ghostty: block in fg_rows[0]) ---
    final showCursor = frame.cursorVisible &&
        frame.cursorX != null &&
        frame.cursorY != null &&
        frame.cursorX! >= 0 &&
        frame.cursorY! >= 0 &&
        frame.cursorX! < frame.cols &&
        frame.cursorY! < frame.rows;

    final cursorStyle = focused
        ? frame.cursorStyle
        : VtCursorStyle.blockHollow; // unfocused → hollow (cursor.zig)

    if (showCursor && cursorStyle == VtCursorStyle.block) {
      final cx = frame.cursorX!;
      final cy = frame.cursorY!;
      final rect = Rect.fromLTWH(
        origin.dx + cx * cellW,
        origin.dy + cy * cellH,
        cellW,
        cellH,
      );
      canvas.drawRect(rect, Paint()..color = frame.foreground);
    }

    // --- glyphs on baseline ---
    final baseStyle = metrics.style.copyWith(
      color: frame.foreground,
      height: 1.0,
    );

    for (var y = 0; y < frame.rows; y++) {
      for (var x = 0; x < frame.cols; x++) {
        final cell = frame.cellAt(x, y);
        if (cell.text.isEmpty) continue;

        final isBlockCursorCell = showCursor &&
            cursorStyle == VtCursorStyle.block &&
            frame.cursorX == x &&
            frame.cursorY == y;

        final fg = isBlockCursorCell
            ? frame.background // invert under block cursor
            : (cell.fg ?? frame.foreground);

        final tp = TextPainter(
          text: TextSpan(
            text: cell.text,
            style: baseStyle.copyWith(color: fg),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        )..layout(maxWidth: cellW * 4);

        // Left of cell + baseline from bottom (not vertically centered).
        final cellLeft = origin.dx + x * cellW;
        final cellTop = origin.dy + y * cellH;
        final baselineY = cellTop + metrics.topToBaseline;
        final measuredBaseline = tp.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        final dy = baselineY - measuredBaseline;
        tp.paint(canvas, Offset(cellLeft, dy));
      }
    }

    // --- bar / underline / hollow (drawn after text) ---
    if (showCursor && cursorStyle != VtCursorStyle.block) {
      final cx = frame.cursorX!;
      final cy = frame.cursorY!;
      final rect = Rect.fromLTWH(
        origin.dx + cx * cellW,
        origin.dy + cy * cellH,
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
              ..strokeWidth = metrics.cursorThickness.clamp(1.0, 2.0),
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

/// Terminal surface: font-sized grid + Ghostty padding, not a stretched fill.
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

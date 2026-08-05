import 'package:flutter/material.dart';

import 'frame.dart';

/// Paints a [VtFrame] as a monospaced cell grid with cursor.
class VtPainter extends CustomPainter {
  VtPainter({
    required this.frame,
    this.fontSize = 13,
    this.fontFamily = 'monospace',
  });

  final VtFrame frame;
  final double fontSize;
  final String fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = frame.background;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (frame.cols <= 0 || frame.rows <= 0) return;

    final cellW = size.width / frame.cols;
    final cellH = size.height / frame.rows;

    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.0,
      color: frame.foreground,
    );

    for (var y = 0; y < frame.rows; y++) {
      for (var x = 0; x < frame.cols; x++) {
        final cell = frame.cellAt(x, y);
        final rect = Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);

        final cellBg = cell.bg;
        if (cellBg != null && cellBg != frame.background) {
          canvas.drawRect(rect, Paint()..color = cellBg);
        }

        if (cell.text.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: cell.text,
              style: textStyle.copyWith(
                color: cell.fg ?? frame.foreground,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout(maxWidth: cellW * 2);
          // Center-ish within cell (top-left with small padding).
          final dx = rect.left + (cellW - tp.width).clamp(0.0, cellW) / 2;
          final dy = rect.top + (cellH - tp.height).clamp(0.0, cellH) / 2;
          tp.paint(canvas, Offset(dx, dy));
        }
      }
    }

    if (frame.cursorVisible &&
        frame.cursorX != null &&
        frame.cursorY != null) {
      final cx = frame.cursorX!;
      final cy = frame.cursorY!;
      if (cx >= 0 && cy >= 0 && cx < frame.cols && cy < frame.rows) {
        final rect = Rect.fromLTWH(cx * cellW, cy * cellH, cellW, cellH);
        final cursorPaint = Paint()
          ..color = frame.foreground.withOpacity(0.85);
        switch (frame.cursorStyle) {
          case VtCursorStyle.bar:
            canvas.drawRect(
              Rect.fromLTWH(rect.left, rect.top, 2, rect.height),
              cursorPaint,
            );
          case VtCursorStyle.underline:
            canvas.drawRect(
              Rect.fromLTWH(
                rect.left,
                rect.bottom - 2,
                rect.width,
                2,
              ),
              cursorPaint,
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
            canvas.drawRect(rect, cursorPaint);
            // Invert glyph under block cursor if present.
            final under = frame.cellAt(cx, cy);
            if (under.text.isNotEmpty) {
              final tp = TextPainter(
                text: TextSpan(
                  text: under.text,
                  style: textStyle.copyWith(color: frame.background),
                ),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout(maxWidth: cellW * 2);
              final dx =
                  rect.left + (cellW - tp.width).clamp(0.0, cellW) / 2;
              final dy =
                  rect.top + (cellH - tp.height).clamp(0.0, cellH) / 2;
              tp.paint(canvas, Offset(dx, dy));
            }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant VtPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.fontFamily != fontFamily;
  }
}

/// Sized terminal surface that paints [frame].
class VtView extends StatelessWidget {
  const VtView({
    super.key,
    required this.frame,
    this.fontSize = 13,
  });

  final VtFrame frame;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: frame.background,
      child: CustomPaint(
        painter: VtPainter(frame: frame, fontSize: fontSize),
        child: const SizedBox.expand(),
      ),
    );
  }
}

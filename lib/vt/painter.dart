import 'package:flutter/material.dart';

import 'frame.dart';
import 'graphics.dart';
import 'image_cache.dart';
import 'metrics.dart';

/// Ghostty-style cell painter.
///
/// Layout rules from `src/renderer/size.zig` + `src/font/Metrics.zig` +
/// `src/renderer/cursor.zig`:
/// - Grid origin = padding; cell (x,y) at (padL + x·cellW, padT + y·cellH).
/// - Glyphs share the measured mono advance so a run of N cells is N·cellW.
/// - Baseline is [VtMetrics.topToBaseline] from the cell top.
/// - Block cursor under text (inverted glyph); bar/underline/hollow after.
///
/// G1 style: selection invert, bold/italic/faint, underline/strike/overline,
/// invisible skip, cursor blink phase, unfocused hollow.
/// G4: Kitty image layers (z < 0 below text, z >= 0 above).
class VtPainter extends CustomPainter {
  VtPainter({
    required this.frame,
    required this.metrics,
    required this.padding,
    this.focused = true,
    this.blinkPhase = true,
    this.imagesBelow = const [],
    this.imagesAbove = const [],
  });

  final VtFrame frame;
  final VtMetrics metrics;
  final EdgeInsets padding;
  final bool focused;

  /// When [frame.cursorBlink] is true, cursor is drawn only if [blinkPhase]
  /// is true (driven by a host ticker). Ignored when blink is off.
  final bool blinkPhase;

  /// Pre-decoded Kitty images with z < 0 (between bg and glyphs).
  final List<VtPaintImage> imagesBelow;

  /// Pre-decoded Kitty images with z >= 0 (after glyphs).
  final List<VtPaintImage> imagesAbove;

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

    final cursorColor = frame.cursorColor ?? frame.foreground;

    // --- backgrounds (full cell, Ghostty cell_bg pass) ---
    // When partial dirty is present we still paint all cells — Flutter
    // CustomPainter has no retained row buffer; dirtyRows is informational.
    for (var y = 0; y < frame.rows; y++) {
      for (var x = 0; x < frame.cols; x++) {
        final cell = frame.cellAt(x, y);
        final colors = _resolveColors(cell);
        final bg = colors.bg;
        if (bg != frame.background) {
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

    // --- Kitty images below text (z < 0) ---
    paintVtImages(canvas, imagesBelow);

    final blinkOk = !frame.cursorBlink || blinkPhase;
    final showCursor = frame.cursorVisible &&
        blinkOk &&
        frame.cursorX != null &&
        frame.cursorY != null &&
        frame.cursorX! >= 0 &&
        frame.cursorY! >= 0 &&
        frame.cursorX! < frame.cols &&
        frame.cursorY! < frame.rows;

    // Unfocused → hollow block (cursor.zig).
    final cursorStyle =
        focused ? frame.cursorStyle : VtCursorStyle.blockHollow;

    // Wide-tail cursor spans two cells when on the trailing half of a wide glyph.
    final cursorCellSpan = frame.cursorOnWideTail ? 2.0 : 1.0;

    // Block cursor first (under glyphs), matching Contents.setCursor.
    if (showCursor && cursorStyle == VtCursorStyle.block) {
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx + frame.cursorX! * cellW,
          origin.dy + frame.cursorY! * cellH,
          cellW * cursorCellSpan,
          cellH,
        ),
        Paint()..color = cursorColor,
      );
    }

    // --- text + decorations ---
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

        // Decorations still apply to empty / invisible cells with flags.
        final hasDeco = cell.underline != VtUnderline.none ||
            cell.strikethrough ||
            cell.overline;

        if (cell.text.isEmpty && !hasDeco) {
          x++;
          continue;
        }

        final colors = _resolveColors(cell);
        var fg = colors.fg;
        if (cell.faint) {
          fg = fg.withOpacity(0.5);
        }

        final blockHere = showCursor &&
            cursorStyle == VtCursorStyle.block &&
            frame.cursorX == x &&
            frame.cursorY == y;
        if (blockHere) {
          // Inverted glyph on solid block (use frame bg as ink).
          fg = frame.background;
        }

        // Coalesce a same-style run of non-empty cells for mono packing.
        // Invisible cells contribute no glyphs but still take space if we
        // painted a run — skip them individually instead.
        if (!cell.invisible && cell.text.isNotEmpty) {
          final runStyle = _textStyle(baseStyle, cell, fg);
          final buf = StringBuffer(cell.text);
          var end = x + 1;
          while (end < frame.cols) {
            final next = frame.cellAt(end, y);
            if (next.text.isEmpty || next.invisible) break;
            final nextBlock = showCursor &&
                cursorStyle == VtCursorStyle.block &&
                frame.cursorX == end &&
                frame.cursorY == y;
            if (nextBlock) break; // block cell needs inverted ink alone
            if (blockHere) break;
            if (!_sameRunStyle(cell, next)) break;
            final nextColors = _resolveColors(next);
            var nextFg = nextColors.fg;
            if (next.faint) {
              nextFg = nextFg.withOpacity(0.5);
            }
            if (nextFg != fg) break;
            buf.write(next.text);
            end++;
          }

          final tp = TextPainter(
            text: TextSpan(
              text: buf.toString(),
              style: runStyle,
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

          // Decorations for each cell in the run (underline color may differ).
          for (var cx = x; cx < end; cx++) {
            _paintDecorations(
              canvas,
              frame.cellAt(cx, y),
              origin.dx + cx * cellW,
              cellTop,
              cellW,
              cellH,
              fg,
            );
          }

          x = end;
        } else {
          // Invisible or empty-with-deco: decorations only.
          if (hasDeco) {
            _paintDecorations(
              canvas,
              cell,
              origin.dx + x * cellW,
              cellTop,
              cellW,
              cellH,
              fg,
            );
          }
          x++;
        }
      }
    }

    // --- Kitty images above text (z >= 0) ---
    paintVtImages(canvas, imagesAbove);

    // --- bar / underline / hollow after text ---
    if (showCursor && cursorStyle != VtCursorStyle.block) {
      final rect = Rect.fromLTWH(
        origin.dx + frame.cursorX! * cellW,
        origin.dy + frame.cursorY! * cellH,
        cellW * cursorCellSpan,
        cellH,
      );
      final paint = Paint()..color = cursorColor;
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
              ..color = cursorColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        case VtCursorStyle.block:
          break;
      }
    }

    canvas.restore();
  }

  /// Resolve paint fg/bg: frame defaults, then selection invert.
  /// Inverse was already applied at projection (render.dart).
  ({Color fg, Color bg}) _resolveColors(VtCell cell) {
    var fg = cell.fg ?? frame.foreground;
    var bg = cell.bg ?? frame.background;
    if (cell.selected) {
      final tmp = fg;
      fg = bg;
      bg = tmp;
    }
    return (fg: fg, bg: bg);
  }

  TextStyle _textStyle(TextStyle base, VtCell cell, Color fg) {
    return base.copyWith(
      color: fg,
      fontWeight: cell.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: cell.italic ? FontStyle.italic : FontStyle.normal,
    );
  }

  bool _sameRunStyle(VtCell a, VtCell b) {
    // Glyph style only — decorations are painted per-cell after the run.
    return a.bold == b.bold &&
        a.italic == b.italic &&
        a.faint == b.faint &&
        a.selected == b.selected;
  }

  void _paintDecorations(
    Canvas canvas,
    VtCell cell,
    double cellLeft,
    double cellTop,
    double cellW,
    double cellH,
    Color fg,
  ) {
    final thickness = metrics.decorationThickness;
    final paintColor = cell.underlineColor ?? fg;
    final paint = Paint()
      ..color = paintColor
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    if (cell.underline != VtUnderline.none) {
      final y = cellTop + metrics.underlinePosition + thickness / 2;
      _paintUnderline(
        canvas,
        cell.underline,
        cellLeft,
        y,
        cellW,
        thickness,
        paint,
      );
    }

    if (cell.strikethrough) {
      final y = cellTop + metrics.strikethroughPosition + thickness / 2;
      canvas.drawLine(
        Offset(cellLeft, y),
        Offset(cellLeft + cellW, y),
        paint..color = fg,
      );
    }

    if (cell.overline) {
      final y = cellTop + metrics.overlinePosition + thickness / 2;
      canvas.drawLine(
        Offset(cellLeft, y),
        Offset(cellLeft + cellW, y),
        paint..color = fg,
      );
    }
  }

  void _paintUnderline(
    Canvas canvas,
    VtUnderline kind,
    double left,
    double y,
    double width,
    double thickness,
    Paint paint,
  ) {
    switch (kind) {
      case VtUnderline.none:
        return;
      case VtUnderline.single:
      case VtUnderline.curly: // approximate curly as single for G1
        canvas.drawLine(Offset(left, y), Offset(left + width, y), paint);
      case VtUnderline.double_:
        canvas.drawLine(Offset(left, y), Offset(left + width, y), paint);
        canvas.drawLine(
          Offset(left, y + thickness + 1),
          Offset(left + width, y + thickness + 1),
          paint,
        );
      case VtUnderline.dotted:
        _drawDashedLine(
          canvas,
          Offset(left, y),
          Offset(left + width, y),
          paint,
          dash: thickness,
          gap: thickness,
        );
      case VtUnderline.dashed:
        _drawDashedLine(
          canvas,
          Offset(left, y),
          Offset(left + width, y),
          paint,
          dash: thickness * 3,
          gap: thickness * 2,
        );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = (Offset(dx, dy)).distance;
    if (len <= 0) return;
    final ux = dx / len;
    final uy = dy / len;
    var pos = 0.0;
    while (pos < len) {
      final end = (pos + dash).clamp(0.0, len);
      canvas.drawLine(
        Offset(a.dx + ux * pos, a.dy + uy * pos),
        Offset(a.dx + ux * end, a.dy + uy * end),
        paint,
      );
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant VtPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.metrics != metrics ||
        oldDelegate.padding != padding ||
        oldDelegate.focused != focused ||
        oldDelegate.blinkPhase != blinkPhase ||
        !identical(oldDelegate.imagesBelow, imagesBelow) ||
        !identical(oldDelegate.imagesAbove, imagesAbove);
  }
}

class VtView extends StatelessWidget {
  const VtView({
    super.key,
    required this.frame,
    required this.metrics,
    this.padding = EdgeInsets.zero,
    this.focused = true,
    this.blinkPhase = true,
    this.imagesBelow = const [],
    this.imagesAbove = const [],
  });

  final VtFrame frame;
  final VtMetrics metrics;
  final EdgeInsets padding;
  final bool focused;
  final bool blinkPhase;
  final List<VtPaintImage> imagesBelow;
  final List<VtPaintImage> imagesAbove;

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
          blinkPhase: blinkPhase,
          imagesBelow: imagesBelow,
          imagesAbove: imagesAbove,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

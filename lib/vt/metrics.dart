import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/painting.dart';

/// Font-derived terminal grid metrics, modeled on Ghostty `src/font/Metrics.zig`.
///
/// Ghostty does **not** stretch cells to fill the window. Cell width/height come
/// from the primary mono face (rounded advance / line height). Leftover surface
/// space becomes padding around the grid (`src/renderer/size.zig`).
class VtMetrics {
  const VtMetrics({
    required this.cellWidth,
    required this.cellHeight,
    required this.cellBaseline,
    required this.underlinePosition,
    required this.underlineThickness,
    required this.cursorThickness,
    required this.fontSize,
    required this.fontFamily,
    required this.style,
  });

  /// Integer pixel cell width (round of mono advance).
  final double cellWidth;

  /// Integer pixel cell height (round of line height).
  final double cellHeight;

  /// Distance from the **bottom** of the cell to the text baseline (Ghostty).
  final double cellBaseline;

  /// Distance from the **top** of the cell to the top of the underline.
  final double underlinePosition;

  final double underlineThickness;
  final double cursorThickness;
  final double fontSize;
  final String fontFamily;
  final TextStyle style;

  /// Top of cell → baseline (paint convenience).
  double get topToBaseline => cellHeight - cellBaseline;

  /// Preferred mono stack (Ghostty ships its own faces; we pick host mono).
  static const List<String> fontFamilyFallback = [
    'JetBrains Mono',
    'Cascadia Code',
    'Cascadia Mono',
    'Fira Code',
    'Fira Mono',
    'Source Code Pro',
    'IBM Plex Mono',
    'DejaVu Sans Mono',
    'Noto Sans Mono',
    'Liberation Mono',
    'Ubuntu Mono',
    'FreeMono',
    'monospace',
  ];

  /// Measure metrics for [fontSize] using a representative ASCII sample.
  ///
  /// Mirrors Ghostty: cell width from widest printable-ish mono advance
  /// (we use `M`/`W`/`0`), height from line metrics, baseline from bottom.
  factory VtMetrics.measure({
    double fontSize = 14,
    String? fontFamily,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final family = fontFamily ?? fontFamilyFallback.first;
    final style = TextStyle(
      fontFamily: family,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.0,
      // Terminals disable proportional features; keep tabular mono.
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Measure advance of dense ASCII glyphs (Ghostty measures printable ASCII).
    final samples = ['M', 'W', '0', '@', 'g', 'y', '|'];
    var maxAdvance = 0.0;
    for (final s in samples) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      )..layout();
      maxAdvance = math.max(maxAdvance, tp.width);
    }

    // Face metrics from Flutter's layout of a tall glyph string.
    final face = TextPainter(
      text: TextSpan(text: r'Hg|@$_', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout();

    // Prefer preferredLineHeight when available (includes leading).
    final faceHeight = math.max(
      face.preferredLineHeight,
      face.height,
    );
    final faceWidth = maxAdvance;

    // Ghostty: cell_width = round(face_width), cell_height = round(lineHeight).
    final cellW = math.max(1.0, faceWidth.roundToDouble());
    final cellH = math.max(1.0, faceHeight.roundToDouble());

    // Distance from bottom of painted box to baseline.
    // TextPainter: height is full glyph box; computeDistanceToActualBaseline
    // is from top of layout.
    final baselineFromTop = face.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    // Ghostty cell_baseline is from BOTTOM.
    var cellBaseline = cellH - baselineFromTop;
    // Center face in rounded cell (Metrics.zig): adjust by half rounding error.
    final faceH = faceHeight;
    cellBaseline = (cellBaseline - (cellH - faceH) / 2).roundToDouble();
    cellBaseline = cellBaseline.clamp(1.0, cellH - 1.0);

    // Underline: one thickness below baseline → from top of cell.
    final underlineThickness = math.max(1.0, (fontSize * 0.08).ceilToDouble());
    final topToBaseline = cellH - cellBaseline;
    final underlinePos = (topToBaseline + underlineThickness).clamp(
      0.0,
      cellH - underlineThickness,
    );

    // Cursor bar thickness (config-driven in Ghostty; default 1–2 device px).
    final cursorThickness = math.max(1.0, (cellW * 0.12).roundToDouble());

    return VtMetrics(
      cellWidth: cellW,
      cellHeight: cellH,
      cellBaseline: cellBaseline,
      underlinePosition: underlinePos,
      underlineThickness: underlineThickness,
      cursorThickness: cursorThickness,
      fontSize: fontSize,
      fontFamily: family,
      style: style,
    );
  }

  /// How many columns/rows fit in [size] after [explicit] padding (Ghostty grid).
  ({int cols, int rows, EdgeInsets padding}) fit(
    Size size, {
    EdgeInsets explicit = const EdgeInsets.all(8),
    int minCols = 20,
    int minRows = 8,
  }) {
    final availW = math.max(0.0, size.width - explicit.horizontal);
    final availH = math.max(0.0, size.height - explicit.vertical);
    final cols = math.max(minCols, (availW / cellWidth).floor());
    final rows = math.max(minRows, (availH / cellHeight).floor());

    // Balanced leftover after explicit padding (Padding.balanced).
    final usedW = cols * cellWidth;
    final usedH = rows * cellHeight;
    final spaceRight = math.max(0.0, availW - usedW);
    final spaceBot = math.max(0.0, availH - usedH);
    final padL = explicit.left + (spaceRight / 2).floorToDouble();
    final padR = explicit.right + (spaceRight - (spaceRight / 2).floorToDouble());
    // Cap top padding (PaddingBalance.true): avoid huge gap above first row.
    final rawTop = explicit.top + (spaceBot / 2).floorToDouble();
    final maxTop =
        (explicit.left + explicit.right + cellWidth) / 2 + explicit.top;
    final vshift = math.max(0.0, rawTop - maxTop);
    final padT = rawTop - vshift;
    final padB = explicit.bottom +
        (spaceBot - (spaceBot / 2).floorToDouble()) +
        vshift;

    return (
      cols: cols,
      rows: rows,
      padding: EdgeInsets.fromLTRB(padL, padT, padR, padB),
    );
  }
}

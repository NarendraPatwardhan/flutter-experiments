import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Font-derived terminal grid metrics — Ghostty `src/font/Metrics.zig`.
///
/// Cell size is the mono face advance and line height (rounded to whole
/// pixels). The window is never stretched into the cell size; leftover space
/// is padding (`src/renderer/size.zig`).
class VtMetrics {
  const VtMetrics({
    required this.cellWidth,
    required this.cellHeight,
    required this.cellBaseline,
    required this.underlinePosition,
    required this.underlineThickness,
    required this.strikethroughPosition,
    required this.overlinePosition,
    required this.cursorThickness,
    required this.fontSize,
    required this.fontFamily,
    required this.style,
  });

  final double cellWidth;
  final double cellHeight;

  /// Distance from the **bottom** of the cell to the alphabetic baseline.
  final double cellBaseline;

  /// Distance from the **top** of the cell to the top of the underline.
  final double underlinePosition;

  final double underlineThickness;

  /// Distance from the **top** of the cell to the top of the strikethrough.
  final double strikethroughPosition;

  /// Distance from the **top** of the cell to the top of the overline.
  final double overlinePosition;

  final double cursorThickness;
  final double fontSize;
  final String fontFamily;
  final TextStyle style;

  double get topToBaseline => cellHeight - cellBaseline;

  /// Thickness used for strikethrough / overline (same stroke as underline).
  double get decorationThickness => underlineThickness;

  /// True monospaced faces only. Avoid Propo / dual-width Nerd aliases.
  static const List<String> fontFamilyFallback = [
    'JetBrainsMono Nerd Font Mono',
    'JetBrainsMono NFM',
    'JetBrains Mono NL',
    'JetBrains Mono',
    'Liberation Mono',
    'DejaVu Sans Mono',
    'Noto Sans Mono',
    'Ubuntu Mono',
    'FreeMono',
    'Cascadia Mono',
    'Fira Mono',
    'Source Code Pro',
    'IBM Plex Mono',
    'monospace',
  ];

  /// Measure like Ghostty `Metrics.calc`:
  /// - cell_width  = round(mono advance)
  /// - cell_height = round(ascent - descent + line_gap)
  /// - cell_baseline from bottom, face centered in rounded cell
  ///
  /// Do **not** force `TextStyle.height: 1.0` when measuring — that collapses
  /// the line height to em-size and produces half-height cells. Do **not**
  /// clamp advance to 0.75em: JetBrains Mono is ~0.77em (10px @ 13pt).
  factory VtMetrics.measure({
    double fontSize = 13,
    String? fontFamily,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final family = fontFamily ?? fontFamilyFallback.first;

    // Style used for both measure and paint. No forced height — Ghostty uses
    // the face’s real line metrics.
    final style = TextStyle(
      fontFamily: family,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 0,
      wordSpacing: 0,
    );

    // --- advance: average of a long mono run (stable vs single-glyph bearing)
    const n = 64;
    final run = _layout(style, 'M' * n);
    var faceWidth = run.width / n;
    if (faceWidth <= 0) {
      faceWidth = fontSize * 0.6;
    }

    // --- line height / baseline from a tall sample (natural metrics)
    final face = _layout(style, r'Hg|$_');
    final faceHeight = math.max(face.preferredLineHeight, face.height);
    // Baseline distance from top of the layout box.
    final baselineFromTop = face.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    // Ghostty Metrics.calc: integer cell size.
    final cellW = math.max(1.0, faceWidth.roundToDouble());
    final cellH = math.max(1.0, faceHeight.roundToDouble());

    // cell_baseline is from BOTTOM. Center face in the rounded cell height
    // the same way Metrics.zig does:
    //   face_baseline (from bottom of face box) ≈ faceHeight - baselineFromTop
    //   then shift by half the rounding delta.
    final faceBaselineFromBottom = faceHeight - baselineFromTop;
    var cellBaseline =
        (faceBaselineFromBottom - (cellH - faceHeight) / 2).roundToDouble();
    cellBaseline = cellBaseline.clamp(1.0, cellH - 1.0);

    final underlineThickness = math.max(1.0, (fontSize * 0.08).ceilToDouble());
    final topToBaseline = cellH - cellBaseline;
    // Ghostty estimate: one thickness below baseline.
    final underlinePos = (topToBaseline + 1).clamp(
      0.0,
      cellH - underlineThickness,
    );
    // Strikethrough ~ mid x-height (halfway from cell top to baseline).
    final strikethroughPos = (topToBaseline * 0.55).clamp(
      0.0,
      cellH - underlineThickness,
    );
    // Overline sits near the top of the cell, one thickness in.
    final overlinePos = underlineThickness.clamp(
      0.0,
      cellH - underlineThickness,
    );
    // Cursor bar ~12% of cell width (Ghostty default thickness is config).
    final cursorThickness = math.max(1.0, (cellW * 0.12).roundToDouble());

    return VtMetrics(
      cellWidth: cellW,
      cellHeight: cellH,
      cellBaseline: cellBaseline,
      underlinePosition: underlinePos,
      underlineThickness: underlineThickness,
      strikethroughPosition: strikethroughPos,
      overlinePosition: overlinePos,
      cursorThickness: cursorThickness,
      fontSize: fontSize,
      fontFamily: family,
      style: style,
    );
  }

  static TextPainter _layout(TextStyle style, String text) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout();
  }

  /// Columns/rows that fit after [explicit] padding; remainder is balanced
  /// (Ghostty `Padding.balanced` + top-cap).
  ({int cols, int rows, EdgeInsets padding}) fit(
    Size size, {
    // Ghostty default window-padding is small (often 2).
    EdgeInsets explicit = const EdgeInsets.fromLTRB(2, 2, 2, 2),
    int minCols = 40,
    int minRows = 12,
  }) {
    final availW = math.max(0.0, size.width - explicit.horizontal);
    final availH = math.max(0.0, size.height - explicit.vertical);
    final cols = math.max(minCols, (availW / cellWidth).floor());
    final rows = math.max(minRows, (availH / cellHeight).floor());

    final usedW = cols * cellWidth;
    final usedH = rows * cellHeight;
    final spaceRight = math.max(0.0, availW - usedW);
    final spaceBot = math.max(0.0, availH - usedH);
    final halfR = (spaceRight / 2).floorToDouble();
    final halfB = (spaceBot / 2).floorToDouble();

    final rawTop = explicit.top + halfB;
    final maxTop =
        (explicit.left + explicit.right + cellWidth) / 2 + explicit.top;
    final vshift = math.max(0.0, rawTop - maxTop);

    return (
      cols: cols,
      rows: rows,
      padding: EdgeInsets.fromLTRB(
        explicit.left + halfR,
        rawTop - vshift,
        explicit.right + (spaceRight - halfR),
        explicit.bottom + (spaceBot - halfB) + vshift,
      ),
    );
  }
}

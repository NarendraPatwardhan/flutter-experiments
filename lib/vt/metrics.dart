import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Font-derived terminal grid metrics (Ghostty `src/font/Metrics.zig`).
///
/// Cell size comes from the mono face advance / line height — never from
/// stretching the window. Leftover surface space is padding.
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

  /// Distance from the **bottom** of the cell to the text baseline.
  final double cellBaseline;

  /// Distance from the **top** of the cell to the top of the underline.
  final double underlinePosition;

  final double underlineThickness;
  final double cursorThickness;
  final double fontSize;
  final String fontFamily;
  final TextStyle style;

  double get topToBaseline => cellHeight - cellBaseline;

  /// True monospaced faces only. Do **not** put Propo / variable-width Nerd
  /// families first — fontconfig often aliases "JetBrains Mono" → Propo, which
  /// makes every cell as wide as `W` and looks double-spaced.
  static const List<String> fontFamilyFallback = [
    // Explicit mono Nerd face (common on Omarchy/Arch desktops).
    'JetBrainsMono Nerd Font Mono',
    'JetBrainsMono NFM',
    'JetBrainsMonoNL Nerd Font Mono',
    // Upstream JetBrains mono (non-ligature preferred for terminals).
    'JetBrains Mono NL',
    'JetBrains Mono',
    // Portable system mono.
    'Liberation Mono',
    'DejaVu Sans Mono',
    'Noto Sans Mono',
    'Ubuntu Mono',
    'FreeMono',
    'Cascadia Mono',
    'Cascadia Code',
    'Fira Mono',
    'Fira Code',
    'Source Code Pro',
    'IBM Plex Mono',
    'monospace',
  ];

  /// Measure metrics for [fontSize].
  ///
  /// Advance is the average width of a run of `M` (Ghostty uses the mono
  /// cell width from the face). We deliberately do **not** take max(W,@,…)
  /// — that path inflates the grid when a proportional face is selected.
  factory VtMetrics.measure({
    double fontSize = 13,
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
      letterSpacing: 0,
      wordSpacing: 0,
    );

    // --- mono advance: N×'M' / N via Paragraph (stable vs TextPainter quirks)
    const n = 64;
    final advance = _measureAdvance(style, 'M' * n) / n;

    // Sanity clamp: real mono is ~0.5–0.65em. Outside that we almost certainly
    // hit a proportional face or a broken metric — fall back to 0.6em.
    final faceWidth = (advance > 0 &&
            advance >= fontSize * 0.45 &&
            advance <= fontSize * 0.75)
        ? advance
        : fontSize * 0.6;

    // --- line height / baseline from a tall sample
    final face = TextPainter(
      text: TextSpan(text: r'Hg|$_', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      strutStyle: StrutStyle(
        fontFamily: family,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: fontSize,
        height: 1.0,
        forceStrutHeight: true,
      ),
    )..layout();

    // Prefer strut / preferred line height; keep it tight (Ghostty ~ lineHeight).
    var faceHeight = math.max(face.preferredLineHeight, face.height);
    // Typical mono line height is ~1.15–1.25em; clamp runaway leading.
    if (faceHeight > fontSize * 1.45) {
      faceHeight = fontSize * 1.2;
    }
    if (faceHeight < fontSize) {
      faceHeight = fontSize * 1.15;
    }

    // Ghostty: round to whole pixels.
    final cellW = math.max(1.0, faceWidth.roundToDouble());
    final cellH = math.max(1.0, faceHeight.roundToDouble());

    final baselineFromTop = face.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    // cell_baseline is from BOTTOM (Metrics.zig).
    var cellBaseline = cellH - baselineFromTop;
    cellBaseline = (cellBaseline - (cellH - faceHeight) / 2).roundToDouble();
    cellBaseline = cellBaseline.clamp(1.0, cellH - 1.0);

    final underlineThickness = math.max(1.0, (fontSize * 0.08).ceilToDouble());
    final topToBaseline = cellH - cellBaseline;
    final underlinePos = (topToBaseline + underlineThickness).clamp(
      0.0,
      cellH - underlineThickness,
    );
    final cursorThickness = math.max(1.0, (cellW * 0.15).roundToDouble());

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

  static double _measureAdvance(TextStyle style, String sample) {
    // Prefer Paragraph maxIntrinsicWidth (stable mono advance).
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: TextDirection.ltr,
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        height: 1.0,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        letterSpacing: 0,
        wordSpacing: 0,
        height: 1.0,
      ),
    );
    builder.addText(sample);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final intrinsic = paragraph.maxIntrinsicWidth;
    if (intrinsic > 0) return intrinsic;

    // Fallback: TextPainter.
    final tp = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  /// Columns/rows that fit in [size] after [explicit] padding.
  /// Remainder (&lt; one cell) is balanced padding — Ghostty `Padding.balanced`.
  ({int cols, int rows, EdgeInsets padding}) fit(
    Size size, {
    EdgeInsets explicit = const EdgeInsets.fromLTRB(4, 2, 4, 2),
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

    // PaddingBalance.true: cap top so first row stays near the top edge.
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

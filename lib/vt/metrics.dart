import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Font-derived terminal grid metrics — Ghostty `src/font/Metrics.zig`.
///
/// Cell size **is** the mono face advance and line height. If [cellWidth]
/// drifts above the painted advance, per-cell paint opens a hole between
/// every glyph (and coalesced runs open a hole at every SGR style break).
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

  /// True monospaced faces only. Prefer `* Mono` / `* NFM` / `* NL` names —
  /// never Propo / dual-width Nerd aliases (those measure wide and paint narrow).
  static const List<String> fontFamilyFallback = [
    'JetBrainsMono Nerd Font Mono',
    'JetBrainsMono NFM',
    'JetBrainsMonoNL Nerd Font Mono',
    'JetBrainsMonoNL NFM',
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
  /// Do **not** force `TextStyle.height: 1.0` when measuring line height —
  /// that collapses cells. Do **not** invent advances; probe the live face.
  factory VtMetrics.measure({
    double fontSize = 13,
    String? fontFamily,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final picked = _pickMonoFamily(
      preferred: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );

    final style = TextStyle(
      fontFamily: picked.family,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 0,
      wordSpacing: 0,
    );

    // Live mono advance — single glyph and a long run must agree closely.
    final faceWidth = _monoAdvance(style);
    final face = _layout(style, r'Hg|$_');
    final faceHeight = math.max(face.preferredLineHeight, face.height);
    final baselineFromTop = face.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    // Ghostty Metrics.calc: integer cell size from unrounded face metrics.
    final cellW = math.max(1.0, faceWidth.roundToDouble());
    final cellH = math.max(1.0, faceHeight.roundToDouble());

    final faceBaselineFromBottom = faceHeight - baselineFromTop;
    var cellBaseline =
        (faceBaselineFromBottom - (cellH - faceHeight) / 2).roundToDouble();
    cellBaseline = cellBaseline.clamp(1.0, cellH - 1.0);

    final underlineThickness = math.max(1.0, (fontSize * 0.08).ceilToDouble());
    final topToBaseline = cellH - cellBaseline;
    final underlinePos = (topToBaseline + 1).clamp(
      0.0,
      cellH - underlineThickness,
    );
    final strikethroughPos = (topToBaseline * 0.55).clamp(
      0.0,
      cellH - underlineThickness,
    );
    final overlinePos = underlineThickness.clamp(
      0.0,
      cellH - underlineThickness,
    );
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
      fontFamily: picked.family,
      style: style,
    );
  }

  /// Advance width of the face used for [style] (same path as paint).
  static double advanceOf(TextStyle style) => _monoAdvance(style);

  static double _monoAdvance(TextStyle style) {
    // Prefer the tighter of single-glyph and long-run averages so a buggy
    // run metric cannot inflate cellW (which opens gaps between every glyph).
    final single = _layout(style, 'M').width;
    const n = 64;
    final run = _layout(style, 'M' * n).width / n;
    var w = single;
    if (run > 0) {
      w = math.min(w <= 0 ? run : w, run);
    }
    // Cross-check other mono keys; take the max so W/@ still fit the cell
    // without rounding *up* past what M reported by more than 0.5px.
    for (final ch in ['W', '0', '@']) {
      final cw = _layout(style, ch).width;
      if (cw > 0 && cw < w + 0.51) {
        w = math.max(w, cw);
      }
    }
    if (w <= 0) {
      w = (style.fontSize ?? 13) * 0.6;
    }
    return w;
  }

  /// Pick a family whose `i` and `M` advances nearly match (true mono).
  static ({String family}) _pickMonoFamily({
    String? preferred,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final candidates = <String>[
      if (preferred != null && preferred.isNotEmpty) preferred,
      ...fontFamilyFallback,
    ];

    String? best;
    var bestScore = double.negativeInfinity;

    for (final family in candidates) {
      final style = TextStyle(
        fontFamily: family,
        fontFamilyFallback: const ['monospace'],
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: 0,
        wordSpacing: 0,
      );
      final m = _layout(style, 'M').width;
      final i = _layout(style, 'i').width;
      final w = _layout(style, 'W').width;
      if (m <= 0) continue;
      // Mono score: i≈M≈W. Propo faces score poorly (i much narrower).
      final mono = 1.0 - ((m - i).abs() + (m - w).abs()) / m;
      // Prefer named mono faces slightly.
      final nameBonus = family.toLowerCase().contains('mono') ||
              family.toLowerCase().contains('nfm')
          ? 0.05
          : 0.0;
      // Reject obvious proportional (i less than 70% of M).
      if (i < m * 0.7) continue;
      final score = mono + nameBonus;
      if (score > bestScore) {
        bestScore = score;
        best = family;
      }
    }

    return (family: best ?? fontFamilyFallback.last);
  }

  static TextPainter _layout(TextStyle style, String text) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: null,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout(minWidth: 0, maxWidth: double.infinity);
  }

  /// Columns/rows that fit after [explicit] padding; remainder is balanced
  /// (Ghostty `Padding.balanced` + top-cap).
  ({int cols, int rows, EdgeInsets padding}) fit(
    Size size, {
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

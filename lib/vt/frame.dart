import 'dart:ui' show Color;

/// One screen cell for Flutter painting (owned Dart snapshot, no FFI).
class VtCell {
  const VtCell({
    this.text = '',
    this.fg,
    this.bg,
  });

  /// Grapheme cluster as UTF-8 decoded text, or empty for blank.
  final String text;

  /// Explicit foreground; null → use frame default.
  final Color? fg;

  /// Explicit background; null → use frame default.
  final Color? bg;

  bool get isEmpty => text.isEmpty;
}

/// Cursor visual style (matches GhosttyRenderStateCursorVisualStyle).
enum VtCursorStyle {
  bar,
  block,
  underline,
  blockHollow,
}

/// Immutable viewport snapshot for [CustomPainter].
class VtFrame {
  const VtFrame({
    required this.cols,
    required this.rows,
    required this.cells,
    required this.background,
    required this.foreground,
    this.cursorX,
    this.cursorY,
    this.cursorVisible = false,
    this.cursorStyle = VtCursorStyle.block,
  });

  final int cols;
  final int rows;

  /// Row-major cells: index = y * cols + x. Length == cols * rows.
  final List<VtCell> cells;

  final Color background;
  final Color foreground;

  final int? cursorX;
  final int? cursorY;
  final bool cursorVisible;
  final VtCursorStyle cursorStyle;

  VtCell cellAt(int x, int y) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) {
      return const VtCell();
    }
    return cells[y * cols + x];
  }

  static VtFrame empty({int cols = 80, int rows = 24}) {
    return VtFrame(
      cols: cols,
      rows: rows,
      cells: List<VtCell>.filled(cols * rows, const VtCell()),
      background: const Color(0xFF1E1E2E),
      foreground: const Color(0xFFCDD6F4),
    );
  }
}

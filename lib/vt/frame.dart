import 'dart:ui' show Color;

import 'theme.dart';

/// Underline kinds — matches GHOSTTY_SGR_UNDERLINE_*.
enum VtUnderline {
  none,
  single,
  double_,
  curly,
  dotted,
  dashed,
}

/// One screen cell for Flutter painting (owned Dart snapshot, no FFI).
class VtCell {
  const VtCell({
    this.text = '',
    this.fg,
    this.bg,
    this.bold = false,
    this.italic = false,
    this.faint = false,
    this.inverse = false,
    this.invisible = false,
    this.strikethrough = false,
    this.overline = false,
    this.underline = VtUnderline.none,
    this.underlineColor,
    this.selected = false,
  });

  /// Grapheme cluster as UTF-8 decoded text, or empty for blank.
  final String text;

  /// Resolved foreground; null → use frame default.
  final Color? fg;

  /// Resolved background; null → use frame default.
  final Color? bg;

  final bool bold;
  final bool italic;
  final bool faint;
  final bool inverse;
  final bool invisible;
  final bool strikethrough;
  final bool overline;
  final VtUnderline underline;
  final Color? underlineColor;
  final bool selected;

  bool get isEmpty => text.isEmpty;

  bool get hasDecoration =>
      strikethrough ||
      overline ||
      underline != VtUnderline.none ||
      bold ||
      italic ||
      faint ||
      inverse ||
      selected;
}

/// Cursor visual style (matches GhosttyRenderStateCursorVisualStyle).
enum VtCursorStyle {
  bar,
  block,
  underline,
  blockHollow,
}

/// Global dirty hint from render state.
enum VtDirtyKind {
  clean,
  partial,
  full,
}

/// Immutable viewport snapshot for [CustomPainter].
class VtFrame {
  const VtFrame({
    required this.cols,
    required this.rows,
    required this.cells,
    required this.background,
    required this.foreground,
    this.cursorColor,
    this.cursorX,
    this.cursorY,
    this.cursorVisible = false,
    this.cursorStyle = VtCursorStyle.block,
    this.cursorBlink = false,
    this.cursorOnWideTail = false,
    this.dirty = VtDirtyKind.full,
  });

  final int cols;
  final int rows;

  /// Row-major cells: index = y * cols + x. Length == cols * rows.
  final List<VtCell> cells;

  final Color background;
  final Color foreground;
  final Color? cursorColor;

  final int? cursorX;
  final int? cursorY;
  final bool cursorVisible;
  final VtCursorStyle cursorStyle;
  final bool cursorBlink;
  final bool cursorOnWideTail;
  final VtDirtyKind dirty;

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
      background: VtTheme.background,
      foreground: VtTheme.foreground,
      dirty: VtDirtyKind.clean,
    );
  }
}

/// Scrollbar metrics for chrome (GhosttyTerminalScrollbar).
class VtScrollbar {
  const VtScrollbar({
    required this.total,
    required this.offset,
    required this.len,
  });

  final int total;
  final int offset;
  final int len;

  double get thumbFraction => total <= 0 ? 1.0 : (len / total).clamp(0.0, 1.0);
  double get offsetFraction =>
      total <= len || total <= 0 ? 0.0 : (offset / (total - len)).clamp(0.0, 1.0);
}

/// Chrome events produced by terminal effects (queued, not during paint).
sealed class VtChromeEvent {
  const VtChromeEvent();
}

class VtChromeBell extends VtChromeEvent {
  const VtChromeBell();
}

class VtChromeTitleChanged extends VtChromeEvent {
  const VtChromeTitleChanged();
}

class VtChromePwdChanged extends VtChromeEvent {
  const VtChromePwdChanged();
}

class VtChromeClipboardWrite extends VtChromeEvent {
  const VtChromeClipboardWrite({
    required this.location,
    required this.parts,
  });

  /// 0=standard, 1=selection, 2=primary
  final int location;
  final List<({String mime, List<int> data})> parts;
}

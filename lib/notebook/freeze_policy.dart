// FreezePolicy — docs/notebook-components.md §7

import '../vt/frame.dart';

/// Pure frame transforms for terminal freezes.
abstract final class FreezePolicy {
  static bool hasInk(VtFrame frame) {
    for (final c in frame.cells) {
      if (c.text.isNotEmpty) return true;
    }
    return false;
  }

  static String rowText(VtFrame frame, int y) {
    final cols = frame.cols;
    if (cols <= 0 || y < 0 || y >= frame.rows) return '';
    final base = y * cols;
    final buf = StringBuffer();
    for (var x = 0; x < cols; x++) {
      buf.write(frame.cells[base + x].text);
    }
    return buf.toString().replaceAll(RegExp(r'\s+$'), '');
  }

  /// Bare shell prompt only (`$`, `#`, …) — not `$ pwd`.
  static bool rowIsBarePrompt(VtFrame frame, int y) {
    final t = rowText(frame, y).trim();
    if (t.isEmpty) return true;
    return RegExp(r'^[\$#%❯>]{1,3}$').hasMatch(t);
  }

  static int usedRows(VtFrame frame) {
    var last = -1;
    final cols = frame.cols;
    if (cols <= 0) return 0;
    for (var y = 0; y < frame.rows; y++) {
      final base = y * cols;
      for (var x = 0; x < cols; x++) {
        if (frame.cells[base + x].text.isNotEmpty) {
          last = y;
          break;
        }
      }
    }
    return last < 0 ? 0 : last + 1;
  }

  static int usedRowsForFreeze(VtFrame frame) {
    var used = usedRows(frame);
    while (used > 1 && rowIsBarePrompt(frame, used - 1)) {
      used -= 1;
    }
    return used <= 0 ? usedRows(frame) : used;
  }

  /// True only if freeze would keep **real** work (not display-only `$ `).
  ///
  /// Fixes empty history cells from Shift+Tab after prompt reattach.
  static bool isWorthFreezing(VtFrame frame) {
    if (!hasInk(frame)) return false;
    final used = usedRowsForFreeze(frame);
    if (used <= 0) return false;
    for (var y = 0; y < used; y++) {
      final t = rowText(frame, y).trim();
      if (t.isEmpty) continue;
      if (rowIsBarePrompt(frame, y)) continue;
      return true;
    }
    // Only bare prompts / blanks (e.g. reattached `$ `).
    return false;
  }

  /// Immutable freeze: no cursor, no trailing bare `$`, cropped to content.
  static VtFrame apply(VtFrame src) {
    final used = usedRowsForFreeze(src);
    if (used <= 0) {
      return src.clone().copyWithMeta(
        cursorVisible: false,
        clearCursorPos: true,
        clearCursorColor: true,
      );
    }
    final cols = src.cols;
    final n = used * cols;
    final cells =
        List<VtCell>.of(src.cells.sublist(0, n.clamp(0, src.cells.length)));
    while (cells.length < n) {
      cells.add(const VtCell());
    }
    return VtFrame(
      cols: cols,
      rows: used,
      cells: cells,
      background: src.background,
      foreground: src.foreground,
      cursorColor: null,
      cursorX: null,
      cursorY: null,
      cursorVisible: false,
      cursorStyle: src.cursorStyle,
      cursorBlink: false,
      cursorOnWideTail: false,
      dirty: VtDirtyKind.full,
      dirtyRows: null,
    );
  }
}

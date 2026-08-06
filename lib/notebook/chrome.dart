import 'package:flutter/material.dart';

import '../vt/metrics.dart';
import '../vt/theme.dart';

/// Shared mono typography for notebook chrome.
abstract final class NotebookChrome {
  static TextStyle mono(
    String? fontFamily, {
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.0,
  }) {
    return TextStyle(
      fontFamily: fontFamily ?? 'monospace',
      fontFamilyFallback: VtMetrics.fontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      color: color ?? VtTheme.chromeFg,
      height: height,
    );
  }

  static TextStyle dim(String? fontFamily, {double size = 11}) =>
      mono(fontFamily, size: size, color: VtTheme.chromeDim);

  static TextStyle accent(String? fontFamily, {double size = 12}) => mono(
        fontFamily,
        size: size,
        color: VtTheme.chromeAccent,
        weight: FontWeight.w600,
      );

  static Widget modeChip(
    String label,
    String? fontFamily, {
    bool emphasize = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: emphasize ? const Color(0x1A7CDE9A) : Colors.transparent,
        border: Border.all(
          color: emphasize ? VtTheme.chromeAccent : VtTheme.chromeBorder,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: mono(
          fontFamily,
          size: 10,
          color: emphasize ? VtTheme.chromeAccent : VtTheme.chromeDim,
          weight: FontWeight.w500,
        ),
      ),
    );
  }

  static String formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

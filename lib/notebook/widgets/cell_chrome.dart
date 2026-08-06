import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/theme.dart';

/// Universal cell outline — docs/notebook-components.md §4.1.
///
/// GrokNight paper-thin borders: history slightly clearer; active melts into
/// canvas with a quieter focused stroke (no neon green box).
class CellChrome extends StatelessWidget {
  const CellChrome({
    super.key,
    required this.kindLabel,
    required this.child,
    this.metaRight,
    this.active = false,
    this.expandBody = true,
    this.fontFamily,
  });

  final String kindLabel;
  final Widget child;
  final String? metaRight;
  final bool active;
  final bool expandBody;
  final String? fontFamily;

  static const double headerHeight = 24;

  static TextStyle _mono(
    String? fam, {
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.0,
  }) {
    return TextStyle(
      fontFamily: fam ?? 'monospace',
      fontFamilyFallback: VtMetrics.fontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      color: color ?? VtTheme.chromeFg,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final border = active ? VtTheme.chromeBorderActive : VtTheme.chromeBorderHistory;
    final width = active ? 1.0 : 1.0;

    final header = SizedBox(
      height: headerHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? VtTheme.background : VtTheme.cellHeaderBg,
          border: Border(
            bottom: BorderSide(color: border.withOpacity(0.85), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _KindChip(label: kindLabel, active: active, fontFamily: fam),
              const Spacer(),
              if (metaRight != null && metaRight!.isNotEmpty)
                Text(
                  metaRight!,
                  style: _mono(fam, size: 10, color: VtTheme.chromeDim),
                ),
            ],
          ),
        ),
      ),
    );

    final body = expandBody
        ? Expanded(child: ClipRect(child: child))
        : ClipRect(child: child);

    return Container(
      decoration: BoxDecoration(
        color: active ? VtTheme.background : VtTheme.cellHistoryBg,
        border: Border.all(color: border, width: width),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
        children: [
          header,
          body,
        ],
      ),
    );
  }

  static String formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static TextStyle mono(
    String? fam, {
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.0,
  }) =>
      _mono(fam, size: size, color: color, weight: weight, height: height);

  static TextStyle dim(String? fam, {double size = 11}) =>
      _mono(fam, size: size, color: VtTheme.chromeDim);

  static TextStyle accent(String? fam, {double size = 12}) => _mono(
        fam,
        size: size,
        color: VtTheme.chromeAccent,
        weight: FontWeight.w600,
      );
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.active,
    this.fontFamily,
  });

  final String label;
  final bool active;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    // Quiet chip: hairline border, no mint fill.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? VtTheme.chromeBorderActive : VtTheme.chromeBorder,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: CellChrome.mono(
          fontFamily,
          size: 10,
          color: active ? VtTheme.chromeFg : VtTheme.chromeDim,
          weight: FontWeight.w500,
        ),
      ),
    );
  }
}

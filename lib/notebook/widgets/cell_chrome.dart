import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/theme.dart';

/// History cell — rounded outline via [Material] shape (reliable corner arcs).
class CellChrome extends StatelessWidget {
  const CellChrome({
    super.key,
    required this.kindLabel,
    required this.child,
    this.metaRight,
    this.expandBody = false,
    this.fontFamily,
  });

  final String kindLabel;
  final Widget child;
  final String? metaRight;
  final bool expandBody;
  final String? fontFamily;

  static const double headerHeight = 22;
  static const double radius = 8;

  static TextStyle mono(
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

  static TextStyle dim(String? fam, {double size = 11}) =>
      mono(fam, size: size, color: VtTheme.chromeDim);

  static TextStyle accent(String? fam, {double size = 12}) => mono(
        fam,
        size: size,
        color: VtTheme.chromeFg,
        weight: FontWeight.w600,
      );

  static String formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final role = VtTheme.roleAccent(kindLabel);
    final border = VtTheme.chromeBorderHistory;
    final r = BorderRadius.circular(radius);

    final header = SizedBox(
      height: headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        child: Row(
          children: [
            Text(
              '· ',
              style: mono(fam, size: 12, color: role, weight: FontWeight.w600),
            ),
            Text(
              kindLabel,
              style: mono(fam, size: 11, color: role, weight: FontWeight.w500),
            ),
            const Spacer(),
            if (metaRight != null && metaRight!.isNotEmpty)
              Text(
                metaRight!,
                style: mono(fam, size: 10, color: VtTheme.chromeMuted),
              ),
          ],
        ),
      ),
    );

    final body = expandBody
        ? Expanded(child: ClipRect(child: child))
        : ClipRect(child: child);

    // Material + shape: border and clip share the same rounded rect so
    // top corners are not squared off by child paint.
    return Material(
      color: VtTheme.cellHistoryBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
        children: [
          header,
          Divider(height: 1, thickness: 1, color: border),
          body,
        ],
      ),
    );
  }
}

/// Active bottom composer — all four corners rounded; mode on bottom rail.
class ActiveComposerChrome extends StatelessWidget {
  const ActiveComposerChrome({
    super.key,
    required this.modeKind,
    required this.child,
    this.focused = true,
    this.fontFamily,
  });

  final String modeKind;
  final Widget child;
  final bool focused;
  final String? fontFamily;

  static const double footerHeight = 22;
  static const double radius = 10;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final border = VtTheme.activeBorder(modeKind, focused: focused);
    final r = BorderRadius.circular(radius);
    final side = BorderSide(color: border, width: focused ? 1.5 : 1.25);

    return Material(
      color: VtTheme.background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: side,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Clip content so VT/grid never paints into the corner arcs.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius - 1),
                topRight: Radius.circular(radius - 1),
              ),
              clipBehavior: Clip.hardEdge,
              child: child,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: border, width: 1)),
            ),
            child: SizedBox(
              height: footerHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    modeKind,
                    style: CellChrome.mono(
                      fam,
                      size: 11,
                      color: focused
                          ? VtTheme.chromeFg.withOpacity(0.8)
                          : VtTheme.chromeMuted,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

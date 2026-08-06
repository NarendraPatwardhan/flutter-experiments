import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/theme.dart';

/// History cell — uniform rounded stroke + quiet role text (no square chips).
///
/// Left accent is painted *inside* ClipRRect so top corners stay round.
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
        padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
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

    // ClipRRect first so ALL corners round; border is uniform 1px.
    // Accent bar is an *inner* strip (not a thick left BorderSide — that
    // square-off the top-left/bottom-left radius in Flutter).
    return ClipRRect(
      borderRadius: r,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VtTheme.cellHistoryBg,
          borderRadius: r,
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
          children: [
            header,
            Divider(
              height: 1,
              thickness: 1,
              color: border.withOpacity(0.65),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

/// Active bottom composer — rounded box, neutral border, mode on bottom rail.
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
  static const double radius = 8;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final border = VtTheme.activeBorder(modeKind, focused: focused);
    final r = BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: r,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VtTheme.background,
          borderRadius: r,
          border: Border.all(color: border, width: focused ? 1.25 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ClipRect(child: child)),
            SizedBox(
              height: footerHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: border.withOpacity(0.85)),
                  ),
                ),
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
                            ? VtTheme.chromeFg.withOpacity(0.75)
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
      ),
    );
  }
}

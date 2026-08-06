import 'package:flutter/material.dart';

import '../../vt/metrics.dart';
import '../../vt/theme.dart';

/// History cell chrome — Grok-style role distinction without boxed chips.
///
/// Left semantic accent bar + plain label (bullet language of Grok scrollback).
/// Paper-thin outer border; content always clipped.
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
        color: VtTheme.chromeAccent,
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

    final header = SizedBox(
      height: headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            // Grok-like bullet: solid glyph, role color — no square chip.
            Text(
              '● ',
              style: mono(fam, size: 10, color: role, weight: FontWeight.w600),
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

    return Container(
      decoration: BoxDecoration(
        color: VtTheme.cellHistoryBg,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: role.withOpacity(0.9), width: 3),
          top: BorderSide(color: border),
          right: BorderSide(color: border),
          bottom: BorderSide(color: border),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
        children: [
          header,
          Divider(height: 1, thickness: 1, color: border.withOpacity(0.7)),
          body,
        ],
      ),
    );
  }
}

/// Active bottom composer — rounded, semantic border, mode on bottom edge.
///
/// Mirrors Grok prompt chrome: ╭─╮ box, model/mode caption on the bottom rail.
class ActiveComposerChrome extends StatelessWidget {
  const ActiveComposerChrome({
    super.key,
    required this.modeKind,
    required this.child,
    this.focused = true,
    this.fontFamily,
  });

  /// `terminal` | `ask` (drives semantic border + caption).
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
    final role = VtTheme.roleAccent(modeKind);

    return Container(
      decoration: BoxDecoration(
        color: VtTheme.background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: focused ? 1.25 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ClipRect(child: child)),
          // Bottom rail: mode sits on the border like Grok model caption.
          SizedBox(
            height: footerHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: border.withOpacity(0.9)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Text(
                      modeKind,
                      style: CellChrome.mono(
                        fam,
                        size: 11,
                        color: role.withOpacity(focused ? 0.9 : 0.55),
                        weight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

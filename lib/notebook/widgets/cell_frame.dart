import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Outlined notebook cell — same box chrome for history and active.
class NotebookCellFrame extends StatelessWidget {
  const NotebookCellFrame({
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

  static const double headerHeight = 26;

  /// Shared outline for every cell (active uses thicker + left accent).
  static const Color outline = Color(0xFF4A4A4A);

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;

    final header = SizedBox(
      height: headerHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: VtTheme.chromeBg,
          border: Border(
            bottom: BorderSide(color: outline, width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              NotebookChrome.modeChip(
                kindLabel,
                fam,
                emphasize: active,
              ),
              const Spacer(),
              if (metaRight != null && metaRight!.isNotEmpty)
                Text(
                  metaRight!,
                  style: NotebookChrome.dim(fam, size: 10),
                ),
            ],
          ),
        ),
      ),
    );

    final body = expandBody ? Expanded(child: child) : child;

    // Container (not DecoratedBox+Clip) so the full rectangle border paints
    // the same way for tall active cells and short history cells.
    return Container(
      decoration: BoxDecoration(
        color: VtTheme.background,
        border: Border(
          top: BorderSide(color: outline, width: active ? 1.5 : 1),
          right: BorderSide(color: outline, width: active ? 1.5 : 1),
          bottom: BorderSide(color: outline, width: active ? 1.5 : 1),
          left: BorderSide(
            color: active ? VtTheme.chromeAccent : outline,
            width: active ? 2.5 : 1,
          ),
        ),
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
}

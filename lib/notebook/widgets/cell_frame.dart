import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Outlined notebook cell. Parent must bound height when [expandBody] is true.
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

  static const double headerHeight = 24;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final borderColor =
        active ? VtTheme.chromeAccent.withOpacity(0.55) : VtTheme.chromeBorder;
    final borderWidth = active ? 1.25 : 1.0;

    final header = SizedBox(
      height: headerHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VtTheme.chromeBg,
          border: Border(
            bottom: BorderSide(color: VtTheme.chromeBorder),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: VtTheme.background,
        border: Border.all(color: borderColor, width: borderWidth),
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

import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Shared chrome for every notebook cell (header + body).
///
/// Parent must give a bounded height (e.g. [SizedBox]) so the body can expand.
class NotebookCellFrame extends StatelessWidget {
  const NotebookCellFrame({
    super.key,
    required this.kindLabel,
    required this.child,
    this.metaRight,
    this.active = false,
    this.accentBorder,
    this.fontFamily,
  });

  final String kindLabel;
  final Widget child;
  final String? metaRight;
  final bool active;
  final Color? accentBorder;
  final String? fontFamily;

  static const double headerHeight = 24;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final top = active ? VtTheme.chromeAccent : VtTheme.chromeBorder;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: VtTheme.background,
        border: Border(
          top: BorderSide(color: top, width: active ? 1.5 : 1),
          bottom: const BorderSide(color: VtTheme.chromeBorder),
          left: accentBorder != null
              ? BorderSide(color: accentBorder!, width: 2)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: DecoratedBox(
              decoration: const BoxDecoration(
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
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

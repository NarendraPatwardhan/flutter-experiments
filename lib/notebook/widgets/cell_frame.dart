import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Outlined notebook cell — always a visible box, not a flat strip.
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

  /// Visible outline (dark-on-dark needs more than hairline #2A2A2A).
  static const Color outline = Color(0xFF3D3D3D);
  static const Color outlineActive = Color(0xFF5A9E72);

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    final borderColor = active ? outlineActive : outline;

    final header = SizedBox(
      height: headerHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VtTheme.chromeBg,
          border: Border(
            bottom: BorderSide(color: outline.withOpacity(0.9)),
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
        border: Border.all(color: borderColor, width: active ? 1.5 : 1.0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
          children: [
            header,
            body,
          ],
        ),
      ),
    );
  }
}

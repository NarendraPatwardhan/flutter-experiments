import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../document.dart';
import 'cell_chrome.dart';

class NotebookBottomBar extends StatelessWidget {
  const NotebookBottomBar({
    super.key,
    required this.hints,
    this.flash,
    this.fontFamily,
  });

  final List<HintItem> hints;
  final String? flash;
  final String? fontFamily;

  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: VtTheme.chromeBg,
        border: Border(top: BorderSide(color: VtTheme.chromeBorder)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0)
              Text('  ·  ', style: CellChrome.dim(fam, size: 11)),
            Text(
              hints[i].keyLabel,
              style: CellChrome.mono(
                fam,
                size: 11,
                color: VtTheme.chromeAccent,
                weight: FontWeight.w500,
              ),
            ),
            Text(
              ' ${hints[i].action}',
              style: CellChrome.dim(fam, size: 11),
            ),
          ],
          const Spacer(),
          if (flash != null && flash!.isNotEmpty)
            Text(
              flash!,
              style: CellChrome.mono(
                fam,
                size: 11,
                color: VtTheme.chromeFg,
              ),
            ),
        ],
      ),
    );
  }
}

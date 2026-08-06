import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import 'cell_chrome.dart';

/// NL composer body for ActiveSlot — docs/notebook-components.md §4.7.
class AskSurface extends StatelessWidget {
  const AskSurface({
    super.key,
    required this.controller,
    required this.focusNode,
    this.fontFamily,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    return ColoredBox(
      color: VtTheme.background,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: CellChrome.mono(fam, size: 13, height: 1.35),
        cursorColor: VtTheme.chromeAccent,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'What should this machine do…',
          hintStyle: CellChrome.dim(fam, size: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        ),
      ),
    );
  }
}

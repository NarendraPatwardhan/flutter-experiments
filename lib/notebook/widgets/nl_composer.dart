import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Ask composer body. Parent [NotebookCellFrame] owns the header.
class NlComposer extends StatelessWidget {
  const NlComposer({
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
        style: NotebookChrome.mono(fam, size: 13, height: 1.35),
        cursorColor: VtTheme.chromeAccent,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Describe what you want done on this machine…',
          hintStyle: NotebookChrome.dim(fam, size: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        ),
      ),
    );
  }
}

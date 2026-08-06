import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Ask-mode editor body. [NotebookCellFrame] supplies the cell header.
class NlComposer extends StatelessWidget {
  const NlComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.fontFamily,
    this.viewportHeight = 400,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String text) onSubmit;
  final String? fontFamily;

  /// Reserved for callers that size the parent cell; field fills the cell body.
  final double viewportHeight;

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

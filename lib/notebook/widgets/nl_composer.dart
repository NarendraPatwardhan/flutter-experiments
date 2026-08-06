import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';
import '../expand_cap.dart';

/// Natural-language composer (Shift+Tab mode).
class NlComposer extends StatefulWidget {
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
  final double viewportHeight;

  @override
  State<NlComposer> createState() => _NlComposerState();
}

class _NlComposerState extends State<NlComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant NlComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final fam = widget.fontFamily;
    final text = widget.controller.text;
    final lines = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    // Header + footer chrome + line height.
    final desired = 36.0 + (lines.clamp(1, 40) * 18.0) + 8.0;
    final h = ExpandCap.clampHeight(
      desired: desired,
      viewportHeight: widget.viewportHeight,
      minHeight: 88,
      maxFraction: 0.42,
    );

    return Material(
      color: VtTheme.chromeBg,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: VtTheme.chromeBorder, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(
                children: [
                  NotebookChrome.modeChip('ask', fam, emphasize: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Message the agent on this machine',
                      style: NotebookChrome.dim(fam, size: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: h - 36,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: NotebookChrome.mono(fam, size: 13, height: 1.35),
                cursorColor: VtTheme.chromeAccent,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Describe what you want done…',
                  hintStyle: NotebookChrome.dim(fam, size: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

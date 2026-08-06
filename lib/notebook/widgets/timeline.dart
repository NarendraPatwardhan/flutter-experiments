import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';
import 'cell_frame.dart';

/// User message on the timeline (above the active surface).
class UserMessageCell extends StatelessWidget {
  const UserMessageCell({
    super.key,
    required this.message,
    this.fontFamily,
  });

  final UserMessage message;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final fam = fontFamily;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VtTheme.background,
        border: Border(
          top: const BorderSide(color: VtTheme.chromeBorder),
          bottom: const BorderSide(color: VtTheme.chromeBorder),
          left: BorderSide(color: VtTheme.chromeAccent, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: NotebookCellFrame.headerHeight,
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
                    NotebookChrome.modeChip('you', fam, emphasize: true),
                    const Spacer(),
                    Text(
                      NotebookChrome.formatTime(message.at),
                      style: NotebookChrome.dim(fam, size: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(
              message.text,
              style: NotebookChrome.mono(fam, size: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

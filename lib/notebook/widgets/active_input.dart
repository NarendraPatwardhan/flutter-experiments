import 'package:flutter/material.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';
import 'cell_frame.dart';
import 'live_terminal.dart';
import 'nl_composer.dart';

/// Bottom-anchored active cell: terminal **or** ask (mode switch, not split).
/// Always outlined — this is a notebook cell, not a full-bleed PTY.
class ActiveInputSurface extends StatelessWidget {
  const ActiveInputSurface({
    super.key,
    required this.mode,
    required this.session,
    required this.metrics,
    required this.blinkPhase,
    required this.terminalFocused,
    required this.nlController,
    required this.nlFocus,
    required this.onTerminalLayout,
    this.shellReady = true,
  });

  final InputMode mode;
  final ProductSession session;
  final VtMetrics metrics;
  final bool blinkPhase;
  final bool terminalFocused;
  final TextEditingController nlController;
  final FocusNode nlFocus;
  final void Function(int cols, int rows, EdgeInsets padding) onTerminalLayout;
  final bool shellReady;

  @override
  Widget build(BuildContext context) {
    final fam = metrics.fontFamily;
    final isAsk = mode == InputMode.naturalLanguage;

    final body = isAsk
        ? NlComposer(
            controller: nlController,
            focusNode: nlFocus,
            fontFamily: fam,
          )
        : shellReady
            ? LiveTerminalView(
                session: session,
                metrics: metrics,
                blinkPhase: blinkPhase,
                focused: terminalFocused,
                onLayout: onTerminalLayout,
              )
            : _StartingBody(fontFamily: fam);

    return NotebookCellFrame(
      kindLabel: isAsk ? 'ask' : 'terminal',
      active: true,
      expandBody: true,
      fontFamily: fam,
      child: body,
    );
  }
}

class _StartingBody extends StatelessWidget {
  const _StartingBody({this.fontFamily});
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VtTheme.background,
      child: Center(
        child: Text(
          'Starting…',
          style: NotebookChrome.dim(fontFamily, size: 13),
        ),
      ),
    );
  }
}

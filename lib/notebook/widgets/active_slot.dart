import 'package:flutter/material.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../document.dart';
import 'ask_surface.dart';
import 'cell_chrome.dart';
import 'live_terminal_surface.dart';

/// Bottom active slot — rounded composer; live terminal owns its wheel scroll.
class ActiveSlot extends StatelessWidget {
  const ActiveSlot({
    super.key,
    required this.mode,
    required this.session,
    required this.metrics,
    required this.blinkPhase,
    required this.terminalFocused,
    required this.nlController,
    required this.nlFocus,
    required this.onTerminalLayout,
    this.onRequestTerminalFocus,
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
  final VoidCallback? onRequestTerminalFocus;
  final bool shellReady;

  @override
  Widget build(BuildContext context) {
    final fam = metrics.fontFamily;
    final isAsk = mode == InputMode.naturalLanguage;
    final modeKind = isAsk ? 'ask' : 'terminal';
    final focused = isAsk || terminalFocused;

    // No GestureDetector wrapper — it can interfere with pointer-signal scroll.
    final body = isAsk
        ? AskSurface(
            controller: nlController,
            focusNode: nlFocus,
            fontFamily: fam,
          )
        : shellReady
            ? LiveTerminalSurface(
                session: session,
                metrics: metrics,
                blinkPhase: blinkPhase,
                focused: terminalFocused,
                onLayout: onTerminalLayout,
                onTap: onRequestTerminalFocus,
              )
            : Center(
                child: Text(
                  'Starting…',
                  style: CellChrome.dim(fam, size: 13),
                ),
              );

    return ActiveComposerChrome(
      modeKind: modeKind,
      focused: focused,
      fontFamily: fam,
      child: ColoredBox(color: VtTheme.background, child: body),
    );
  }
}

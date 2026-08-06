import 'package:flutter/material.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../chrome.dart';
import '../model.dart';
import 'live_terminal.dart';
import 'nl_composer.dart';

/// Bottom-anchored active surface: terminal **or** ask (mode switch, not split).
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
    this.showChrome = true,
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

  /// Kind chip on the active surface (off for full-bleed cold terminal).
  final bool showChrome;

  /// Hide guest boot dump until the shell is interactive.
  final bool shellReady;

  @override
  Widget build(BuildContext context) {
    final fam = metrics.fontFamily;

    final body = switch (mode) {
      InputMode.terminal => shellReady
          ? LiveTerminalView(
              session: session,
              metrics: metrics,
              blinkPhase: blinkPhase,
              focused: terminalFocused,
              onLayout: onTerminalLayout,
            )
          : _StartingBody(fontFamily: fam),
      InputMode.naturalLanguage => NlComposer(
          controller: nlController,
          focusNode: nlFocus,
          fontFamily: fam,
        ),
    };

    if (!showChrome) {
      return ColoredBox(color: VtTheme.background, child: body);
    }

    final label = mode == InputMode.naturalLanguage ? 'ask' : 'terminal';
    return ColoredBox(
      color: VtTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: VtTheme.chromeBg,
                border: Border(
                  top: BorderSide(color: VtTheme.chromeBorder),
                  bottom: BorderSide(color: VtTheme.chromeBorder),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: NotebookChrome.modeChip(
                    label,
                    fam,
                    emphasize: true,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _StartingBody extends StatelessWidget {
  const _StartingBody({this.fontFamily});
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Starting…',
        style: NotebookChrome.dim(fontFamily, size: 13),
      ),
    );
  }
}

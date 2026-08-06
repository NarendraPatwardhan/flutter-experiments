import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../controller.dart';
import '../expand_cap.dart';
import '../model.dart';
import 'bottom_bar.dart';
import 'frozen_cell.dart';
import 'live_terminal.dart';
import 'nl_composer.dart';
import 'top_bar.dart';

/// Full notebook chrome: top bar, history, single live terminal, optional composer, bottom bar.
class NotebookShell extends StatefulWidget {
  const NotebookShell({
    super.key,
    required this.session,
    required this.notebook,
    required this.metrics,
    required this.blinkPhase,
    required this.terminalFocused,
    required this.statusText,
    required this.busy,
    required this.nlController,
    required this.nlFocus,
    required this.onRerun,
    required this.onTerminalLayout,
    required this.onNlSubmit,
    this.title = 'agentos',
  });

  final ProductSession session;
  final NotebookController notebook;
  final VtMetrics metrics;
  final bool blinkPhase;
  final bool terminalFocused;
  final String statusText;
  final bool busy;
  final TextEditingController nlController;
  final FocusNode nlFocus;
  final VoidCallback onRerun;
  final void Function(int cols, int rows, EdgeInsets padding) onTerminalLayout;
  final void Function(String text) onNlSubmit;
  final String title;

  @override
  State<NotebookShell> createState() => _NotebookShellState();
}

class _NotebookShellState extends State<NotebookShell> {
  final ScrollController _historyScroll = ScrollController();
  int _seenRevision = 0;

  @override
  void dispose() {
    _historyScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NotebookShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rev = widget.notebook.historyRevision;
    if (rev != _seenRevision && widget.notebook.history.isNotEmpty) {
      _seenRevision = rev;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_historyScroll.hasClients) return;
        _historyScroll.animateTo(
          _historyScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final mode = notebook.mode;
    final history = notebook.history;
    final metrics = widget.metrics;

    return ColoredBox(
      color: VtTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NotebookTopBar(
            title: widget.title,
            status: widget.statusText,
            busy: widget.busy,
            bell: widget.session.bellFlash,
            modeLabel: notebook.modeChipLabel(),
            onRerun: widget.busy ? null : widget.onRerun,
            fontFamily: metrics.fontFamily,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bodyH = constraints.maxHeight;
                final minActive = ExpandCap.minActiveHeight(
                  bodyH,
                  fraction: history.isEmpty ? 1.0 : 0.4,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (history.isNotEmpty)
                      Flexible(
                        flex: 2,
                        child: ListView.builder(
                          controller: _historyScroll,
                          padding: EdgeInsets.zero,
                          itemCount: history.length,
                          itemBuilder: (context, i) {
                            final e = history[i];
                            return switch (e) {
                              FrozenTerminalEntry(:final cell) =>
                                FrozenTerminalCellView(
                                  cell: cell,
                                  metrics: metrics,
                                  maxHeight: (bodyH * 0.45).clamp(120.0, 360.0),
                                ),
                              UserMessageEntry(:final cell) =>
                                UserMessageCellView(
                                  cell: cell,
                                  fontFamily: metrics.fontFamily,
                                ),
                              SystemNoticeEntry(:final cell) =>
                                SystemNoticeCellView(
                                  cell: cell,
                                  fontFamily: metrics.fontFamily,
                                ),
                            };
                          },
                        ),
                      ),
                    // Exactly one live terminal — always the machine surface.
                    Expanded(
                      flex: history.isEmpty ? 1 : 3,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: minActive),
                        child: LiveTerminalView(
                          session: widget.session,
                          metrics: metrics,
                          blinkPhase: widget.blinkPhase,
                          focused: widget.terminalFocused &&
                              mode == InputMode.terminal,
                          onLayout: widget.onTerminalLayout,
                        ),
                      ),
                    ),
                    if (mode == InputMode.naturalLanguage)
                      NlComposer(
                        controller: widget.nlController,
                        focusNode: widget.nlFocus,
                        onSubmit: widget.onNlSubmit,
                        fontFamily: metrics.fontFamily,
                        viewportHeight: bodyH,
                      ),
                  ],
                );
              },
            ),
          ),
          NotebookBottomBar(
            hints: notebook.hintsForCurrent(),
            flash: notebook.statusFlash,
            fontFamily: metrics.fontFamily,
          ),
        ],
      ),
    );
  }
}

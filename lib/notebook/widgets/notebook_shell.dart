import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../controller.dart';
import '../expand_cap.dart';
import '../model.dart';
import 'bottom_bar.dart';
import 'cell_frame.dart';
import 'live_terminal.dart';
import 'nl_composer.dart';
import 'timeline.dart';
import 'top_bar.dart';

/// Machine notebook surface.
///
/// - Empty + terminal: full-bleed active terminal (no fake void).
/// - Timeline present: history scrolls above; active bottom-capped.
/// - Ask mode: live terminal above ask cell at bottom.
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
    required this.onRestart,
    required this.onTerminalLayout,
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
  final VoidCallback onRestart;
  final void Function(int cols, int rows, EdgeInsets padding) onTerminalLayout;
  final String title;

  @override
  State<NotebookShell> createState() => _NotebookShellState();
}

class _NotebookShellState extends State<NotebookShell> {
  final ScrollController _scroll = ScrollController();
  int _seenRev = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NotebookShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rev = widget.notebook.timelineRevision;
    if (rev != _seenRev && widget.notebook.timeline.isNotEmpty) {
      _seenRev = rev;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Widget _live({required bool focused}) {
    return LiveTerminalView(
      session: widget.session,
      metrics: widget.metrics,
      blinkPhase: widget.blinkPhase,
      focused: focused,
      onLayout: widget.onTerminalLayout,
    );
  }

  String? get _gridMeta {
    final c = widget.session.frame.cols;
    final r = widget.session.frame.rows;
    if (c <= 0 || r <= 0) return null;
    return '${c}×$r';
  }

  /// Terminal cell filling max constraints (use under Expanded or as full body).
  Widget _terminalCell({
    required bool focused,
    String? meta,
  }) {
    return NotebookCellFrame(
      kindLabel: 'terminal',
      metaRight: meta ?? _gridMeta,
      active: focused,
      fontFamily: widget.metrics.fontFamily,
      child: _live(focused: focused),
    );
  }

  Widget _askStack() {
    final fam = widget.metrics.fontFamily;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _terminalCell(focused: false, meta: 'live'),
        ),
        Expanded(
          flex: 2,
          child: NotebookCellFrame(
            kindLabel: 'ask',
            active: true,
            fontFamily: fam,
            child: NlComposer(
              controller: widget.nlController,
              focusNode: widget.nlFocus,
              fontFamily: fam,
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeline() {
    final items = widget.notebook.timeline;
    final fam = widget.metrics.fontFamily;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        return switch (e) {
          UserMessageEntry(:final message) => UserMessageCell(
              message: message,
              fontFamily: fam,
            ),
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final mode = notebook.mode;
    final empty = notebook.timeline.isEmpty;
    final fam = widget.metrics.fontFamily;

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
            onRestart: widget.busy ? null : widget.onRestart,
            fontFamily: fam,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bodyH = constraints.maxHeight;

                // Cold start, terminal: fill the body (bounded by Expanded parent).
                if (empty && mode == InputMode.terminal) {
                  return _terminalCell(focused: widget.terminalFocused);
                }

                // Ask, empty timeline: flex stack (terminal + ask).
                if (empty && mode == InputMode.naturalLanguage) {
                  return _askStack();
                }

                // Timeline + bottom-capped active.
                final activeH = ExpandCap.clampHeight(
                  desired: bodyH * 0.5,
                  viewportHeight: bodyH,
                  minHeight: 160,
                  maxFraction: 0.55,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _timeline()),
                    if (mode == InputMode.terminal)
                      SizedBox(
                        height: activeH,
                        child: _terminalCell(
                          focused: widget.terminalFocused,
                        ),
                      )
                    else
                      SizedBox(
                        height: activeH,
                        child: _askStack(),
                      ),
                  ],
                );
              },
            ),
          ),
          NotebookBottomBar(
            hints: notebook.hintsForCurrent(),
            flash: notebook.statusFlash,
            fontFamily: fam,
          ),
        ],
      ),
    );
  }
}

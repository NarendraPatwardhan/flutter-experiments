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
import 'frozen_cell.dart';
import 'live_terminal.dart';
import 'nl_composer.dart';
import 'top_bar.dart';

/// Machine notebook geometry (agreed model):
///
/// - **Empty history + terminal:** full-bleed active terminal (terminal-first).
/// - **History present:** scrollable cells above (oldest top → newest above active);
///   active cell pinned bottom, expand→cap.
/// - **Ask mode:** active bottom is ask; live terminal sits in the region above
///   (still one guest), history above that if any.
///
/// No fake void / "notebook" watermark.
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Widget _liveTerminal({required bool focused}) {
    return LiveTerminalView(
      session: widget.session,
      metrics: widget.metrics,
      blinkPhase: widget.blinkPhase,
      focused: focused,
      onLayout: widget.onTerminalLayout,
    );
  }

  Widget _historyList(double bodyH) {
    final history = widget.notebook.history;
    final metrics = widget.metrics;
    final cap = (bodyH * 0.45).clamp(120.0, 360.0);
    return ListView.builder(
      controller: _historyScroll,
      padding: EdgeInsets.zero,
      itemCount: history.length,
      itemBuilder: (context, i) {
        final e = history[i];
        return switch (e) {
          FrozenTerminalEntry(:final cell) => FrozenTerminalCellView(
              cell: cell,
              metrics: metrics,
              maxHeight: cap,
            ),
          UserMessageEntry(:final cell) => UserMessageCellView(
              cell: cell,
              fontFamily: metrics.fontFamily,
            ),
          SystemNoticeEntry(:final cell) => SystemNoticeCellView(
              cell: cell,
              fontFamily: metrics.fontFamily,
            ),
        };
      },
    );
  }

  /// Active terminal cell (framed) filling [height] or expanding.
  Widget _terminalActive({required bool expand, double? height}) {
    final fam = widget.metrics.fontFamily;
    final cols = widget.session.frame.cols;
    final rows = widget.session.frame.rows;
    final sizeMeta = cols > 0 ? '${cols}×$rows' : null;
    final frame = NotebookCellFrame(
      kindLabel: 'terminal',
      metaRight: sizeMeta,
      active: widget.terminalFocused,
      fontFamily: fam,
      child: _liveTerminal(focused: widget.terminalFocused),
    );
    if (expand) {
      return Expanded(child: frame);
    }
    return SizedBox(height: height, child: frame);
  }

  Widget _askActive(double bodyH) {
    final fam = widget.metrics.fontFamily;
    // Ask sits at bottom with expand-cap; live terminal fills remainder above.
    final askH = ExpandCap.clampHeight(
      desired: bodyH * 0.28,
      viewportHeight: bodyH,
      minHeight: 120,
      maxFraction: 0.40,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotebookCellFrame(
            kindLabel: 'terminal',
            metaRight: 'live',
            active: false,
            fontFamily: fam,
            child: _liveTerminal(focused: false),
          ),
        ),
        SizedBox(
          height: askH + NotebookCellFrame.headerHeight,
          child: NotebookCellFrame(
            kindLabel: 'ask',
            metaRight: 'active',
            active: true,
            fontFamily: fam,
            child: NlComposer(
              controller: widget.nlController,
              focusNode: widget.nlFocus,
              onSubmit: widget.onNlSubmit,
              fontFamily: fam,
              viewportHeight: askH,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final mode = notebook.mode;
    final historyEmpty = notebook.history.isEmpty;
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

                // --- Terminal-first cold start: full-bleed active terminal ---
                if (historyEmpty && mode == InputMode.terminal) {
                  return _terminalActive(expand: true);
                }

                // --- Ask with no history yet: terminal + ask stacked ---
                if (historyEmpty && mode == InputMode.naturalLanguage) {
                  return _askActive(bodyH);
                }

                // --- History present: timeline above, active bottom-capped ---
                final activeH = ExpandCap.clampHeight(
                  desired: bodyH * 0.5,
                  viewportHeight: bodyH,
                  minHeight: 160,
                  maxFraction: 0.55,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _historyList(bodyH)),
                    if (mode == InputMode.terminal)
                      _terminalActive(expand: false, height: activeH)
                    else
                      SizedBox(
                        height: activeH,
                        child: _askActive(activeH),
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

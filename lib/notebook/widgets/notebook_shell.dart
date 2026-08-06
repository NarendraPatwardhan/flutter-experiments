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

/// Full notebook chrome: fixed top/bottom bars, history stack, pinned active cell.
///
/// Geometry (SYSTEM H1 / ui-northstar):
/// ```
/// [top bar fixed]
/// [ Expanded body Column:
///     Expanded: history ListView (oldest → newest). Empty = void above active.
///     Active cell PINNED AT BOTTOM (fixed height, not residual Expanded)
/// ]
/// [bottom bar fixed]
/// ```
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

  /// Active region height from body height [h] and whether history has entries.
  double _activeHeight(double h, bool historyEmpty) {
    if (h <= 0) return 160;
    if (historyEmpty) {
      // Terminal-first: large bottom active cell; leave top void so structure is obvious.
      return h * 0.78;
    }
    return ExpandCap.clampHeight(
      desired: h * 0.45,
      viewportHeight: h,
      minHeight: 160,
      maxFraction: 0.55,
    );
  }

  Widget _historyList(List<NotebookHistoryEntry> history, double bodyH) {
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

  Widget _liveTerminal({required bool focused}) {
    return LiveTerminalView(
      session: widget.session,
      metrics: widget.metrics,
      blinkPhase: widget.blinkPhase,
      focused: focused,
      onLayout: widget.onTerminalLayout,
    );
  }

  Widget _activeCell({
    required double height,
    required InputMode mode,
  }) {
    final metrics = widget.metrics;
    final fam = metrics.fontFamily;
    final cols = widget.session.frame.cols;
    final rows = widget.session.frame.rows;
    final sizeMeta = cols > 0 ? '${cols}×$rows' : null;

    if (mode == InputMode.terminal) {
      return SizedBox(
        height: height,
        child: NotebookCellFrame(
          kindLabel: 'terminal',
          metaRight: sizeMeta,
          active: widget.terminalFocused,
          fontFamily: fam,
          child: _liveTerminal(
            focused: widget.terminalFocused,
          ),
        ),
      );
    }

    // Natural language: machine still visible above ask composer.
    final termH = height * 0.4;
    final askH = height - termH;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: termH,
            child: NotebookCellFrame(
              kindLabel: 'terminal',
              metaRight: 'live',
              active: false,
              fontFamily: fam,
              child: _liveTerminal(focused: false),
            ),
          ),
          SizedBox(
            height: askH,
            child: NotebookCellFrame(
              kindLabel: 'ask',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final mode = notebook.mode;
    final history = notebook.history;
    final metrics = widget.metrics;
    final historyEmpty = history.isEmpty;

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
                final activeH = _activeHeight(bodyH, historyEmpty);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // History (or empty canvas / void) fills space above active.
                    Expanded(
                      child: historyEmpty
                          ? _EmptyTimeline(fontFamily: metrics.fontFamily)
                          : _historyList(history, bodyH),
                    ),
                    // Active cell pinned at bottom of body — fixed height.
                    _activeCell(height: activeH, mode: mode),
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

/// Void above the active cell when history is empty — makes notebook structure readable.
class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({this.fontFamily});
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Center(
        child: Text(
          'notebook',
          style: TextStyle(
            fontFamily: fontFamily ?? 'monospace',
            fontFamilyFallback: VtMetrics.fontFamilyFallback,
            fontSize: 11,
            letterSpacing: 0.14,
            color: VtTheme.chromeDim.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

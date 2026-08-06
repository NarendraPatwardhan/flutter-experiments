import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../controller.dart';
import '../expand_cap.dart';
import '../model.dart';
import 'active_input.dart';
import 'bottom_bar.dart';
import 'timeline.dart';
import 'top_bar.dart';

/// Machine notebook surface (docs/ui-northstar.md).
///
/// Geometry (always):
/// ```
///   [ air / scrollable history — void only ABOVE oldest ]
///   [ outlined active cell — BOTTOM-ANCHORED ]
/// ```
/// Active is terminal **or** ask (Shift+Tab). Never a split stack.
/// Cells always have outlines — this is a notebook, not a raw PTY window.
class NotebookShell extends StatefulWidget {
  const NotebookShell({
    super.key,
    required this.session,
    required this.notebook,
    required this.metrics,
    required this.blinkPhase,
    required this.terminalFocused,
    required this.subtitle,
    required this.busy,
    required this.nlController,
    required this.nlFocus,
    required this.onTerminalLayout,
    this.title = 'agentos',
  });

  final ProductSession session;
  final NotebookController notebook;
  final VtMetrics metrics;
  final bool blinkPhase;
  final bool terminalFocused;
  final String? subtitle;
  final bool busy;
  final TextEditingController nlController;
  final FocusNode nlFocus;
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
    if (rev != _seenRev && widget.notebook.hasTimeline) {
      _seenRev = rev;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(0);
      });
    }
  }

  Widget _active({required bool shellReady}) {
    return ActiveInputSurface(
      mode: widget.notebook.mode,
      session: widget.session,
      metrics: widget.metrics,
      blinkPhase: widget.blinkPhase,
      terminalFocused: widget.terminalFocused,
      nlController: widget.nlController,
      nlFocus: widget.nlFocus,
      onTerminalLayout: widget.onTerminalLayout,
      shellReady: shellReady,
    );
  }

  /// Active height: expand for the mode, then hard-cap.
  double _activeHeight({
    required double bodyH,
    required bool empty,
    required bool isTerm,
  }) {
    if (empty && isTerm) {
      // First cell alone: grow large but still a bottom cell (air above).
      return ExpandCap.clampHeight(
        desired: bodyH * 0.88,
        viewportHeight: bodyH,
        minHeight: 200,
        maxFraction: 0.92,
      );
    }
    if (empty && !isTerm) {
      return ExpandCap.clampHeight(
        desired: bodyH * 0.35,
        viewportHeight: bodyH,
        minHeight: 140,
        maxFraction: 0.5,
      );
    }
    // Timeline present: active shares space, stays bottom.
    return ExpandCap.clampHeight(
      desired: isTerm ? bodyH * 0.42 : bodyH * 0.32,
      viewportHeight: bodyH,
      minHeight: isTerm ? 180 : 120,
      maxFraction: isTerm ? 0.55 : 0.45,
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final mode = notebook.mode;
    final empty = !notebook.hasTimeline;
    final fam = widget.metrics.fontFamily;
    final shellReady = widget.session.shellReady;
    final isTerm = mode == InputMode.terminal;

    return ColoredBox(
      color: VtTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NotebookTopBar(
            title: widget.title,
            subtitle: widget.subtitle,
            busy: widget.busy,
            bell: widget.session.bellFlash,
            fontFamily: fam,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bodyH = constraints.maxHeight;
                final activeH = _activeHeight(
                  bodyH: bodyH,
                  empty: empty,
                  isTerm: isTerm,
                );

                // Always: [history-or-air] + bottom active outlined cell.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: empty
                            ? const SizedBox.expand() // air above first cell
                            : TimelinePane(
                                entries: notebook.timeline,
                                scrollController: _scroll,
                                fontFamily: fam,
                              ),
                      ),
                      SizedBox(
                        height: activeH,
                        child: _active(shellReady: shellReady),
                      ),
                    ],
                  ),
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

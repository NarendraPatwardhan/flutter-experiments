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

/// Machine notebook — Grok stack geometry.
///
/// ```
///   [ air  /  history cells glued to bottom of this region ]
///   [ active outlined cell — ALWAYS bottom-anchored        ]
/// ```
///
/// Active is terminal **or** ask (mode of one cell). Never a split.
/// Cold-start terminal is the same bottom cell as with history — not mid-window.
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
    this.onRequestTerminalFocus,
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
  final VoidCallback? onRequestTerminalFocus;
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

  /// Bottom active height — same rules empty or not (expand → hard-cap).
  double _activeHeight(double bodyH, bool isTerm) {
    if (isTerm) {
      // ~14 rows of mono + header, then hard-cap. Never ~full body mid-window.
      final rowH = widget.metrics.cellHeight;
      final desired = 26 + 8 + rowH * 14;
      return ExpandCap.clampHeight(
        desired: desired,
        viewportHeight: bodyH,
        minHeight: 160,
        maxFraction: 0.42,
      );
    }
    return ExpandCap.clampHeight(
      desired: bodyH * 0.28,
      viewportHeight: bodyH,
      minHeight: 120,
      maxFraction: 0.38,
    );
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final isTerm = notebook.mode == InputMode.terminal;
    final fam = widget.metrics.fontFamily;
    final shellReady = widget.session.shellReady;

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
                final activeH = _activeHeight(bodyH, isTerm);

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // History (or air) — void only ABOVE content.
                      Expanded(
                        child: notebook.hasTimeline
                            ? TimelinePane(
                                entries: notebook.timeline,
                                scrollController: _scroll,
                                metrics: widget.metrics,
                              )
                            : const SizedBox.expand(),
                      ),
                      // Active cell — always bottom.
                      SizedBox(
                        height: activeH,
                        child: ActiveInputSurface(
                          mode: notebook.mode,
                          session: widget.session,
                          metrics: widget.metrics,
                          blinkPhase: widget.blinkPhase,
                          terminalFocused: widget.terminalFocused,
                          nlController: widget.nlController,
                          nlFocus: widget.nlFocus,
                          onTerminalLayout: widget.onTerminalLayout,
                          onRequestTerminalFocus: widget.onRequestTerminalFocus,
                          shellReady: shellReady,
                        ),
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

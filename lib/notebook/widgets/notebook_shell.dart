import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../session/product_session.dart';
import '../../vt/metrics.dart';
import '../../vt/theme.dart';
import '../controller.dart';
import '../document.dart';
import '../expand_cap.dart';
import 'active_slot.dart';
import 'bottom_bar.dart';
import 'cell_chrome.dart';
import 'history_column.dart';
import 'top_bar.dart';

/// Layout-only shell — docs/notebook-components.md §8.
///
/// ```
/// TopBar
/// HistoryColumn (or air)
/// ActiveSlot  ← always bottom, shared rest height
/// BottomBar
/// ```
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
    final rev = widget.notebook.revision;
    if (rev != _seenRev && widget.notebook.hasTimeline) {
      _seenRev = rev;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(0);
      });
    }
  }

  /// Shared rest height for terminal **and** ask (no jump on Shift+Tab).
  double _activeHeight(double bodyH) {
    final rowH = widget.metrics.cellHeight;
    final desired = CellChrome.headerHeight + 10 + rowH * 8;
    return ExpandCap.clampHeight(
      desired: desired,
      viewportHeight: bodyH,
      minHeight: 148,
      maxFraction: 0.40,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nb = widget.notebook;
    final fam = widget.metrics.fontFamily;

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
                final activeH = _activeHeight(bodyH);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: nb.hasTimeline
                            ? HistoryColumn(
                                cells: nb.timeline,
                                scrollController: _scroll,
                                metrics: widget.metrics,
                              )
                            : const SizedBox.expand(),
                      ),
                      SizedBox(
                        height: activeH,
                        child: ActiveSlot(
                          mode: nb.mode,
                          session: widget.session,
                          metrics: widget.metrics,
                          blinkPhase: widget.blinkPhase,
                          terminalFocused: widget.terminalFocused,
                          nlController: widget.nlController,
                          nlFocus: widget.nlFocus,
                          onTerminalLayout: widget.onTerminalLayout,
                          onRequestTerminalFocus:
                              widget.onRequestTerminalFocus,
                          shellReady: widget.session.shellReady,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          NotebookBottomBar(
            hints: nb.hintsForCurrent(),
            flash: nb.statusFlash,
            fontFamily: fam,
          ),
        ],
      ),
    );
  }
}

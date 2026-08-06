import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../session/product_session.dart';
import '../../vt/bindings.dart'
    show
        kSelectionGestureDrag,
        kSelectionGesturePress,
        kSelectionGestureRelease;
import '../../vt/metrics.dart';
import '../../vt/painter.dart';

/// Live Ghostty terminal surface wired to [ProductSession].
///
/// Grid always fits the **cell** (not a fixed 80×24). Overflow history is
/// VT scrollback; wheel/trackpad scrolls **inside** the cell. Paint is clipped
/// so nothing bleeds into the notebook air above.
class LiveTerminalView extends StatefulWidget {
  const LiveTerminalView({
    super.key,
    required this.session,
    required this.metrics,
    required this.blinkPhase,
    required this.focused,
    this.onLayout,
  });

  final ProductSession session;
  final VtMetrics metrics;
  final bool blinkPhase;
  final bool focused;

  /// Called when grid cols/rows/padding change after fit.
  final void Function(int cols, int rows, EdgeInsets padding)? onLayout;

  @override
  State<LiveTerminalView> createState() => _LiveTerminalViewState();
}

class _LiveTerminalViewState extends State<LiveTerminalView> {
  int _cols = 80;
  int _rows = 8;
  EdgeInsets _padding = const EdgeInsets.all(8);

  void _fit(Size size) {
    if (size.width < 1 || size.height < 1) return;
    final fit = widget.metrics.fit(
      size,
      explicit: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      minCols: 2,
      minRows: 1,
    );
    if (fit.cols == _cols &&
        fit.rows == _rows &&
        fit.padding == _padding) {
      return;
    }
    setState(() {
      _cols = fit.cols;
      _rows = fit.rows;
      _padding = fit.padding;
    });
    widget.onLayout?.call(fit.cols, fit.rows, fit.padding);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(size);
        });
        // Clip hard: VT frame must never paint outside the notebook cell.
        return ClipRect(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                // Scroll **inside** the cell (VT scrollback), not the notebook.
                unawaited(widget.session.onScroll(signal.scrollDelta.dy));
              }
            },
            onPointerDown: (e) {
              unawaited(widget.session.onPointer(
                kind: kSelectionGesturePress,
                x: e.localPosition.dx,
                y: e.localPosition.dy,
                padL: _padding.left.round(),
                padT: _padding.top.round(),
              ));
            },
            onPointerMove: (e) {
              if (e.down) {
                unawaited(widget.session.onPointer(
                  kind: kSelectionGestureDrag,
                  x: e.localPosition.dx,
                  y: e.localPosition.dy,
                  padL: _padding.left.round(),
                  padT: _padding.top.round(),
                ));
              }
            },
            onPointerUp: (e) {
              unawaited(widget.session.onPointer(
                kind: kSelectionGestureRelease,
                x: e.localPosition.dx,
                y: e.localPosition.dy,
                padL: _padding.left.round(),
                padT: _padding.top.round(),
              ));
            },
            child: VtView(
              frame: widget.session.frame,
              metrics: widget.metrics,
              padding: _padding,
              focused: widget.focused,
              blinkPhase: widget.blinkPhase,
              imagesBelow: widget.session.imagesBelow,
              imagesAbove: widget.session.imagesAbove,
            ),
          ),
        );
      },
    );
  }
}

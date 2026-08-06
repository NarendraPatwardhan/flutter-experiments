import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// Live terminal in ActiveSlot.
///
/// Grid fits the cell; wheel/trackpad scrolls **VT scrollback** inside the cell.
/// Claims [PointerScrollEvent] via [PointerSignalResolver] so nothing steals it.
class LiveTerminalSurface extends StatefulWidget {
  const LiveTerminalSurface({
    super.key,
    required this.session,
    required this.metrics,
    required this.blinkPhase,
    required this.focused,
    required this.onLayout,
    this.onTap,
  });

  final ProductSession session;
  final VtMetrics metrics;
  final bool blinkPhase;
  final bool focused;
  final void Function(int cols, int rows, EdgeInsets padding) onLayout;
  final VoidCallback? onTap;

  @override
  State<LiveTerminalSurface> createState() => _LiveTerminalSurfaceState();
}

class _LiveTerminalSurfaceState extends State<LiveTerminalSurface> {
  int _cols = 80;
  int _rows = 8;
  EdgeInsets _padding = const EdgeInsets.fromLTRB(8, 4, 8, 4);

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
    widget.onLayout(fit.cols, fit.rows, fit.padding);
  }

  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    // Claim the scroll so no ancestor / platform default eats it.
    GestureBinding.instance.pointerSignalResolver.register(signal, (event) {
      final e = event as PointerScrollEvent;
      // Prefer vertical; fall back to horizontal for some trackpads.
      var dy = e.scrollDelta.dy;
      if (dy == 0) dy = e.scrollDelta.dx;
      if (dy == 0) return;
      unawaited(widget.session.onScroll(dy));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(size);
        });
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _onPointerSignal,
          onPointerDown: (e) {
            widget.onTap?.call();
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
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
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

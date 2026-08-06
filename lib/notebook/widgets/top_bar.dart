import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Thin fixed identity bar. No metrics, no restart, no mode chip.
class NotebookTopBar extends StatelessWidget {
  const NotebookTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.busy = false,
    this.bell = false,
    this.fontFamily,
  });

  final String title;
  /// Quiet secondary (pwd, short error). Never grid size or tick state.
  final String? subtitle;
  final bool busy;
  final bool bell;
  final String? fontFamily;

  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    final accent = bell ? VtTheme.chromeBell : VtTheme.chromeAccent;
    final fam = fontFamily;
    final sub = subtitle?.trim();
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: VtTheme.chromeBg,
        border: Border(
          bottom: BorderSide(
            color: bell ? VtTheme.chromeBell : VtTheme.chromeBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: NotebookChrome.mono(
              fam,
              size: 12,
              color: accent,
              weight: FontWeight.w600,
            ),
          ),
          if (sub != null && sub.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NotebookChrome.dim(fam, size: 12),
              ),
            ),
          ] else
            const Spacer(),
          if (busy)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: VtTheme.chromeDim,
              ),
            ),
        ],
      ),
    );
  }
}

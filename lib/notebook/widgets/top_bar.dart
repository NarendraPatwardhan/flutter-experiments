import 'package:flutter/material.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

class NotebookTopBar extends StatelessWidget {
  const NotebookTopBar({
    super.key,
    required this.title,
    required this.status,
    this.busy = false,
    this.bell = false,
    this.modeLabel,
    this.onRestart,
    this.fontFamily,
  });

  final String title;
  final String status;
  final bool busy;
  final bool bell;
  final String? modeLabel;
  final VoidCallback? onRestart;
  final String? fontFamily;

  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    final accent = bell ? VtTheme.chromeBell : VtTheme.chromeAccent;
    final fam = fontFamily;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
          if (modeLabel != null) ...[
            const SizedBox(width: 8),
            NotebookChrome.modeChip(modeLabel!, fam, emphasize: true),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NotebookChrome.mono(fam, size: 12),
            ),
          ),
          if (busy)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: VtTheme.chromeDim,
              ),
            )
          else if (onRestart != null)
            Tooltip(
              message: 'Restart session',
              waitDuration: const Duration(milliseconds: 400),
              child: TextButton(
                onPressed: onRestart,
                style: TextButton.styleFrom(
                  foregroundColor: VtTheme.chromeDim,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('restart', style: NotebookChrome.dim(fam, size: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

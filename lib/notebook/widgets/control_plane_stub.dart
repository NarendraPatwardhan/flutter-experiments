import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../vt/theme.dart';
import '../chrome.dart';

/// Control-plane aperture (Ctrl+K).
Future<void> showControlPlaneStub(
  BuildContext context, {
  VoidCallback? onRestart,
  String? fontFamily,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x990A0A0A),
    builder: (ctx) {
      return _ControlPlaneDialog(
        onRestart: onRestart,
        fontFamily: fontFamily,
      );
    },
  );
}

class _ControlPlaneDialog extends StatefulWidget {
  const _ControlPlaneDialog({
    this.onRestart,
    this.fontFamily,
  });

  final VoidCallback? onRestart;
  final String? fontFamily;

  @override
  State<_ControlPlaneDialog> createState() => _ControlPlaneDialogState();
}

class _ControlPlaneDialogState extends State<_ControlPlaneDialog> {
  int _index = 0;

  late final List<_Item> _items = [
    if (widget.onRestart != null)
      _Item(
        label: 'Restart session',
        secondary: 'Reboot guest and terminal',
        enabled: true,
        run: () {
          Navigator.of(context).pop();
          widget.onRestart!();
        },
      ),
    const _Item(
      label: 'Snapshots',
      secondary: 'Save and restore full guest machine state',
      enabled: false,
    ),
    const _Item(
      label: 'Mounts',
      secondary: 'Attach host paths and volumes into the guest',
      enabled: false,
    ),
    const _Item(
      label: 'Images',
      secondary: 'Choose or inspect the guest image',
      enabled: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Prefer first enabled row.
    final first = _items.indexWhere((e) => e.enabled);
    if (first >= 0) _index = first;
  }

  void _move(int delta) {
    final enabledIdx = <int>[];
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].enabled) enabledIdx.add(i);
    }
    if (enabledIdx.isEmpty) return;
    final cur = enabledIdx.indexOf(_index);
    final base = cur < 0 ? 0 : cur;
    final next = enabledIdx[(base + delta) % enabledIdx.length];
    setState(() => _index = next);
  }

  void _activate() {
    final item = _items[_index];
    if (item.enabled && item.run != null) item.run!();
  }

  @override
  Widget build(BuildContext context) {
    final fam = widget.fontFamily;
    return Dialog(
      backgroundColor: VtTheme.chromeBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: VtTheme.chromeBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 400),
        child: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.escape): const _CloseIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowDown): const _DownIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowUp): const _UpIntent(),
            LogicalKeySet(LogicalKeyboardKey.enter): const _ActivateIntent(),
            LogicalKeySet(LogicalKeyboardKey.numpadEnter):
                const _ActivateIntent(),
          },
          child: Actions(
            actions: {
              _CloseIntent: CallbackAction<_CloseIntent>(
                onInvoke: (_) {
                  Navigator.of(context).pop();
                  return null;
                },
              ),
              _DownIntent: CallbackAction<_DownIntent>(
                onInvoke: (_) {
                  _move(1);
                  return null;
                },
              ),
              _UpIntent: CallbackAction<_UpIntent>(
                onInvoke: (_) {
                  _move(-1);
                  return null;
                },
              ),
              _ActivateIntent: CallbackAction<_ActivateIntent>(
                onInvoke: (_) {
                  _activate();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(
                      'Control plane',
                      style: NotebookChrome.accent(fam, size: 14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Operate the machine under this notebook',
                      style:
                          NotebookChrome.dim(fam, size: 12).copyWith(height: 1.3),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final active = i == _index;
                        return _Row(
                          fam: fam,
                          label: item.label,
                          secondary: item.secondary,
                          enabled: item.enabled,
                          active: active,
                          onTap: item.enabled
                              ? () {
                                  setState(() => _index = i);
                                  item.run?.call();
                                }
                              : null,
                          onHover: item.enabled
                              ? () => setState(() => _index = i)
                              : null,
                        );
                      },
                    ),
                  ),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: VtTheme.chromeBorder),
                      ),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '↑↓ move  ·  ↵ run  ·  Esc close',
                      style: NotebookChrome.dim(fam, size: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item {
  const _Item({
    required this.label,
    required this.secondary,
    required this.enabled,
    this.run,
  });
  final String label;
  final String secondary;
  final bool enabled;
  final VoidCallback? run;
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

class _DownIntent extends Intent {
  const _DownIntent();
}

class _UpIntent extends Intent {
  const _UpIntent();
}

class _ActivateIntent extends Intent {
  const _ActivateIntent();
}

class _Row extends StatelessWidget {
  const _Row({
    required this.fam,
    required this.label,
    required this.secondary,
    required this.enabled,
    required this.active,
    this.onTap,
    this.onHover,
  });

  final String? fam;
  final String label;
  final String secondary;
  final bool enabled;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final bg =
        active && enabled ? const Color(0x1A7CDE9A) : Colors.transparent;
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: NotebookChrome.mono(
                    fam,
                    size: 13,
                    color: enabled
                        ? (active ? VtTheme.chromeAccent : VtTheme.chromeFg)
                        : VtTheme.chromeDim,
                    weight:
                        active && enabled ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  secondary,
                  style:
                      NotebookChrome.dim(fam, size: 11).copyWith(height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

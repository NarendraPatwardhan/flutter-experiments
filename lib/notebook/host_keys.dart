// Host chords that must not reach the guest VT (SYSTEM H1).

import 'package:flutter/services.dart';

/// Host-owned key chords for the notebook shell.
enum HostChord {
  /// Open / focus control-plane stub (Ctrl/Cmd+K).
  controlPlane,

  /// Toggle terminal ↔ natural language (Shift+Tab).
  toggleMode,

  /// Freeze live terminal into history (Ctrl/Cmd+Shift+F).
  freeze,

  /// Esc — peel palette, clear NL draft, or park (ladder skeleton).
  escape,

  /// Submit NL draft (Ctrl/Cmd+Enter in NL mode).
  nlSubmit,
}

/// Classify a key event for host handling. Returns null if the key should
/// pass through to the guest (or text field) under normal routing.
///
/// Priority is applied by the notebook controller; this only detects chords.
HostChord? classifyHostChord(KeyEvent event) {
  // Only press/repeat — ignore key-up.
  final isPress = event is KeyDownEvent || event is KeyRepeatEvent;
  if (!isPress) return null;

  final key = event.logicalKey;
  final ctrl = HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  final shift = HardwareKeyboard.instance.isShiftPressed;

  if (key == LogicalKeyboardKey.escape) {
    return HostChord.escape;
  }

  if (key == LogicalKeyboardKey.tab && shift && !ctrl) {
    return HostChord.toggleMode;
  }

  if (ctrl && !shift && key == LogicalKeyboardKey.keyK) {
    return HostChord.controlPlane;
  }

  if (ctrl && shift && key == LogicalKeyboardKey.keyF) {
    return HostChord.freeze;
  }

  if (ctrl &&
      !shift &&
      (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
    return HostChord.nlSubmit;
  }

  return null;
}

/// Display labels for bottom-bar hints.
String hostChordKeyLabel(HostChord chord) {
  switch (chord) {
    case HostChord.controlPlane:
      return 'Ctrl+K';
    case HostChord.toggleMode:
      return 'Shift+Tab';
    case HostChord.freeze:
      return 'Ctrl+Shift+F';
    case HostChord.escape:
      return 'Esc';
    case HostChord.nlSubmit:
      return 'Ctrl+Enter';
  }
}

String hostChordActionLabel(HostChord chord) {
  switch (chord) {
    case HostChord.controlPlane:
      return 'control plane';
    case HostChord.toggleMode:
      return 'ask';
    case HostChord.freeze:
      return 'freeze';
    case HostChord.escape:
      return 'back';
    case HostChord.nlSubmit:
      return 'send';
  }
}

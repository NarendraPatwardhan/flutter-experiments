// Host chords that must not reach the guest VT.

import 'package:flutter/services.dart';

/// Host-owned key chords for the notebook shell.
enum HostChord {
  /// Open control plane (Ctrl/Cmd+K).
  controlPlane,

  /// Toggle terminal ↔ natural language (Shift+Tab).
  toggleMode,

  /// Esc — clear NL draft or return to terminal.
  escape,

  /// Submit NL draft (Ctrl/Cmd+Enter in ask mode).
  nlSubmit,
}

/// Classify a key event for host handling. Returns null if the key should
/// pass through to the guest (or text field).
HostChord? classifyHostChord(KeyEvent event) {
  final isPress = event is KeyDownEvent || event is KeyRepeatEvent;
  if (!isPress) return null;

  final key = event.logicalKey;
  final ctrl = HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  final shift = HardwareKeyboard.instance.isShiftPressed;

  if (key == LogicalKeyboardKey.escape) {
    return HostChord.escape;
  }

  // Shift+Tab.
  if (shift && !ctrl && key == LogicalKeyboardKey.tab) {
    return HostChord.toggleMode;
  }

  if (ctrl && !shift && key == LogicalKeyboardKey.keyK) {
    return HostChord.controlPlane;
  }

  if (ctrl &&
      !shift &&
      (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
    return HostChord.nlSubmit;
  }

  return null;
}

String hostChordKeyLabel(HostChord chord) {
  switch (chord) {
    case HostChord.controlPlane:
      return 'Ctrl+K';
    case HostChord.toggleMode:
      return 'Shift+Tab';
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
    case HostChord.escape:
      return 'back';
    case HostChord.nlSubmit:
      return 'send';
  }
}

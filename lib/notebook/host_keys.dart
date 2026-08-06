import 'package:flutter/services.dart';

enum HostChord {
  controlPlane,
  toggleMode,
  escape,
  nlSubmit,
}

HostChord? classifyHostChord(KeyEvent event) {
  final isPress = event is KeyDownEvent || event is KeyRepeatEvent;
  if (!isPress) return null;

  final key = event.logicalKey;
  final ctrl = HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  final shift = HardwareKeyboard.instance.isShiftPressed;

  if (key == LogicalKeyboardKey.escape) return HostChord.escape;

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

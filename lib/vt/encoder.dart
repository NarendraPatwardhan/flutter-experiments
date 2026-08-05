// Key / focus / paste encoding via libghostty-vt (G2 stream plane).

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'keys.dart';

/// Holds a Ghostty key encoder + reusable key event.
///
/// Always syncs encoder options from the live terminal before [encodeKey].
class VtEncoder {
  VtEncoder._({
    required GhosttyVtNative native,
    required Pointer<Void> encoder,
    required Pointer<Void> keyEvent,
  })  : _native = native,
        _encoder = encoder,
        _keyEvent = keyEvent;

  final GhosttyVtNative _native;
  Pointer<Void> _encoder;
  Pointer<Void> _keyEvent;
  bool _closed = false;

  GhosttyVtNative get native => _native;
  Pointer<Void> get handle => _encoder;

  /// Open libghostty-vt (or reuse path) and allocate encoder + key event.
  factory VtEncoder.open([String? libPath]) {
    final native = GhosttyVtNative.open(libPath);
    final encOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    final evOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
    try {
      var rc = native.keyEncoderNew(nullptr, encOut);
      if (rc != kGhosttySuccess) {
        throw StateError('ghostty_key_encoder_new failed: $rc');
      }
      final encoder = encOut.value;

      rc = native.keyEventNew(nullptr, evOut);
      if (rc != kGhosttySuccess) {
        native.keyEncoderFree(encoder);
        throw StateError('ghostty_key_event_new failed: $rc');
      }
      return VtEncoder._(
        native: native,
        encoder: encoder,
        keyEvent: evOut.value,
      );
    } finally {
      freePtr(encOut);
      freePtr(evOut);
    }
  }

  /// Encode a key event using modes from [terminal].
  ///
  /// Always calls [GhosttyVtNative.keyEncoderSetoptFromTerminal] first.
  /// Returns empty bytes when the key produces no sequence (e.g. bare mods).
  Uint8List encodeKey({
    required Pointer<Void> terminal,
    required int ghosttyKey,
    required int mods,
    required int action,
    String? utf8,
  }) {
    _ensureOpen();
    if (terminal == nullptr) {
      throw ArgumentError('terminal must not be null');
    }

    _native.keyEncoderSetoptFromTerminal(_encoder, terminal);
    _native.keyEventSetAction(_keyEvent, action);
    _native.keyEventSetKey(_keyEvent, ghosttyKey);
    _native.keyEventSetMods(_keyEvent, mods);

    Pointer<Uint8> utf8Ptr = nullptr;
    var utf8Len = 0;
    if (utf8 != null && utf8.isNotEmpty) {
      final units = const Utf8Encoder().convert(utf8);
      utf8Len = units.length;
      utf8Ptr = mallocBytes<Uint8>(utf8Len, sizeOf<Uint8>());
      utf8Ptr.asTypedList(utf8Len).setAll(0, units);
    }
    try {
      // Clear or set associated UTF-8 for this event.
      _native.keyEventSetUtf8(_keyEvent, utf8Ptr, utf8Len);
      return _encodeIntoBuffer((buf, cap, outLen) {
        return _native.keyEncoderEncode(
          _encoder,
          _keyEvent,
          buf,
          cap,
          outLen,
        );
      });
    } finally {
      if (utf8Ptr != nullptr) freePtr(utf8Ptr);
    }
  }

  /// Focus gained/lost report (CSI I / CSI O) for mode 1004.
  Uint8List encodeFocus({required bool gained}) {
    _ensureOpen();
    final event = gained ? kFocusGained : kFocusLost;
    return _encodeIntoBuffer((buf, cap, outLen) {
      return _native.focusEncode(event, buf, cap, outLen);
    });
  }

  /// Encode paste text. Always runs [GhosttyVtNative.pasteEncode] so unsafe
  /// bytes are stripped even when [pasteIsSafe] is false.
  ///
  /// [bracketed] should reflect the terminal's bracketed-paste mode when known.
  Uint8List encodePaste(String text, {bool bracketed = false}) {
    _ensureOpen();
    if (text.isEmpty) return Uint8List(0);

    final units = Uint8List.fromList(utf8.encode(text));
    // paste_encode mutates the input buffer in place.
    final data = mallocBytes<Uint8>(units.length, sizeOf<Uint8>());
    try {
      data.asTypedList(units.length).setAll(0, units);
      // Optional safety probe — still encode to strip either way.
      _native.pasteIsSafe(data, units.length);
      return _encodeIntoBuffer((buf, cap, outLen) {
        return _native.pasteEncode(
          data,
          units.length,
          bracketed,
          buf,
          cap,
          outLen,
        );
      });
    } finally {
      freePtr(data);
    }
  }

  /// Map a Flutter [LogicalKeyboardKey] to a Ghostty key code, or null.
  static int? logicalKeyToGhostty(LogicalKeyboardKey k) {
    // Letters
    if (k == LogicalKeyboardKey.keyA) return kKeyA;
    if (k == LogicalKeyboardKey.keyB) return kKeyB;
    if (k == LogicalKeyboardKey.keyC) return kKeyC;
    if (k == LogicalKeyboardKey.keyD) return kKeyD;
    if (k == LogicalKeyboardKey.keyE) return kKeyE;
    if (k == LogicalKeyboardKey.keyF) return kKeyF;
    if (k == LogicalKeyboardKey.keyG) return kKeyG;
    if (k == LogicalKeyboardKey.keyH) return kKeyH;
    if (k == LogicalKeyboardKey.keyI) return kKeyI;
    if (k == LogicalKeyboardKey.keyJ) return kKeyJ;
    if (k == LogicalKeyboardKey.keyK) return kKeyK;
    if (k == LogicalKeyboardKey.keyL) return kKeyL;
    if (k == LogicalKeyboardKey.keyM) return kKeyM;
    if (k == LogicalKeyboardKey.keyN) return kKeyN;
    if (k == LogicalKeyboardKey.keyO) return kKeyO;
    if (k == LogicalKeyboardKey.keyP) return kKeyP;
    if (k == LogicalKeyboardKey.keyQ) return kKeyQ;
    if (k == LogicalKeyboardKey.keyR) return kKeyR;
    if (k == LogicalKeyboardKey.keyS) return kKeyS;
    if (k == LogicalKeyboardKey.keyT) return kKeyT;
    if (k == LogicalKeyboardKey.keyU) return kKeyU;
    if (k == LogicalKeyboardKey.keyV) return kKeyV;
    if (k == LogicalKeyboardKey.keyW) return kKeyW;
    if (k == LogicalKeyboardKey.keyX) return kKeyX;
    if (k == LogicalKeyboardKey.keyY) return kKeyY;
    if (k == LogicalKeyboardKey.keyZ) return kKeyZ;

    // Digits
    if (k == LogicalKeyboardKey.digit0) return kKeyDIGIT_0;
    if (k == LogicalKeyboardKey.digit1) return kKeyDIGIT_1;
    if (k == LogicalKeyboardKey.digit2) return kKeyDIGIT_2;
    if (k == LogicalKeyboardKey.digit3) return kKeyDIGIT_3;
    if (k == LogicalKeyboardKey.digit4) return kKeyDIGIT_4;
    if (k == LogicalKeyboardKey.digit5) return kKeyDIGIT_5;
    if (k == LogicalKeyboardKey.digit6) return kKeyDIGIT_6;
    if (k == LogicalKeyboardKey.digit7) return kKeyDIGIT_7;
    if (k == LogicalKeyboardKey.digit8) return kKeyDIGIT_8;
    if (k == LogicalKeyboardKey.digit9) return kKeyDIGIT_9;

    // Navigation / editing
    if (k == LogicalKeyboardKey.arrowUp) return kKeyARROW_UP;
    if (k == LogicalKeyboardKey.arrowDown) return kKeyARROW_DOWN;
    if (k == LogicalKeyboardKey.arrowLeft) return kKeyARROW_LEFT;
    if (k == LogicalKeyboardKey.arrowRight) return kKeyARROW_RIGHT;
    if (k == LogicalKeyboardKey.enter) return kKeyENTER;
    if (k == LogicalKeyboardKey.numpadEnter) return kKeyNUMPAD_ENTER;
    if (k == LogicalKeyboardKey.backspace) return kKeyBACKSPACE;
    if (k == LogicalKeyboardKey.tab) return kKeyTAB;
    if (k == LogicalKeyboardKey.escape) return kKeyESCAPE;
    if (k == LogicalKeyboardKey.space) return kKeySPACE;
    if (k == LogicalKeyboardKey.home) return kKeyHOME;
    if (k == LogicalKeyboardKey.end) return kKeyEND;
    if (k == LogicalKeyboardKey.pageUp) return kKeyPAGE_UP;
    if (k == LogicalKeyboardKey.pageDown) return kKeyPAGE_DOWN;
    if (k == LogicalKeyboardKey.delete) return kKeyDELETE;
    if (k == LogicalKeyboardKey.insert) return kKeyINSERT;

    // Function keys
    if (k == LogicalKeyboardKey.f1) return kKeyF1;
    if (k == LogicalKeyboardKey.f2) return kKeyF2;
    if (k == LogicalKeyboardKey.f3) return kKeyF3;
    if (k == LogicalKeyboardKey.f4) return kKeyF4;
    if (k == LogicalKeyboardKey.f5) return kKeyF5;
    if (k == LogicalKeyboardKey.f6) return kKeyF6;
    if (k == LogicalKeyboardKey.f7) return kKeyF7;
    if (k == LogicalKeyboardKey.f8) return kKeyF8;
    if (k == LogicalKeyboardKey.f9) return kKeyF9;
    if (k == LogicalKeyboardKey.f10) return kKeyF10;
    if (k == LogicalKeyboardKey.f11) return kKeyF11;
    if (k == LogicalKeyboardKey.f12) return kKeyF12;

    // Punctuation / symbols (US layout codes; utf8 still attached by caller)
    if (k == LogicalKeyboardKey.minus) return kKeyMINUS;
    if (k == LogicalKeyboardKey.equal) return kKeyEQUAL;
    if (k == LogicalKeyboardKey.bracketLeft) return kKeyBRACKET_LEFT;
    if (k == LogicalKeyboardKey.bracketRight) return kKeyBRACKET_RIGHT;
    if (k == LogicalKeyboardKey.backslash) return kKeyBACKSLASH;
    if (k == LogicalKeyboardKey.semicolon) return kKeySEMICOLON;
    if (k == LogicalKeyboardKey.quote) return kKeyQUOTE;
    if (k == LogicalKeyboardKey.backquote) return kKeyBACKQUOTE;
    if (k == LogicalKeyboardKey.comma) return kKeyCOMMA;
    if (k == LogicalKeyboardKey.period) return kKeyPERIOD;
    if (k == LogicalKeyboardKey.slash) return kKeySLASH;

    return null;
  }

  /// Build Ghostty mod bits from host modifier state.
  ///
  /// When all flags are omitted, reads [HardwareKeyboard.instance].
  static int modsFromHardware({
    bool? shift,
    bool? ctrl,
    bool? alt,
    bool? meta,
  }) {
    if (shift == null && ctrl == null && alt == null && meta == null) {
      final h = HardwareKeyboard.instance;
      shift = h.isShiftPressed;
      ctrl = h.isControlPressed;
      alt = h.isAltPressed;
      meta = h.isMetaPressed;
    }
    var m = 0;
    if (shift ?? false) m |= kModsShift;
    if (ctrl ?? false) m |= kModsCtrl;
    if (alt ?? false) m |= kModsAlt;
    if (meta ?? false) m |= kModsSuper;
    return m;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_keyEvent != nullptr) {
      _native.keyEventFree(_keyEvent);
      _keyEvent = nullptr;
    }
    if (_encoder != nullptr) {
      _native.keyEncoderFree(_encoder);
      _encoder = nullptr;
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('VtEncoder is closed');
  }

  /// Encode with a scratch buffer; grow on [kGhosttyOutOfSpace].
  Uint8List _encodeIntoBuffer(
    int Function(Pointer<Uint8> buf, int cap, Pointer<Size> outLen) encode,
  ) {
    final outLen = mallocBytes<Size>(1, sizeOf<Size>());
    // Most sequences fit in 128; grow if needed.
    var cap = 128;
    var buf = mallocBytes<Uint8>(cap, sizeOf<Uint8>());
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        outLen.value = 0;
        final rc = encode(buf, cap, outLen);
        if (rc == kGhosttySuccess) {
          final n = outLen.value;
          if (n <= 0) return Uint8List(0);
          return Uint8List.fromList(buf.asTypedList(n));
        }
        if (rc == kGhosttyOutOfSpace) {
          final need = outLen.value;
          if (need <= 0) return Uint8List(0);
          freePtr(buf);
          cap = need;
          buf = mallocBytes<Uint8>(cap, sizeOf<Uint8>());
          continue;
        }
        throw StateError('libghostty encode failed: $rc');
      }
      throw StateError('libghostty encode: buffer growth exhausted');
    } finally {
      freePtr(buf);
      freePtr(outLen);
    }
  }
}

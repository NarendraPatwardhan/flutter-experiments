// Terminal content formatter (G4 debug / export).

import 'dart:convert';
import 'dart:ffi';

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';

/// Output format for [formatTerminal].
enum VtFormatKind {
  plain,
  vt,
  html,
}

/// Format the terminal active screen via Ghostty formatter APIs.
String formatTerminal(
  GhosttyVtNative native,
  Pointer term, {
  VtFormatKind format = VtFormatKind.plain,
  bool unwrap = false,
  bool trim = true,
}) {
  final fmtOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
  final opts =
      mallocBytes<GhosttyFormatterTerminalOptionsNative>(
    1,
    sizeOf<GhosttyFormatterTerminalOptionsNative>(),
  );
  final outLen = mallocBytes<Size>(1, sizeOf<Size>());

  try {
    // Zero-init sized options + nested extras.
    final optBytes = opts.cast<Uint8>().asTypedList(
          sizeOf<GhosttyFormatterTerminalOptionsNative>(),
        );
    optBytes.fillRange(0, optBytes.length, 0);

    opts.ref.size = sizeOf<GhosttyFormatterTerminalOptionsNative>();
    opts.ref.emit = switch (format) {
      VtFormatKind.plain => kFormatterFormatPlain,
      VtFormatKind.vt => kFormatterFormatVt,
      VtFormatKind.html => kFormatterFormatHtml,
    };
    opts.ref.unwrap = unwrap;
    opts.ref.trim = trim;
    opts.ref.extra.size = sizeOf<GhosttyFormatterTerminalExtraNative>();
    opts.ref.extra.screen.size = sizeOf<GhosttyFormatterScreenExtraNative>();
    opts.ref.selection = nullptr;

    // C API takes options by value (MEMORY class). Pass struct by value.
    final rc = native.formatterTerminalNew(
      nullptr,
      fmtOut,
      term.cast(),
      opts.ref,
    );
    if (rc != kGhosttySuccess || fmtOut.value == nullptr) {
      throw StateError('ghostty_formatter_terminal_new failed: $rc');
    }
    final formatter = fmtOut.value;

    try {
      // Grow buffer
      var need = 4096;
      for (var attempt = 0; attempt < 10; attempt++) {
        final buf = mallocBytes<Uint8>(need, sizeOf<Uint8>());
        try {
          outLen.value = 0;
          final frc =
              native.formatterFormatBuf(formatter, buf, need, outLen);
          if (frc == kGhosttySuccess) {
            final n = outLen.value;
            if (n <= 0) return '';
            return utf8.decode(buf.asTypedList(n), allowMalformed: true);
          }
          if (frc == kGhosttyOutOfSpace) {
            need = outLen.value > need ? outLen.value : need * 2;
            continue;
          }
          throw StateError('ghostty_formatter_format_buf failed: $frc');
        } finally {
          freePtr(buf);
        }
      }
      throw StateError('ghostty_formatter_format_buf: growth exhausted');
    } finally {
      native.formatterFree(formatter);
    }
  } finally {
    freePtr(fmtOut);
    freePtr(opts);
    freePtr(outLen);
  }
}

import 'dart:ui' show Color;

/// Terminal + host chrome — neutral grays, **visible** outlines.
///
/// Borders must read on `#141414`. Grok “melt” is still a readable stroke
/// (`prompt_border_active` range), not hairline invisible gray.
abstract final class VtTheme {
  static const Color background = Color(0xFF141414);
  static const Color foreground = Color(0xFFE1E1E1);
  static const Color cursor = Color(0xFFE1E1E1);

  static const Color chromeBg = Color(0xFF0C0C0C);
  static const Color chromeFg = Color(0xFFC8C8C8);
  static const Color chromeAccent = Color(0xFFE1E1E1);

  static const Color roleTerminal = Color(0xFFB0B0B0);
  static const Color roleAsk = Color(0xFFB0B0B0);
  static const Color roleYou = Color(0xFFD0D0D0);
  static const Color roleAgent = Color(0xFF909090);

  static const Color chromeSuccess = Color(0xFF9A9A9A);

  /// Idle outline — visible on canvas (was #323237, effectively invisible).
  static const Color chromeBorder = Color(0xFF4A4A4E);

  /// Focused composer outline.
  static const Color chromeBorderActive = Color(0xFF6E6E74);

  /// History cell outline — clear card edge.
  static const Color chromeBorderHistory = Color(0xFF55555A);

  static const Color chromeDim = Color(0xFF6C6C6C);
  static const Color chromeMuted = Color(0xFF585858);

  static const Color cellHeaderBg = Color(0xFF181818);
  /// Lift cells off the canvas so the stroke + fill read as a card.
  static const Color cellHistoryBg = Color(0xFF1A1A1A);

  static const Color chromeBell = Color(0xFFB0B0B0);
  static const Color selection = Color(0x55363636);

  static Color roleAccent(String kind) {
    switch (kind) {
      case 'terminal':
        return roleTerminal;
      case 'ask':
        return roleAsk;
      case 'you':
        return roleYou;
      case 'agent':
        return roleAgent;
      default:
        return chromeDim;
    }
  }

  static Color activeBorder(String modeKind, {required bool focused}) {
    return focused ? chromeBorderActive : chromeBorder;
  }
}

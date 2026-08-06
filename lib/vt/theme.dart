import 'dart:ui' show Color;

/// Terminal + host chrome (Grok Build GrokNight).
///
/// Borders melt into the canvas. Role distinction is **semantic accent**,
/// not neon boxes. Plan/ask get warmer accents like Grok's plan orange.
abstract final class VtTheme {
  // Surfaces
  static const Color background = Color(0xFF141414);
  static const Color foreground = Color(0xFFE1E1E1);
  static const Color cursor = Color(0xFFE1E1E1);

  static const Color chromeBg = Color(0xFF0C0C0C);
  static const Color chromeFg = Color(0xFFC8C8C8);

  /// Identity / top bar (teal).
  static const Color chromeAccent = Color(0xFF1ABC9C);

  /// Semantic role accents (TokyoNight / GrokNight).
  static const Color roleTerminal = Color(0xFF1ABC9C); // teal
  static const Color roleAsk = Color(0xFFBB9AF7); // magenta (assistant)
  static const Color roleYou = Color(0xFFC8C8C8); // secondary text
  static const Color roleAgent = Color(0xFFBB9AF7); // magenta
  static const Color rolePlan = Color(0xFFFF9E64); // orange — plan mode later

  static const Color chromeSuccess = Color(0xFF9ECE6A);
  static const Color chromeBorder = Color(0xFF323237);
  static const Color chromeBorderActive = Color(0xFF505058);
  static const Color chromeBorderHistory = Color(0xFF3C3C41);
  static const Color chromeDim = Color(0xFF6C6C6C);
  static const Color chromeMuted = Color(0xFF585858);

  static const Color cellHeaderBg = Color(0xFF111111);
  static const Color cellHistoryBg = Color(0xFF121212);

  static const Color chromeBell = Color(0xFFE0AF68);
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
      case 'plan':
        return rolePlan;
      default:
        return chromeDim;
    }
  }

  /// Active composer border by mode (Grok semantic border).
  static Color activeBorder(String modeKind, {required bool focused}) {
    final base = roleAccent(modeKind);
    if (focused) return base;
    // Melt toward canvas when unfocused.
    return Color.lerp(chromeBorder, base, 0.45) ?? chromeBorder;
  }
}

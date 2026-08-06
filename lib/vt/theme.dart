import 'dart:ui' show Color;

/// Terminal + host chrome — **neutral GrokNight grays only**.
///
/// No teal/mint identity, no magenta ask border. Distinction is weight and
/// paper-thin borders that melt into `#141414`, like Grok's prompt chrome.
abstract final class VtTheme {
  // Surfaces (groknight.rs)
  static const Color background = Color(0xFF141414);
  static const Color foreground = Color(0xFFE1E1E1);
  static const Color cursor = Color(0xFFE1E1E1);

  static const Color chromeBg = Color(0xFF0C0C0C);
  static const Color chromeFg = Color(0xFFC8C8C8);

  /// Identity wordmark — soft primary text, not a hue.
  static const Color chromeAccent = Color(0xFFE1E1E1);

  /// Role labels (all grayscale; hierarchy by brightness only).
  static const Color roleTerminal = Color(0xFFB0B0B0);
  static const Color roleAsk = Color(0xFFB0B0B0);
  static const Color roleYou = Color(0xFFD0D0D0);
  static const Color roleAgent = Color(0xFF909090);

  static const Color chromeSuccess = Color(0xFF9A9A9A);
  /// Grok prompt_border — melts into canvas.
  static const Color chromeBorder = Color(0xFF323237);
  /// Grok prompt_border_active — focused composer.
  static const Color chromeBorderActive = Color(0xFF505058);
  static const Color chromeBorderHistory = Color(0xFF3C3C41);
  static const Color chromeDim = Color(0xFF6C6C6C);
  static const Color chromeMuted = Color(0xFF585858);

  static const Color cellHeaderBg = Color(0xFF121212);
  static const Color cellHistoryBg = Color(0xFF161616);

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

  /// Active composer border — neutral gray only (no hue).
  static Color activeBorder(String modeKind, {required bool focused}) {
    return focused ? chromeBorderActive : chromeBorder;
  }
}

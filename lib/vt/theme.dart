import 'dart:ui' show Color;

/// Terminal + host chrome colors.
///
/// Anchored on Grok Build **GrokNight** (`xai-grok-pager-render` theme/groknight.rs):
/// neutral gray ramp, paper-thin borders, quiet accents — not neon mint.
///
/// ```
/// bg_base / storm     #141414
/// bg_terminal         #0a0a0a
/// text_primary        #e1e1e1
/// prompt_border       #323237  (idle frame — melts into bg)
/// prompt_border_active #505058
/// gray / muted        #6c6c6c
/// success (quiet)     #9ece6a  (TokyoNight green — status only)
/// model/identity      #1abc9c  (teal — identity chip, not fill)
/// ```
abstract final class VtTheme {
  // Terminal grid surface
  static const Color background = Color(0xFF141414);
  static const Color foreground = Color(0xFFE1E1E1);
  static const Color cursor = Color(0xFFE1E1E1);

  // Host chrome
  static const Color chromeBg = Color(0xFF0C0C0C);
  static const Color chromeFg = Color(0xFFC8C8C8);
  /// Quiet identity / focus — teal, not mint neon.
  static const Color chromeAccent = Color(0xFF1ABC9C);
  /// Success / positive (rare) — TokyoNight green, dimmer than old #7CDE9A.
  static const Color chromeSuccess = Color(0xFF9ECE6A);
  /// Paper-thin outline — melts into background (Grok prompt_border).
  static const Color chromeBorder = Color(0xFF323237);
  /// Focused / active slot outline (Grok prompt_border_active).
  static const Color chromeBorderActive = Color(0xFF505058);
  /// History cell outline — slightly clearer so transcript reads as cells.
  static const Color chromeBorderHistory = Color(0xFF3C3C41);
  static const Color chromeDim = Color(0xFF6C6C6C);
  static const Color chromeMuted = Color(0xFF585858);

  /// Subtle header strip inside cells (bg_dark-ish).
  static const Color cellHeaderBg = Color(0xFF111111);
  /// History body wash — almost canvas, slight lift.
  static const Color cellHistoryBg = Color(0xFF121212);

  static const Color chromeBell = Color(0xFFE0AF68);
  static const Color selection = Color(0x55363636);
}

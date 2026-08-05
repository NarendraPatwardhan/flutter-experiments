import 'dart:ui' show Color;

/// Terminal chrome + default cell theme.
///
/// libghostty-vt has no look; these match Ghostty’s typical dark defaults
/// (near-black surface, light foreground, soft cursor).
abstract final class VtTheme {
  // Surface outside the grid (same as cell bg so padding “extends”).
  static const Color background = Color(0xFF171717);
  static const Color foreground = Color(0xFFD0D0D0);
  static const Color cursor = Color(0xFFE0E0E0);

  // Thin host chrome (not Material seed teal).
  static const Color chromeBg = Color(0xFF0E0E0E);
  static const Color chromeFg = Color(0xFFA0A0A0);
  static const Color chromeAccent = Color(0xFF7CDE9A);
  static const Color chromeBorder = Color(0xFF2A2A2A);
  static const Color chromeDim = Color(0xFF606060);
}

/// Expand for readability, then hard-cap (docs/ui-northstar.md).
abstract final class ExpandCap {
  static double clampHeight({
    required double desired,
    required double viewportHeight,
    double minHeight = 120,
    double maxFraction = 0.55,
    double absoluteMax = double.infinity,
  }) {
    if (viewportHeight <= 0) return minHeight;
    final cap = (viewportHeight * maxFraction).clamp(minHeight, absoluteMax);
    if (desired <= minHeight) return minHeight;
    if (desired >= cap) return cap;
    return desired;
  }
}

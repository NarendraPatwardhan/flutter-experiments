// Expand-for-reading then hard-cap (docs/ui-northstar.md §4.10).

/// Layout helper: grow content height, then clamp into a scrollable region.
class ExpandCap {
  ExpandCap._();

  /// Clamp [desired] height into [minHeight]..[maxHeight].
  ///
  /// [maxHeight] is typically `viewport * maxFraction` (e.g. 0.55).
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

  /// Whether [desired] exceeded the cap (caller should enable scroll).
  static bool needsScroll({
    required double desired,
    required double viewportHeight,
    double minHeight = 120,
    double maxFraction = 0.55,
  }) {
    final h = clampHeight(
      desired: desired,
      viewportHeight: viewportHeight,
      minHeight: minHeight,
      maxFraction: maxFraction,
    );
    return desired > h + 0.5;
  }

  /// Minimum height reserved for the live terminal / active region when
  /// history is present (fraction of remaining body below top/bottom bars).
  static double minActiveHeight(double bodyHeight, {double fraction = 0.35}) {
    if (bodyHeight <= 0) return 120;
    return (bodyHeight * fraction).clamp(120.0, bodyHeight);
  }
}

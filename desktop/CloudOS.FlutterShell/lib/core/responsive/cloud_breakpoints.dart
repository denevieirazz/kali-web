enum CloudBreakpoint {
  compact,
  medium,
  large,
  wide;

  static CloudBreakpoint fromWidth(double width, {bool isPortrait = false}) {
    if (isPortrait && width < 900) return CloudBreakpoint.compact;
    if (width < 840) return CloudBreakpoint.compact;
    if (width < 1280) return CloudBreakpoint.medium;
    if (width < 1920) return CloudBreakpoint.large;
    return CloudBreakpoint.wide;
  }

  bool get isCompact => this == CloudBreakpoint.compact;
  bool get isMedium => this == CloudBreakpoint.medium;
  bool get isLarge => this == CloudBreakpoint.large;
  bool get isWide => this == CloudBreakpoint.wide;
}

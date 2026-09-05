import 'package:flutter/material.dart';
import 'cloud_breakpoints.dart';
import 'cloud_layout_metrics.dart';

class CloudResponsiveScope extends InheritedWidget {
  const CloudResponsiveScope({
    required this.metrics,
    required super.child,
    super.key,
  });

  final CloudLayoutMetrics metrics;

  static CloudLayoutMetrics of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CloudResponsiveScope>();
    if (scope != null) return scope.metrics;

    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null) {
      return CloudLayoutMetrics.fromSize(mediaQuery.size);
    }
    return const CloudLayoutMetrics(screenWidth: 1920, screenHeight: 1080);
  }

  @override
  bool updateShouldNotify(CloudResponsiveScope oldWidget) {
    return oldWidget.metrics.screenWidth != metrics.screenWidth ||
        oldWidget.metrics.screenHeight != metrics.screenHeight;
  }
}

extension CloudResponsiveContext on BuildContext {
  CloudLayoutMetrics get cloudMetrics => CloudResponsiveScope.of(this);
  CloudBreakpoint get cloudBreakpoint => cloudMetrics.breakpoint;
  bool get isCompact => cloudMetrics.isCompact;
  bool get isMedium => cloudMetrics.isMedium;
  bool get isLarge => cloudMetrics.isLarge;
  bool get isWide => cloudMetrics.isWide;
  bool get isPortrait => cloudMetrics.isPortrait;
  bool get isLandscape => cloudMetrics.isLandscape;
}

class CloudResponsiveBuilder extends StatelessWidget {
  const CloudResponsiveBuilder({
    required this.builder,
    super.key,
  });

  final Widget Function(BuildContext context, CloudLayoutMetrics metrics) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = CloudLayoutMetrics.fromConstraints(constraints);
        return CloudResponsiveScope(
          metrics: metrics,
          child: builder(context, metrics),
        );
      },
    );
  }
}

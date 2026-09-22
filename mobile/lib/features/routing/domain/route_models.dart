import 'dart:collection';

import 'package:nadr_mobile/core/geo/geo_coordinate.dart';

enum RouteMode { normal, safe, drifted, imu }

enum RiskZone { low, medium, high }

final class RiskSegmentCounts {
  const RiskSegmentCounts({
    required this.low,
    required this.medium,
    required this.high,
  });

  final int low;
  final int medium;
  final int high;
}

final class RouteMetrics {
  const RouteMetrics({
    this.distanceMeters,
    this.estimatedTimeSeconds,
    this.totalRiskScore,
    this.maximumRiskZone,
    this.averageRisk,
    this.riskSegments,
  });

  final double? distanceMeters;
  final double? estimatedTimeSeconds;
  final double? totalRiskScore;
  final RiskZone? maximumRiskZone;
  final double? averageRisk;
  final RiskSegmentCounts? riskSegments;
}

final class RouteAlternative {
  RouteAlternative({
    required this.mode,
    required List<GeoCoordinate> path,
    required this.metrics,
    this.optimization,
    this.riskWeight,
    this.description,
  }) : path = List.unmodifiable(path);

  final RouteMode mode;
  final List<GeoCoordinate> path;
  final RouteMetrics metrics;
  final String? optimization;
  final double? riskWeight;
  final String? description;
}

final class RouteMetadata {
  const RouteMetadata({this.start, this.end, this.source, this.kpIndex});

  final GeoCoordinate? start;
  final GeoCoordinate? end;
  final String? source;
  final double? kpIndex;
}

final class RouteAlternatives {
  RouteAlternatives({
    Map<RouteMode, RouteAlternative> byMode = const {},
    this.metadata,
  }) : _byMode = Map.unmodifiable(byMode);

  factory RouteAlternatives.empty() => RouteAlternatives();

  final Map<RouteMode, RouteAlternative> _byMode;
  final RouteMetadata? metadata;

  UnmodifiableMapView<RouteMode, RouteAlternative> get byMode =>
      UnmodifiableMapView(_byMode);

  RouteAlternative? operator [](RouteMode mode) => _byMode[mode];

  bool get isEmpty => _byMode.isEmpty;

  bool get isNotEmpty => _byMode.isNotEmpty;
}

import 'package:nadr_mobile/core/geo/geo_coordinate.dart';

abstract interface class RiskRepository<RiskSnapshot> {
  Future<RiskSnapshot> getCurrentRisk(GeoCoordinate coordinate);
}

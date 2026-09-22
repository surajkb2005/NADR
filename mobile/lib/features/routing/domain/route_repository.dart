import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

abstract interface class RouteRepository {
  Future<RouteAlternatives> calculateRoute({
    required GeoCoordinate start,
    required GeoCoordinate end,
    RouteMode mode = RouteMode.normal,
  });
}

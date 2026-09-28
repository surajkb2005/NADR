import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/presentation/route_camera_fit.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

void main() {
  test('bounds include the full bent path, current start, and destination', () {
    final fit = RouteCameraFit.forRoute(
      route: _route(const [
        GeoCoordinate(latitude: 12, longitude: 77),
        GeoCoordinate(latitude: 15, longitude: 74),
        GeoCoordinate(latitude: 13, longitude: 78),
      ]),
      start: const GeoCoordinate(latitude: 11, longitude: 76),
      destination: const GeoCoordinate(latitude: 14, longitude: 80),
      viewportWidth: 390,
      viewportHeight: 800,
      topInset: 24,
      bottomInset: 20,
    )!;
    expect(
      fit.bounds.southWest,
      const GeoCoordinate(latitude: 11, longitude: 74),
    );
    expect(
      fit.bounds.northEast,
      const GeoCoordinate(latitude: 15, longitude: 80),
    );
  });

  test('short route gets nonzero span; absent route has no fit', () {
    final fit = RouteCameraFit.forRoute(
      route: _route(const [
        GeoCoordinate(latitude: 12, longitude: 77),
        GeoCoordinate(latitude: 12.00001, longitude: 77.00001),
      ]),
      start: null,
      destination: null,
      viewportWidth: 320,
      viewportHeight: 600,
      topInset: 0,
      bottomInset: 0,
    )!;
    expect(
      fit.bounds.northEast.latitude - fit.bounds.southWest.latitude,
      greaterThanOrEqualTo(0.001 - 1e-8),
    );
    expect(
      fit.bounds.northEast.longitude - fit.bounds.southWest.longitude,
      greaterThanOrEqualTo(0.001 - 1e-8),
    );
    expect(
      RouteCameraFit.forRoute(
        route: null,
        start: null,
        destination: null,
        viewportWidth: 320,
        viewportHeight: 600,
        topInset: 0,
        bottomInset: 0,
      ),
      isNull,
    );
  });

  test('padding reserves search, sheet, controls, and system insets', () {
    RouteCameraFit fit(
      double width,
      double height,
      double top,
      double bottom,
    ) => RouteCameraFit.forRoute(
      route: _route(const [
        GeoCoordinate(latitude: 12, longitude: 77),
        GeoCoordinate(latitude: 13, longitude: 78),
      ]),
      start: null,
      destination: null,
      viewportWidth: width,
      viewportHeight: height,
      topInset: top,
      bottomInset: bottom,
    )!;
    final phone = fit(390, 800, 24, 20).padding;
    final noInsets = fit(390, 800, 0, 0).padding;
    final narrow = fit(280, 560, 20, 20).padding;
    expect(phone.top, greaterThan(noInsets.top));
    expect(phone.bottom, greaterThan(noInsets.bottom));
    expect(phone.bottom, greaterThan(800 * 0.20));
    expect(phone.left, greaterThan(0));
    expect(narrow.left, lessThan(phone.left));
    expect(narrow.top + narrow.bottom, lessThan(560));
  });
}

RouteAlternative _route(List<GeoCoordinate> path) => RouteAlternative(
  mode: RouteMode.normal,
  path: path,
  metrics: const RouteMetrics(),
);

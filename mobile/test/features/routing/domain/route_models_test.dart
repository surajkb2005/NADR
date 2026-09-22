import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

void main() {
  test('route paths and alternative maps are immutable', () {
    final sourcePath = <GeoCoordinate>[
      const GeoCoordinate(latitude: 12, longitude: 77),
    ];
    final alternative = RouteAlternative(
      mode: RouteMode.normal,
      path: sourcePath,
      metrics: const RouteMetrics(),
    );
    final sourceMap = <RouteMode, RouteAlternative>{
      RouteMode.normal: alternative,
    };
    final alternatives = RouteAlternatives(byMode: sourceMap);

    sourcePath.add(const GeoCoordinate(latitude: 13, longitude: 78));
    sourceMap.clear();

    expect(alternative.path, hasLength(1));
    expect(alternatives[RouteMode.normal], same(alternative));
    expect(
      () => alternatives.byMode[RouteMode.safe] = alternative,
      throwsUnsupportedError,
    );
  });
}

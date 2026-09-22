import 'package:geolocator/geolocator.dart';

/// geolocator_android 5.0.3 copies numeric accuracy into AndroidPosition but
/// does not forward Position.hasAccuracy through its constructor. The native
/// mapper only sends a nonzero numeric value when Location.hasAccuracy().
abstract final class GpsAccuracy {
  static bool isReported(Position position) =>
      position.hasAccuracy ||
      (position is AndroidPosition && position.accuracy != 0);

  static double? measuredMeters(Position position) =>
      isReported(position) &&
          position.accuracy.isFinite &&
          position.accuracy > 0
      ? position.accuracy
      : null;
}

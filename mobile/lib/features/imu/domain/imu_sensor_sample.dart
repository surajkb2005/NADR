final class ImuSensorSample {
  const ImuSensorSample({
    required this.linearAccelerationX,
    required this.linearAccelerationY,
    required this.linearAccelerationZ,
    required this.timestamp,
    this.heading,
    this.headingAccuracyDegrees,
    this.angularVelocityRadiansPerSecond,
    this.stepDetected = false,
    this.isDecayTick = false,
  });

  final double linearAccelerationX;
  final double linearAccelerationY;
  final double linearAccelerationZ;
  final double? heading;
  final double? headingAccuracyDegrees;
  final double? angularVelocityRadiansPerSecond;
  final DateTime timestamp;

  /// True only for an Android TYPE_STEP_DETECTOR event.
  ///
  /// Raw acceleration remains available for diagnostics, but is not treated
  /// as proof of geographic travel by the Android movement estimator.
  final bool stepDetected;

  /// The website's 200 ms decay/position integration tick, not a sensor event.
  final bool isDecayTick;
}

final class ImuSensorSample {
  const ImuSensorSample({
    required this.linearAccelerationX,
    required this.linearAccelerationY,
    required this.linearAccelerationZ,
    required this.timestamp,
    this.heading,
    this.isDecayTick = false,
  });

  final double linearAccelerationX;
  final double linearAccelerationY;
  final double linearAccelerationZ;
  final double? heading;
  final DateTime timestamp;

  /// The website's 200 ms decay/position integration tick, not a sensor event.
  final bool isDecayTick;
}

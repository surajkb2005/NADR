enum ImuNavigationPhase {
  stopped,
  waitingForGps,
  starting,
  active,
  unavailable,
  headingUnavailable,
  error,
  paused,
}

final class ImuNavigationState {
  const ImuNavigationState(this.phase);

  final ImuNavigationPhase phase;

  String get label => switch (phase) {
    ImuNavigationPhase.stopped => 'IMU stopped',
    ImuNavigationPhase.waitingForGps => 'IMU waiting for GPS',
    ImuNavigationPhase.starting => 'Starting IMU sensors…',
    ImuNavigationPhase.active => 'IMU estimation active',
    ImuNavigationPhase.unavailable => 'IMU sensors unavailable',
    ImuNavigationPhase.headingUnavailable => 'IMU heading unavailable',
    ImuNavigationPhase.error => 'IMU sensor error',
    ImuNavigationPhase.paused => 'IMU paused',
  };
}

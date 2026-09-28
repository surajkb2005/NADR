import 'package:flutter/material.dart' hide NavigationMode;
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

/// Typed, presentation-only snapshot of real navigation status.
///
/// Build this via [NavigationStatusData.fromSessionState] from the app's
/// actual [NavigationSessionState] / [DeviceLocationState] / optional
/// [ImuNavigationState]. This is not a new state store — it reads existing
/// state and reshapes it for display. Construct fake instances directly
/// only in widget tests/previews.
@immutable
final class NavigationStatusData {
  const NavigationStatusData({
    required this.mode,
    required this.hasGpsFix,
    this.gpsAccuracyMeters,
    this.headingDegrees,
    this.imuPhase,
    this.locationState,
  });

  final NavigationMode mode;
  final bool hasGpsFix;

  /// Null means "not reported" — not zero, not unknown-as-zero.
  final double? gpsAccuracyMeters;

  /// A validated heading in degrees, or null when no valid heading exists.
  /// A missing heading is intentionally never coerced to 0°.
  final double? headingDegrees;

  final ImuNavigationPhase? imuPhase;
  final DeviceLocationState? locationState;

  factory NavigationStatusData.fromSessionState({
    required NavigationSessionState session,
    ImuNavigationState? imuState,
    DeviceLocationState? locationState,
  }) {
    final displayed = session.displayedPosition;
    return NavigationStatusData(
      mode: session.navigationMode,
      hasGpsFix: session.hasGpsFix,
      gpsAccuracyMeters:
          session.navigationMode == NavigationMode.gps &&
              displayed?.horizontalAccuracyMeters != null &&
              displayed!.horizontalAccuracyMeters!.isFinite &&
              displayed.horizontalAccuracyMeters! >= 0
          ? displayed.horizontalAccuracyMeters
          : null,
      headingDegrees: _validHeading(displayed?.heading, imuState),
      imuPhase: imuState?.phase,
      locationState: locationState,
    );
  }

  static const _unreliableImuPhases = {
    ImuNavigationPhase.stopped,
    ImuNavigationPhase.waitingForGps,
    ImuNavigationPhase.starting,
    ImuNavigationPhase.calibrating,
    ImuNavigationPhase.unavailable,
    ImuNavigationPhase.headingUnavailable,
    ImuNavigationPhase.error,
    ImuNavigationPhase.paused,
  };

  static double? _validHeading(double? heading, ImuNavigationState? imu) {
    if (heading == null || !heading.isFinite) return null;
    if (imu != null && _unreliableImuPhases.contains(imu.phase)) return null;
    return heading;
  }
}

/// Compact Material 3 panel showing real GPS/IMU navigation mode, GPS
/// accuracy (when reported), IMU phase, and heading availability.
///
/// Purely presentational: no sensor polling, no timers, no new controller.
class NavigationStatusPanel extends StatelessWidget {
  const NavigationStatusPanel({required this.data, super.key});

  final NavigationStatusData data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: 'Navigation status',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _modeChip(colors),
          if (data.mode == NavigationMode.gps)
            _gpsAccuracyChip(colors)
          else
            _imuPhaseChip(colors),
          if (data.mode == NavigationMode.gps && data.locationState != null)
            _trackingChip(colors),
          _headingChip(colors),
        ],
      ),
    );
  }

  Widget _modeChip(ColorScheme colors) => CompactStatusChip(
    key: const ValueKey('nav-status-mode'),
    label: data.mode == NavigationMode.gps ? 'GPS mode' : 'IMU mode',
    icon: data.mode == NavigationMode.gps
        ? Icons.satellite_alt_rounded
        : Icons.explore_rounded,
    color: colors.primary,
  );

  Widget _gpsAccuracyChip(ColorScheme colors) {
    if (!data.hasGpsFix) {
      return CompactStatusChip(
        key: const ValueKey('nav-status-gps'),
        label: 'No GPS fix',
        icon: Icons.gps_off_rounded,
        color: colors.error,
      );
    }
    final accuracy = data.gpsAccuracyMeters;
    return CompactStatusChip(
      key: const ValueKey('nav-status-gps'),
      label: accuracy != null
          ? '±${accuracy.toStringAsFixed(0)} m'
          : 'Accuracy unknown',
      icon: Icons.my_location_rounded,
      color: accuracy != null ? const Color(0xFF188038) : colors.outline,
    );
  }

  Widget _imuPhaseChip(ColorScheme colors) {
    final phase = data.imuPhase;
    if (phase == null) {
      return CompactStatusChip(
        key: const ValueKey('nav-status-imu'),
        label: 'IMU unknown',
        icon: Icons.help_outline_rounded,
        color: colors.outline,
      );
    }
    final isProblem = switch (phase) {
      ImuNavigationPhase.unavailable ||
      ImuNavigationPhase.headingUnavailable ||
      ImuNavigationPhase.error => true,
      _ => false,
    };
    final isActive = phase == ImuNavigationPhase.active;
    return CompactStatusChip(
      key: const ValueKey('nav-status-imu'),
      label: _shortImuLabel(phase),
      icon: isActive
          ? Icons.explore_rounded
          : isProblem
          ? Icons.explore_off_rounded
          : Icons.hourglass_top_rounded,
      color: isActive
          ? const Color(0xFF188038)
          : isProblem
          ? colors.error
          : colors.primary,
    );
  }

  Widget _trackingChip(ColorScheme colors) {
    final location = data.locationState!;
    final unavailable =
        location.serviceStatus == LocationServiceStatus.disabled ||
        location.permissionStatus == LocationPermissionStatus.denied ||
        location.permissionStatus == LocationPermissionStatus.deniedForever ||
        location.trackingStatus == LocationTrackingStatus.error;
    final active =
        !unavailable &&
        location.trackingStatus == LocationTrackingStatus.active;
    return CompactStatusChip(
      key: const ValueKey('nav-status-tracking'),
      label: unavailable
          ? 'GPS unavailable'
          : active
          ? 'GPS tracking'
          : 'GPS waiting',
      icon: unavailable
          ? Icons.gps_off_rounded
          : active
          ? Icons.gps_fixed_rounded
          : Icons.gps_not_fixed_rounded,
      color: unavailable
          ? colors.error
          : active
          ? const Color(0xFF188038)
          : colors.primary,
    );
  }

  static String _shortImuLabel(ImuNavigationPhase phase) => switch (phase) {
    ImuNavigationPhase.stopped => 'IMU stopped',
    ImuNavigationPhase.waitingForGps => 'Waiting for GPS',
    ImuNavigationPhase.starting => 'Starting IMU',
    ImuNavigationPhase.calibrating => 'Calibrating',
    ImuNavigationPhase.active => 'IMU active',
    ImuNavigationPhase.unavailable => 'IMU unavailable',
    ImuNavigationPhase.headingUnavailable => 'No heading',
    ImuNavigationPhase.error => 'IMU error',
    ImuNavigationPhase.paused => 'IMU paused',
  };

  Widget _headingChip(ColorScheme colors) {
    final heading = data.headingDegrees;
    if (heading == null) {
      return CompactStatusChip(
        key: const ValueKey('nav-status-heading'),
        label: 'Heading unavailable',
        icon: Icons.explore_off_outlined,
        color: colors.outline,
      );
    }
    return CompactStatusChip(
      key: const ValueKey('nav-status-heading'),
      label: '${heading.toStringAsFixed(0)}°',
      icon: Icons.navigation_rounded,
      color: colors.primary,
    );
  }
}

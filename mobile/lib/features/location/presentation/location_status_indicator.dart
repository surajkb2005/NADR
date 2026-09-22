import 'package:flutter/material.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

class LocationStatusIndicator extends StatelessWidget {
  const LocationStatusIndicator({required this.state, super.key});

  final DeviceLocationState state;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(context, state);
    return CompactStatusChip(
      key: const ValueKey('location-status-indicator'),
      label: presentation.label,
      icon: presentation.icon,
      color: presentation.color,
    );
  }

  static _LocationStatusPresentation _presentationFor(
    BuildContext context,
    DeviceLocationState state,
  ) {
    final colors = Theme.of(context).colorScheme;

    if (state.serviceStatus == LocationServiceStatus.disabled) {
      return _LocationStatusPresentation(
        label: 'Location services disabled',
        icon: Icons.location_disabled_rounded,
        color: colors.error,
      );
    }

    switch (state.permissionStatus) {
      case LocationPermissionStatus.deniedForever:
        return _LocationStatusPresentation(
          label: 'Location permission blocked',
          icon: Icons.gpp_bad_outlined,
          color: colors.error,
        );
      case LocationPermissionStatus.denied:
        return _LocationStatusPresentation(
          label: 'Location permission denied',
          icon: Icons.location_off_outlined,
          color: colors.error,
        );
      case LocationPermissionStatus.notRequested ||
          LocationPermissionStatus.granted:
        break;
    }

    return switch (state.trackingStatus) {
      LocationTrackingStatus.active => _LocationStatusPresentation(
        label: 'Location active',
        icon: Icons.gps_fixed_rounded,
        color: const Color(0xFF188038),
      ),
      LocationTrackingStatus.error => _LocationStatusPresentation(
        label: 'Location unavailable',
        icon: Icons.gps_off_rounded,
        color: colors.error,
      ),
      LocationTrackingStatus.stopped ||
      LocationTrackingStatus.starting ||
      LocationTrackingStatus.acquiring => _LocationStatusPresentation(
        label: 'Getting location…',
        icon: Icons.gps_not_fixed_rounded,
        color: colors.primary,
      ),
    };
  }
}

final class _LocationStatusPresentation {
  const _LocationStatusPresentation({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

import 'package:flutter/material.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;

class NavigationModeControl extends StatelessWidget {
  const NavigationModeControl({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final domain.NavigationMode mode;
  final ValueChanged<domain.NavigationMode> onModeChanged;

  static const _imuLight = Color(0xFF6F42C1);
  static const _imuDark = Color(0xFFD0BCFF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedColor = switch (mode) {
      domain.NavigationMode.gps => colorScheme.primary,
      domain.NavigationMode.imu =>
        theme.brightness == Brightness.dark ? _imuDark : _imuLight,
    };

    return Material(
      key: const ValueKey('navigation-mode-control'),
      elevation: 3,
      color: colorScheme.surfaceContainerHigh,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<domain.NavigationMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: domain.NavigationMode.gps,
              icon: Icon(Icons.location_on_outlined),
              label: Text('GPS'),
            ),
            ButtonSegment(
              value: domain.NavigationMode.imu,
              icon: Icon(Icons.explore_outlined),
              label: Text('IMU'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => onModeChanged(selection.single),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(88, 48)),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? selectedColor
                  : colorScheme.onSurfaceVariant;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? selectedColor.withValues(alpha: 0.14)
                  : Colors.transparent;
            }),
            side: WidgetStatePropertyAll(
              BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }
}

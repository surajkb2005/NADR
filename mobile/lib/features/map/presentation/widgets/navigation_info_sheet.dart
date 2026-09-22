import 'package:flutter/material.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/shared/widgets/bottom_sheet_surface.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

class NavigationInfoSheet extends StatelessWidget {
  const NavigationInfoSheet({required this.mode, super.key});

  final domain.NavigationMode mode;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const ValueKey('navigation-info-sheet'),
      initialChildSize: 0.20,
      minChildSize: 0.16,
      maxChildSize: 0.48,
      snap: true,
      builder: (context, scrollController) {
        return BottomSheetSurface(
          scrollController: scrollController,
          child: _NavigationInfoContent(mode: mode),
        );
      },
    );
  }
}

class _NavigationInfoContent extends StatelessWidget {
  const _NavigationInfoContent({required this.mode});

  final domain.NavigationMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGps = mode == domain.NavigationMode.gps;
    final statusColor = isGps
        ? theme.colorScheme.primary
        : theme.brightness == Brightness.dark
        ? const Color(0xFFD0BCFF)
        : const Color(0xFF6F42C1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'NADR Navigation',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            CompactStatusChip(
              label: isGps ? 'GPS' : 'IMU',
              icon: isGps ? Icons.location_on_outlined : Icons.explore_outlined,
              color: statusColor,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'No destination selected',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select a destination to view route information.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

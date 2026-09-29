import 'package:flutter/material.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';

/// Read-only presentation of the current confirmed destination.
///
/// Displays only fields the real [Destination] model provides. Does not
/// invent a place name when [Destination.displayLabel] is absent — falls
/// back to coordinates instead.
class DestinationInfoCard extends StatelessWidget {
  const DestinationInfoCard({this.destination, super.key});

  final Destination? destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destination = this.destination;

    if (destination == null) {
      return Card.filled(
        key: const ValueKey('destination-info-card-empty'),
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            Icons.location_searching_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: const Text('No destination selected'),
          subtitle: const Text('Choose a destination to see route details.'),
        ),
      );
    }

    final coordinate = destination.coordinate;
    final label = destination.displayLabel;

    return Card.filled(
      key: const ValueKey('destination-info-card'),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(
          Icons.location_on_rounded,
          color: Color(0xFFE65100),
        ),
        title: Text(
          label ?? '${coordinate.latitude}, ${coordinate.longitude}',
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: label != null
            ? Text(
                '${coordinate.latitude}, ${coordinate.longitude}',
                overflow: TextOverflow.ellipsis,
              )
            : null,
      ),
    );
  }
}

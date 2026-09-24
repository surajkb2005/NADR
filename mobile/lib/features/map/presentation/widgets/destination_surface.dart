import 'package:flutter/material.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';

class DestinationSurface extends StatelessWidget {
  const DestinationSurface({
    required this.destination,
    required this.onPressed,
    super.key,
  });

  final Destination? destination;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        elevation: 3,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('destination-surface'),
          onTap: onPressed,
          child: Semantics(
            button: true,
            label: destination == null
                ? 'Choose destination'
                : 'Change destination',
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 48,
                      child: Icon(
                        destination == null
                            ? Icons.add_location_alt_outlined
                            : Icons.location_on_rounded,
                        color: destination == null
                            ? null
                            : const Color(0xFFE65100),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        destination == null
                            ? 'Choose destination'
                            : '${destination!.coordinate.latitude}, '
                                  '${destination!.coordinate.longitude}',
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(7),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFFFFDE7),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/branding/nadr_logo.jpeg',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            semanticLabel: 'NADR',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

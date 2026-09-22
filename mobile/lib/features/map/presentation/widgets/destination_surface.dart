import 'package:flutter/material.dart';

class DestinationSurface extends StatelessWidget {
  const DestinationSurface({super.key});

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
        child: Semantics(
          label: 'Destination selection is not yet available',
          textField: true,
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.search_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Choose destination',
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
    );
  }
}

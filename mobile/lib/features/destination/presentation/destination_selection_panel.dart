import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';

String? validateLatitude(String? value) =>
    _validateCoordinate(value, name: 'latitude', minimum: -90, maximum: 90);

String? validateLongitude(String? value) =>
    _validateCoordinate(value, name: 'longitude', minimum: -180, maximum: 180);

String? _validateCoordinate(
  String? value, {
  required String name,
  required double minimum,
  required double maximum,
}) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return 'Enter a $name.';
  final parsed = double.tryParse(normalized);
  if (parsed == null) return 'Enter a valid number.';
  if (!parsed.isFinite) return 'Enter a finite number.';
  if (parsed < minimum || parsed > maximum) {
    return '${name[0].toUpperCase()}${name.substring(1)} must be between '
        '${minimum.toInt()} and ${maximum.toInt()}.';
  }
  return null;
}

class DestinationSelectionPanel extends StatefulWidget {
  const DestinationSelectionPanel({
    required this.destination,
    required this.onSelectOnMap,
    required this.onConfirm,
    required this.onClear,
    super.key,
  });

  final Destination? destination;
  final VoidCallback onSelectOnMap;
  final ValueChanged<Destination> onConfirm;
  final VoidCallback onClear;

  @override
  State<DestinationSelectionPanel> createState() =>
      _DestinationSelectionPanelState();
}

class _DestinationSelectionPanelState extends State<DestinationSelectionPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;

  @override
  void initState() {
    super.initState();
    final coordinate = widget.destination?.coordinate;
    _latitudeController = TextEditingController(
      text: coordinate?.latitude.toString() ?? '',
    );
    _longitudeController = TextEditingController(
      text: coordinate?.longitude.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _confirmCoordinates() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final destination = Destination(
      coordinate: GeoCoordinate(
        latitude: double.parse(_latitudeController.text.trim()),
        longitude: double.parse(_longitudeController.text.trim()),
      ),
    );
    widget.onConfirm(destination);
    Navigator.of(context).pop();
  }

  void _selectOnMap() {
    widget.onSelectOnMap();
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onClear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose destination',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('close-destination-panel'),
                      tooltip: 'Cancel destination selection',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a point on the map or enter exact coordinates.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.destination case final destination?) ...[
                  const SizedBox(height: 16),
                  _CurrentDestinationCard(destination: destination),
                ],
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: const ValueKey('select-destination-on-map'),
                  onPressed: _selectOnMap,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Select a point on the map'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR ENTER COORDINATES'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
                Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final latitudeField = TextFormField(
                        key: const ValueKey('destination-latitude-field'),
                        controller: _latitudeController,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          hintText: '-90 to 90',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        validator: validateLatitude,
                        textInputAction: TextInputAction.next,
                      );
                      final longitudeField = TextFormField(
                        key: const ValueKey('destination-longitude-field'),
                        controller: _longitudeController,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          hintText: '-180 to 180',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        validator: validateLongitude,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _confirmCoordinates(),
                      );
                      return constraints.maxWidth >= 480
                          ? Row(
                              children: [
                                Expanded(child: latitudeField),
                                const SizedBox(width: 12),
                                Expanded(child: longitudeField),
                              ],
                            )
                          : Column(
                              children: [
                                latitudeField,
                                const SizedBox(height: 12),
                                longitudeField,
                              ],
                            );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('confirm-coordinate-destination'),
                  onPressed: _confirmCoordinates,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    widget.destination == null
                        ? 'Confirm destination'
                        : 'Replace destination',
                  ),
                ),
                if (widget.destination != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const ValueKey('clear-destination'),
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Clear destination'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DestinationReviewPanel extends StatelessWidget {
  const DestinationReviewPanel({
    required this.coordinate,
    required this.onConfirm,
    super.key,
  });

  final GeoCoordinate coordinate;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Confirm destination',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Latitude: ${coordinate.latitude}'),
                Text('Longitude: ${coordinate.longitude}'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('cancel-map-destination'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('confirm-map-destination'),
                        onPressed: () {
                          onConfirm();
                          Navigator.of(context).pop();
                        },
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentDestinationCard extends StatelessWidget {
  const _CurrentDestinationCard({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) {
    final coordinate = destination.coordinate;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(
          Icons.location_on_rounded,
          color: Color(0xFFE65100),
        ),
        title: const Text('Current destination'),
        subtitle: Text('${coordinate.latitude}, ${coordinate.longitude}'),
      ),
    );
  }
}

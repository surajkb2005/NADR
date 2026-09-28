import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/features/destination/application/place_search_controller.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';

/// Floating map search. The session destination remains owned by the caller.
class DestinationSearchSurface extends ConsumerStatefulWidget {
  const DestinationSearchSurface({
    required this.destination,
    required this.onSelect,
    required this.onOpenFallback,
    super.key,
  });

  final Destination? destination;
  final ValueChanged<Destination> onSelect;
  final VoidCallback onOpenFallback;

  @override
  ConsumerState<DestinationSearchSurface> createState() =>
      _DestinationSearchSurfaceState();
}

class _DestinationSearchSurfaceState
    extends ConsumerState<DestinationSearchSurface> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: _destinationText(widget.destination),
    );
  }

  @override
  void didUpdateWidget(covariant DestinationSearchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.destination != oldWidget.destination) {
      _textController.text = _destinationText(widget.destination);
      _showSuggestions = false;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static String _destinationText(Destination? destination) {
    if (destination == null) return '';
    return destination.displayLabel ??
        '${destination.coordinate.latitude}, ${destination.coordinate.longitude}';
  }

  void _clearEditing() {
    _textController.clear();
    ref.read(placeSearchControllerProvider.notifier).clear();
    setState(() => _showSuggestions = false);
    _focusNode.requestFocus();
  }

  void _select(PlaceSearchResult result) {
    final destination = result.toDestination();
    _textController.text = result.label;
    ref.read(placeSearchControllerProvider.notifier).clear();
    setState(() => _showSuggestions = false);
    _focusNode.unfocus();
    widget.onSelect(destination);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final search = ref.watch(placeSearchControllerProvider);
    final showPanel =
        _showSuggestions &&
        search.phase != PlaceSearchPhase.idle &&
        search.query == _textController.text.trim();

    return TapRegion(
      onTapOutside: (_) {
        if (mounted) setState(() => _showSuggestions = false);
        _focusNode.unfocus();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              key: const ValueKey('destination-search-surface'),
              elevation: 3,
              shadowColor: colors.shadow.withValues(alpha: 0.18),
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: TextField(
                key: const ValueKey('destination-search-field'),
                controller: _textController,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search destination',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_textController.text.isNotEmpty)
                        IconButton(
                          key: const ValueKey('clear-search-text'),
                          tooltip: 'Clear search text',
                          onPressed: _clearEditing,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      IconButton(
                        key: const ValueKey('destination-surface'),
                        tooltip: 'Choose on map or enter coordinates',
                        onPressed: () {
                          setState(() => _showSuggestions = false);
                          _focusNode.unfocus();
                          widget.onOpenFallback();
                        },
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
                ),
                onTap: () => setState(() => _showSuggestions = true),
                onChanged: (value) {
                  ref
                      .read(placeSearchControllerProvider.notifier)
                      .updateQuery(value);
                  setState(() => _showSuggestions = true);
                },
              ),
            ),
            if (showPanel) ...[
              const SizedBox(height: 6),
              Material(
                key: const ValueKey('destination-suggestions'),
                elevation: 3,
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: _suggestions(search),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestions(PlaceSearchState search) => switch (search.phase) {
    PlaceSearchPhase.idle => const SizedBox.shrink(),
    PlaceSearchPhase.loading => const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Searching…'),
        ],
      ),
    ),
    PlaceSearchPhase.results => ListView.builder(
      shrinkWrap: true,
      itemCount: search.results.length,
      itemBuilder: (context, index) {
        final result = search.results[index];
        return ListTile(
          key: ValueKey('place-result-$index'),
          leading: const Icon(Icons.place_outlined),
          title: Text(
            result.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: result.subtitle == null
              ? null
              : Text(
                  result.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _select(result),
        );
      },
    ),
    PlaceSearchPhase.empty => const ListTile(
      leading: Icon(Icons.search_off_rounded),
      title: Text('No results'),
    ),
    PlaceSearchPhase.failure => ListTile(
      leading: const Icon(Icons.error_outline_rounded),
      title: Text(
        search.errorKind == PlaceSearchErrorKind.unconfigured
            ? 'Search unavailable'
            : 'Search failed',
      ),
      subtitle: Text(search.errorMessage ?? 'Try again.'),
      trailing: TextButton(
        onPressed: () => ref
            .read(placeSearchControllerProvider.notifier)
            .updateQuery(_textController.text),
        child: const Text('Retry'),
      ),
    ),
  };
}

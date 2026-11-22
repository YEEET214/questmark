import 'package:flutter/material.dart';

import 'map_config.dart';

/// The map's attribution ("OpenFreeMap, © OpenMapTiles, Data ©
/// OpenStreetMap contributors"), required by the data licence (ODbL) and
/// by OpenFreeMap / OpenMapTiles.
///
/// A small "i" button in the bottom-right corner; tapping it opens a card
/// with the credits, and the ✕ (or the button again) closes it.
///
/// This replaces flutter_map's own attribution widget, which has to be
/// drawn *inside* the map, so the map buttons on top covered its popup
/// (user report, PR #10 review). This one is placed last in the page's
/// Stack, so it is always on top.
class MapAttribution extends StatefulWidget {
  const MapAttribution({super.key});

  @override
  State<MapAttribution> createState() => _MapAttributionState();
}

class _MapAttributionState extends State<MapAttribution> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_open) {
      return Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          key: const Key('attributionButton'),
          tooltip: 'Map credits',
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.info_outline),
          onPressed: _toggle,
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Card(
        key: const Key('attributionCard'),
        elevation: 4,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Map credits',
                        style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: _toggle,
                  ),
                ],
              ),
              for (final a in MapConfig.attributions)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(a, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

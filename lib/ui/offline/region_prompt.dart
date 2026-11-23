import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/offline_region.dart';
import '../../models/region_plan.dart';
import 'region_size_picker.dart';
import 'region_texts.dart';

/// "Download the map for your area?" (R11, PLAN.md D7, D26): shown at the
/// top of the map when the user is outside every downloaded region.
/// Nothing is downloaded unless they tap Download.
///
/// * Not now: hidden until the app is restarted.
/// * Don't ask again: hidden for good (it can be turned back on in
///   Offline maps).
class RegionPrompt extends StatefulWidget {
  const RegionPrompt({
    super.key,
    required this.center,
    required this.onDownload,
    required this.onNotNow,
    required this.onNever,
  });

  /// The user's position: the middle of the area.
  final GeoPoint center;
  final ValueChanged<RegionSize> onDownload;
  final VoidCallback onNotNow;
  final VoidCallback onNever;

  @override
  State<RegionPrompt> createState() => _RegionPromptState();
}

class _RegionPromptState extends State<RegionPrompt> {
  RegionSize _size = RegionSize.medium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = RegionPlan(widget.center, _size);
    return Card(
      key: const Key('regionPrompt'),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.download_for_offline_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Download the map for your area?',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 8, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'See the detailed map around you without a connection.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  RegionSizePicker(
                    selected: _size,
                    onChanged: (s) => setState(() => _size = s),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    regionEstimate(plan),
                    key: const Key('regionPromptEstimate'),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    regionNameNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  key: const Key('regionPromptNever'),
                  onPressed: widget.onNever,
                  child: const Text('Don\'t ask again'),
                ),
                TextButton(
                  key: const Key('regionPromptNotNow'),
                  onPressed: widget.onNotNow,
                  child: const Text('Not now'),
                ),
                TextButton(
                  key: const Key('regionPromptDownload'),
                  onPressed: () => widget.onDownload(_size),
                  child: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

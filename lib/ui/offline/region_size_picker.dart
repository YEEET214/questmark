import 'package:flutter/material.dart';

import '../../models/offline_region.dart';

/// Small / Medium / Large, for a region download.
class RegionSizePicker extends StatelessWidget {
  const RegionSizePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final RegionSize selected;
  final ValueChanged<RegionSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RegionSize>(
      key: const Key('regionSizePicker'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final s in RegionSize.values)
          ButtonSegment(
            value: s,
            label: Text(s.label, key: Key('regionSize-${s.name}')),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

import 'package:flutter/material.dart';

/// A small reminder in the map's bottom-left corner: how many tasks have
/// no location, and so aren't on the map.
///
/// Collapsed, it's a small circle with "!". Tapping it expands it into a
/// rounded rectangle reading "3 tasks without locations". Tapping again
/// collapses it. It starts collapsed, so it never covers much of the map,
/// and it's hidden entirely when every task has a location.
class MissingLocationBadge extends StatefulWidget {
  const MissingLocationBadge({super.key, required this.count});

  final int count;

  /// The expanded text, with correct singular/plural.
  static String label(int count) => count == 1
      ? '1 task without a location'
      : '$count tasks without locations';

  @override
  State<MissingLocationBadge> createState() => _MissingLocationBadgeState();
}

class _MissingLocationBadgeState extends State<MissingLocationBadge> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final fg = theme.colorScheme.onTertiaryContainer;
    final label = MissingLocationBadge.label(widget.count);

    return Semantics(
      button: true,
      expanded: _expanded,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.tertiaryContainer,
        elevation: 3,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('missingLocationBadge'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: Padding(
              // A 40 x 40 circle when collapsed; the same height as a pill
              // when expanded.
              padding: EdgeInsets.fromLTRB(8, 8, _expanded ? 16 : 8, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Text(
                        '!',
                        style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  if (_expanded) ...[
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(color: fg)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

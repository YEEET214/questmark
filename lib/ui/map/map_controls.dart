import 'package:flutter/material.dart';

/// The small button stack on the right of the map, in the style of
/// Google Maps:
///
/// * a toggle that shows or hides completed quests (PLAN.md D17);
/// * a "+ / −" zoom pair.
///
/// It's purely presentational: the map page owns the state and passes in
/// callbacks. A callback of `null` disables that button (e.g. "+" at the
/// maximum zoom).
class MapControls extends StatelessWidget {
  const MapControls({
    super.key,
    required this.showCompleted,
    required this.onToggleCompleted,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool showCompleted;
  final VoidCallback onToggleCompleted;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  /// Width and height of each button. Small, so the map stays visible.
  static const double buttonSize = 40;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Panel(
          child: _ControlButton(
            key: const Key('toggleCompletedButton'),
            tooltip: showCompleted ? 'Hide completed' : 'Show completed',
            icon: showCompleted
                ? Icons.check_circle
                : Icons.check_circle_outline,
            selected: showCompleted,
            onPressed: onToggleCompleted,
          ),
        ),
        const SizedBox(height: 8),
        _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ControlButton(
                key: const Key('zoomInButton'),
                tooltip: 'Zoom in',
                icon: Icons.add,
                onPressed: onZoomIn,
              ),
              const SizedBox(
                width: buttonSize - 16,
                child: Divider(height: 1, thickness: 1),
              ),
              _ControlButton(
                key: const Key('zoomOutButton'),
                tooltip: 'Zoom out',
                icon: Icons.remove,
                onPressed: onZoomOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: MapControls.buttonSize,
          child: Icon(
            icon,
            size: 22,
            color: onPressed == null
                ? scheme.onSurface.withValues(alpha: 0.38)
                : selected
                    ? scheme.primary
                    : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

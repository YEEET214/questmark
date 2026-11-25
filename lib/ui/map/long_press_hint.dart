import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';

/// A one-time tip on the map (PLAN.md D29): "Long-press the map to add a
/// quest at that spot." Long-pressing (PLAN.md D23) isn't something people
/// find by themselves.
///
/// Gone for good after "Got it", or once the user long-presses the map.
/// Shows nothing without a [SettingsController] (some tests).
class LongPressHint extends StatelessWidget {
  const LongPressHint({super.key});

  @override
  Widget build(BuildContext context) {
    final seen = context.select<SettingsController?, bool>(
        (s) => s?.longPressHintSeen ?? true);
    if (seen) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomLeft,
      child: Card(
        key: const Key('longPressHint'),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Tip: long-press the map to add a quest at that spot.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: const Key('longPressHintDismiss'),
                onPressed: () =>
                    context.read<SettingsController>().markLongPressHintSeen(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

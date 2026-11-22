import 'package:flutter/material.dart';

/// The "explain" step before the OS permission dialog (PLAN.md D8).
///
/// Shown at the top of the map while the app may still ask for location
/// access. The OS dialog only appears after the user taps "Allow", so they
/// know why the app is asking. "Not now" hides it for this app session;
/// the my-location button can still ask later.
class LocationPrompt extends StatelessWidget {
  const LocationPrompt({
    super.key,
    required this.onAllow,
    required this.onDismiss,
  });

  final VoidCallback onAllow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('locationPrompt'),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'See where you are among your quests',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 8),
              child: Text(
                'QuestMark shows your position on the map. It is only used '
                'while the app is open and never leaves your phone.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Not now')),
                TextButton(onPressed: onAllow, child: const Text('Allow')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

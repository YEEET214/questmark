import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';

/// Settings (PLAN.md D28), opened from the Quests page's "⋮" menu:
/// dark mode and high contrast. Changes apply at once and are saved.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Appearance',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          // A radio group: one of three, all visible at once.
          RadioGroup<AppThemeMode>(
            groupValue: s.themeMode,
            onChanged: (m) {
              if (m != null) s.setThemeMode(m);
            },
            child: Column(
              children: [
                for (final m in AppThemeMode.values)
                  RadioListTile<AppThemeMode>(
                    key: Key('themeMode-${m.name}'),
                    value: m,
                    title: Text(m == AppThemeMode.dark ? 'Dark mode' : m.label),
                    subtitle: m == AppThemeMode.system
                        ? const Text('Follows your phone\'s setting')
                        : null,
                  ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('highContrastSwitch'),
            secondary: const Icon(Icons.contrast),
            title: const Text('High contrast mode'),
            subtitle: const Text(
                'Stronger colours, text and outlines. The map itself is not '
                'changed.'),
            value: s.highContrast,
            onChanged: s.setHighContrast,
          ),
        ],
      ),
    );
  }
}

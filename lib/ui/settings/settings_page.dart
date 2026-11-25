import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/map_cache_controller.dart';
import '../../state/settings_controller.dart';
import '../formatting.dart';
import '../privacy_texts.dart';

/// Settings (PLAN.md D28, D29), opened from the Quests page's "⋮" menu:
/// dark mode and high contrast (changes apply at once and are saved), and
/// the map cache's size with "Clear".
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
          if (context.select<MapCacheController?, bool>((c) => c != null))
            const _StorageSection(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Privacy',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          // Moved here from under the address search (D31).
          const ListTile(
            key: Key('nominatimNote'),
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Address search'),
            subtitle: Text(nominatimPrivacyNote),
          ),
        ],
      ),
    );
  }
}

/// "Storage": the map cache's size, and "Clear" (D29). The size is read
/// again each time Settings opens, since the map adds tiles meanwhile.
class _StorageSection extends StatefulWidget {
  const _StorageSection();

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  @override
  void initState() {
    super.initState();
    context.read<MapCacheController>().refresh();
  }

  Future<void> _clear(MapCacheController cache) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Clear the map cache?'),
        content: const Text(
            'Maps you have browsed are downloaded again when you look at '
            'them. Downloaded areas and the world map are kept.'),
        actions: [
          TextButton(
              key: const Key('clearCacheNo'),
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('No')),
          TextButton(
              key: const Key('clearCacheYes'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Yes')),
        ],
      ),
    );
    if (yes ?? false) await cache.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<MapCacheController>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Storage',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        ListTile(
          key: const Key('mapCacheTile'),
          leading: const Icon(Icons.layers_outlined),
          title: const Text('Map cache'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cache.clearing
                    ? 'Clearing…'
                    : '${formatMegabytes(cache.sizeBytes)} of up to '
                        '${formatMegabytes(cache.maxBytes)}',
                key: const Key('mapCacheSize'),
              ),
              const Text('Maps you have browsed, kept for 30 days so they '
                  'load faster and work offline.'),
              if (cache.clearing)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(key: Key('mapCacheClearing')),
                ),
            ],
          ),
          isThreeLine: true,
          trailing: TextButton(
            key: const Key('clearCacheButton'),
            onPressed: cache.clearing || cache.sizeBytes == 0
                ? null
                : () => _clear(cache),
            child: const Text('Clear'),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/geo_point.dart';
import '../../models/offline_region.dart';
import '../../services/region_downloader.dart';
import '../../state/offline_maps_controller.dart';
import '../formatting.dart';
import 'region_select_page.dart';
import 'region_texts.dart';

/// The Offline maps screen (R11, PLAN.md D7, D26), opened from the map's
/// download button: the downloaded regions with their size and state, the
/// running download (pause), resume / rename / delete, and "Download an
/// area" to pick another place on the map.
class OfflineMapsPage extends StatelessWidget {
  const OfflineMapsPage({super.key, this.initialCenter, this.selectPage});

  /// Where "Download an area" starts: the map's centre.
  final GeoPoint? initialCenter;

  /// Builds the area picker. Tests can swap it.
  final Widget Function(GeoPoint? center)? selectPage;

  static Future<void> open(BuildContext context, {GeoPoint? center}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OfflineMapsPage(initialCenter: center)));

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OfflineMapsController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Offline maps')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('downloadAreaButton'),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Download an area'),
        onPressed: () => _pickArea(context, c),
      ),
      body: !c.hasLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                SwitchListTile(
                  key: const Key('offerMyAreaSwitch'),
                  title: const Text('Offer to download my area'),
                  subtitle: const Text(
                      'On the map, when you\'re outside every downloaded '
                      'area'),
                  value: c.offerMyArea,
                  onChanged: c.setOfferMyArea,
                ),
                const Divider(height: 1),
                if (c.regions.isEmpty)
                  Padding(
                    key: const Key('noRegions'),
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No offline maps yet. Downloaded areas show the '
                      'detailed map without a connection; elsewhere you see '
                      'the low-detail world map.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  for (final r in c.regions)
                    _RegionTile(
                      region: r,
                      progress:
                          c.activeRegionId == r.id ? c.progress : null,
                      deleting: c.isDeleting(r.id),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Offline maps use ${formatMegabytes(c.totalBytes)} on '
                      'this phone.',
                      key: const Key('offlineTotal'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _pickArea(BuildContext context, OfflineMapsController c) {
    if (c.isDownloading) {
      _snack(context, 'Wait for the current download, or pause it first.');
      return Future.value();
    }
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          selectPage?.call(initialCenter) ??
          RegionSelectPage(initialCenter: initialCenter),
    ));
  }
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

enum _Action { pause, resume, rename, delete }

/// Owns its text controller, so it is disposed only once the dialog's
/// closing animation is over.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});
  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        key: const Key('regionNameField'),
        controller: _text,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            key: const Key('regionNameSave'),
            onPressed: () => Navigator.pop(context, _text.text),
            child: const Text('Save')),
      ],
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.region,
    this.progress,
    this.deleting = false,
  });

  final OfflineRegion region;

  /// Shows "Deleting…" with a moving bar, and no menu, until it's gone.
  final bool deleting;

  /// Set while this region is downloading.
  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final r = region;
    final p = progress;
    final theme = Theme.of(context);
    final c = context.read<OfflineMapsController>();
    final details = p != null
        ? '${formatCount(p.doneTiles)} of ${formatCount(p.totalTiles)} '
            'tiles · ${formatMegabytes(p.downloadedBytes)}'
        : '${formatDate(r.createdAt.toLocal())} · ${formatMegabytes(r.bytes)}'
            ' · ${formatKm(r.plan.kmAcross)} across';
    return ListTile(
      key: Key('region-${r.id}'),
      leading: Icon(
        switch (r.status) {
          _ when deleting => Icons.delete_outline,
          _ when p != null => Icons.downloading,
          RegionStatus.complete ||
          RegionStatus.limitReached =>
            Icons.offline_pin_outlined,
          _ => Icons.pause_circle_outline,
        },
        color: theme.colorScheme.primary,
      ),
      title: Text(r.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              deleting
                  ? 'Deleting…'
                  : p != null
                      ? 'Downloading…'
                      : regionStatusText(r),
              key: Key('regionStatus-${r.id}')),
          Text(details),
          if (deleting)
            // No percentage to show: SQLite deletes and compacts in one go.
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(key: Key('regionDeleting')),
            )
          else if (p != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: p.fraction),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: deleting
          ? null
          : PopupMenuButton<_Action>(
        key: Key('regionMenu-${r.id}'),
        tooltip: 'More',
        onSelected: (a) => _act(context, c, a),
        itemBuilder: (_) => [
          if (p != null)
            const PopupMenuItem(
                key: Key('regionPause'),
                value: _Action.pause,
                child: Text('Pause'))
          else if (r.canResume)
            const PopupMenuItem(
                key: Key('regionResume'),
                value: _Action.resume,
                child: Text('Resume')),
          const PopupMenuItem(
              key: Key('regionRename'),
              value: _Action.rename,
              child: Text('Rename')),
          const PopupMenuItem(
              key: Key('regionDelete'),
              value: _Action.delete,
              child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _act(
      BuildContext context, OfflineMapsController c, _Action action) async {
    switch (action) {
      case _Action.pause:
        await c.pause();
      case _Action.resume:
        if (c.isDownloading) {
          _snack(context, 'Wait for the current download, or pause it first.');
        } else {
          await c.resume(region.id);
        }
      case _Action.rename:
        final name = await _askName(context, region.name);
        if (name != null) await c.rename(region.id, name);
      case _Action.delete:
        if (await _confirmDelete(context)) await c.delete(region.id);
    }
  }

  Future<String?> _askName(BuildContext context, String current) =>
      showDialog<String>(
        context: context,
        builder: (_) => _RenameDialog(current: current),
      );

  Future<bool> _confirmDelete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete "${region.name}"?'),
        content: const Text(
            'Its detailed map is removed from this phone. Map tiles that '
            'another downloaded area also uses are kept.'),
        actions: [
          TextButton(
              key: const Key('regionDeleteNo'),
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('No')),
          TextButton(
              key: const Key('regionDeleteYes'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Yes')),
        ],
      ),
    );
    return yes ?? false;
  }
}

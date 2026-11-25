import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../models/geo_point.dart';
import '../../models/offline_region.dart';
import '../../models/region_plan.dart';
import '../../state/offline_maps_controller.dart';
import '../map/base_map_layer.dart';
import '../map/geo_point_latlng.dart';
import '../map/map_attribution.dart';
import '../map/map_config.dart';
import 'region_size_picker.dart';
import 'region_texts.dart';

/// "Download an area" (R11, PLAN.md D7, D26): move the map until the
/// square frames the area, pick Small / Medium / Large, see the estimate,
/// and tap Download. Nothing is downloaded before that.
class RegionSelectPage extends StatefulWidget {
  const RegionSelectPage({
    super.key,
    this.initialCenter,
    this.baseLayer,
    this.mapController,
  });

  /// Where the map starts (the world map's centre). Defaults to the whole
  /// world.
  final GeoPoint? initialCenter;

  /// The base map. Defaults to the app-wide [MapBaseLayer].
  final Widget? baseLayer;

  /// Lets tests inspect the camera. The page creates its own if null.
  final MapController? mapController;

  @override
  State<RegionSelectPage> createState() => _RegionSelectPageState();
}

class _RegionSelectPageState extends State<RegionSelectPage> {
  late final MapController _map = widget.mapController ?? MapController();
  RegionSize _size = RegionSize.medium;
  late GeoPoint _center =
      widget.initialCenter ?? MapConfig.worldCenter.toPickedGeoPoint();
  double? _zoom;
  bool _starting = false;

  /// The map's size on screen, from the last layout.
  Size _view = Size.zero;

  /// The square's side on screen: [RegionSize.tilesAcross] zoom-14 tiles
  /// are 256 px each at zoom 14, half that per zoom level out.
  double _squarePx(double zoom) =>
      _size.tilesAcross * 256 * math.pow(2, zoom - RegionPlan.maxZoom).toDouble();

  /// The zoom at which the square fills ~70% of the shorter side.
  double _fittingZoom(Size view) {
    final side = 0.7 * math.min(view.width, view.height);
    final zoom = RegionPlan.maxZoom +
        math.log(side / (_size.tilesAcross * 256)) / math.ln2;
    return zoom.clamp(MapConfig.minZoom, MapConfig.maxZoom).toDouble();
  }

  @override
  void dispose() {
    if (widget.mapController == null) _map.dispose();
    super.dispose();
  }

  void _onMoved(MapCamera camera, bool _) {
    void update() {
      if (!mounted) return;
      setState(() {
        _center = camera.center.toPickedGeoPoint();
        _zoom = camera.zoom;
      });
    }

    // The map can report positions during layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  void _setSize(RegionSize size) {
    setState(() => _size = size);
    _map.move(_center.toLatLng(), _fittingZoom(_view));
  }

  Future<void> _download() async {
    final c = context.read<OfflineMapsController>();
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.download(_center, _size);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Downloading. You can leave this screen.')));
    } on StateError {
      if (!mounted) return;
      setState(() => _starting = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Another download is running. Pause it first.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseLayer = widget.baseLayer ?? context.read<MapBaseLayer>().layer;
    final theme = Theme.of(context);
    final plan = RegionPlan(_center, _size);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose an area')),
      body: LayoutBuilder(builder: (context, box) {
        final view = _view = box.biggest;
        final zoom = _zoom ?? _fittingZoom(view);
        return Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center.toLatLng(),
                initialZoom: _fittingZoom(view),
                minZoom: MapConfig.minZoom,
                maxZoom: MapConfig.maxZoom,
                onPositionChanged: _onMoved,
                // A square on a rotated map would be confusing.
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [baseLayer],
            ),
            IgnorePointer(
              child: CustomPaint(
                key: const Key('regionSquare'),
                painter: _SquarePainter(
                  side: _squarePx(zoom),
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const Positioned(right: 12, bottom: 12, child: MapAttribution()),
          ],
        );
      }),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // At most 40 % of the screen, scrolling inside, so a large
              // font size never pushes the map or the button away (D30).
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              Text(
                'Move the map to put the area in the square.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RegionSizePicker(
                selected: _size,
                onChanged: _setSize,
              ),
              const SizedBox(height: 6),
              Text(regionEstimate(plan),
                  key: const Key('regionSelectEstimate'),
                  style: theme.textTheme.bodyMedium),
              Text(
                '$regionEstimateNote $regionNameNote',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('regionSelectDownload'),
                icon: const Icon(Icons.download),
                label: const Text('Download this area'),
                onPressed: _starting ? null : _download,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Darkens the map outside a centred square and outlines it.
class _SquarePainter extends CustomPainter {
  _SquarePainter({required this.side, required this.color});

  final double side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final square = Rect.fromCenter(
        center: size.center(Offset.zero), width: side, height: side);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(square);
    canvas.drawPath(outside, Paint()..color = const Color(0x55000000));
    canvas.drawRect(
      square,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SquarePainter old) =>
      old.side != side || old.color != color;
}

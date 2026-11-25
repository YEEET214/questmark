import 'package:flutter/foundation.dart';

import '../data/tile_cache.dart';

/// The map's browse cache for the Settings page (PLAN.md D29): its size,
/// and clearing it. The cache itself is kept by the map (D27).
class MapCacheController extends ChangeNotifier {
  MapCacheController(this._cache, {required this.maxBytes})
      : _size = _cache.sizeBytes;

  final NetworkTileCache _cache;

  /// The cache's limit (100 MB, the user's choice: MapConfig), shown
  /// next to its size.
  final int maxBytes;

  int _size;
  bool _clearing = false;
  bool _disposed = false;

  int get sizeBytes => _size;

  /// Clearing takes a moment (SQLite also compacts the file).
  bool get clearing => _clearing;

  /// Reads the size again: the map adds tiles while it's used.
  void refresh() {
    if (_cache.sizeBytes == _size) return;
    _size = _cache.sizeBytes;
    _notify();
  }

  Future<void> clear() async {
    if (_clearing) return;
    _clearing = true;
    _notify();
    try {
      await _cache.clear();
    } catch (e) {
      debugPrint('Map cache could not be cleared: $e');
    } finally {
      _clearing = false;
      _size = _cache.sizeBytes;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

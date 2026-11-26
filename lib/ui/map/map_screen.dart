import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/providers.dart';
import '../../data/map/map_source_service.dart';
import '../../data/map/pmtiles_reader.dart';
import '../../domain/traffic/traffic_geojson.dart';
import '../../domain/traffic/traffic_models.dart';
import 'speed_limit_sign.dart';

/// Ban do offline (MapLibre doc PMTiles qua may chu tile 127.0.0.1) + bien bao.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final MapSourceService _service = ref.read(mapSourceServiceProvider);
  String? _styleUrl;
  PmTilesHeader? _header;
  String? _error;
  bool _loading = true;

  MapLibreMapController? _map;
  bool _styleReady = false;
  final HeadingTracker _heading = HeadingTracker();
  int _lastLat = 0, _lastLng = 0;
  bool _hasLast = false;
  int _speedLimit = 0;
  int _cameraAhead = -1;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final MapSourceService svc = ref.read(mapSourceServiceProvider);
    try {
      final String? path = await svc.savedPath();
      if (path == null) {
        setState(() => _loading = false);
        return;
      }
      final String url = await svc.startFromPath(path);
      if (!mounted) return;
      setState(() {
        _styleUrl = url;
        _header = svc.header;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Không mở được file bản đồ: $e';
      });
    }
  }

  Future<void> _pick() async {
    setState(() => _loading = true);
    try {
      final String? dest = await ref.read(mapSourceServiceProvider).pickAndImport();
      if (dest == null) {
        setState(() => _loading = false);
        return;
      }
      _styleReady = false;
      _map = null;
      await _start();
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'File không phải bản đồ PMTiles hợp lệ: $e';
      });
    }
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  Future<void> _onStyleLoaded() async {
    final MapLibreMapController? m = _map;
    if (m == null) return;
    await m.addGeoJsonSource('signs', signsGeoJson(const <NearbySign>[]));
    await m.addCircleLayer(
      'signs',
      'signs-layer',
      const CircleLayerProperties(
        circleRadius: 6,
        circleColor: <Object>['get', 'color'],
        circleStrokeColor: '#000000',
        circleStrokeWidth: 1,
      ),
    );
    await m.addGeoJsonSource('poi', poiGeoJson(const <Poi>[]));
    await m.addCircleLayer(
      'poi',
      'poi-layer',
      const CircleLayerProperties(
        circleRadius: 8,
        circleColor: <Object>['get', 'color'],
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
    );
    _styleReady = true;
    await _refreshOverlays();
  }

  Future<void> _onLocation(UserLocation loc) async {
    final int lat = (loc.position.latitude * 10000000).round();
    final int lng = (loc.position.longitude * 10000000).round();
    _heading.update(lat, lng);
    final SignIndex? idx = ref.read(signIndexProvider).valueOrNull;
    if (idx == null) return;
    final int h = _heading.headingDeg;
    final List<NearbySign> near = idx.nearby(lat, lng, 500);
    final NearbySign? lim = h < 0 ? null : currentSpeedLimit(near, h);
    int cam = -1;
    if (h >= 0) {
      for (final NearbySign n in signsAhead(near, h)) {
        if (n.sign.kind == SignKind.speedCamera || n.sign.kind == SignKind.streetCamera) {
          cam = n.distanceM;
          break;
        }
      }
    }
    if (mounted && (lim != null || cam != _cameraAhead)) {
      setState(() {
        if (lim != null) _speedLimit = lim.sign.speedKmh;
        _cameraAhead = cam;
      });
    }
  }

  bool _refreshing = false;
  bool _pending = false;

  /// Ve lai bien bao + POI theo khung nhin hien tai (goi khi camera dung lai).
  Future<void> _refreshOverlays() async {
    final MapLibreMapController? m = _map;
    final CameraPosition? cam = m?.cameraPosition;
    if (m == null || cam == null || !_styleReady) return;
    if (_refreshing) {
      _pending = true;
      return;
    }
    _refreshing = true;
    try {
      final int lat = (cam.target.latitude * 10000000).round();
      final int lng = (cam.target.longitude * 10000000).round();
      final SignIndex? idx = ref.read(signIndexProvider).valueOrNull;
      if (idx != null) {
        await m.setGeoJsonSource('signs', signsGeoJson(viewportSigns(idx, lat, lng, cam.zoom)));
      }
      final List<Poi>? poi = ref.read(poiProvider).valueOrNull;
      if (poi != null) {
        await m.setGeoJsonSource('poi', poiGeoJson(viewportPoi(poi, lat, lng, cam.zoom)));
      }
    } finally {
      _refreshing = false;
    }
    if (_pending && mounted) {
      _pending = false;
      await _refreshOverlays();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nap du lieu bien bao/POI som va ve ngay khi nap xong.
    ref.listen<AsyncValue<SignIndex>>(signIndexProvider, (_, __) => _refreshOverlays());
    ref.listen<AsyncValue<List<Poi>>>(poiProvider, (_, __) => _refreshOverlays());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bản đồ'),
        actions: <Widget>[
          IconButton(
            key: const Key('pick_map'),
            tooltip: 'Chọn file bản đồ (.pmtiles)',
            icon: const Icon(Icons.folder_open),
            onPressed: _loading ? null : _pick,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_styleUrl == null || _header == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const Text(
                'Chưa có bản đồ offline. Hãy tải file vietnam.pmtiles về điện thoại '
                'rồi bấm nút bên dưới để chọn file.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pick_map_body'),
                onPressed: _pick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Chọn file bản đồ'),
              ),
            ],
          ),
        ),
      );
    }
    final PmTilesHeader h = _header!;
    return Stack(
      children: <Widget>[
        MapLibreMap(
          styleString: _styleUrl!,
          initialCameraPosition: CameraPosition(
            target: LatLng(h.centerLatE7 / 1e7, h.centerLonE7 / 1e7),
            zoom: h.centerZoom.toDouble().clamp(h.minZoom.toDouble(), h.maxZoom.toDouble()),
          ),
          minMaxZoomPreference: MinMaxZoomPreference(h.minZoom.toDouble(), h.maxZoom.toDouble() + 2),
          myLocationEnabled: true,
          myLocationTrackingMode: MyLocationTrackingMode.tracking,
          onMapCreated: (MapLibreMapController c) => _map = c,
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraIdle: _refreshOverlays,
          onUserLocationUpdated: _onLocation,
        ),
        Positioned(
          left: 16,
          bottom: 24,
          child: Row(
            children: <Widget>[
              if (_speedLimit > 0) SpeedLimitSign(kmh: _speedLimit),
              if (_cameraAhead >= 0)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Chip(
                    key: const Key('map_camera'),
                    avatar: const Icon(Icons.videocam, size: 18),
                    label: Text('Camera cách $_cameraAhead m'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

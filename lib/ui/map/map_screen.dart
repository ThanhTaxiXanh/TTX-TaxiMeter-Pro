import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/providers.dart';
import '../../data/map/map_source_service.dart';
import '../../data/map/pmtiles_reader.dart';
import '../../domain/traffic/traffic_geojson.dart';
import '../../domain/traffic/traffic_models.dart';
import '../common/format.dart';
import 'map_icons.dart';
import 'report_sheet.dart';
import 'speed_limit_sign.dart';

/// Ban do offline 3D (MapLibre doc PMTiles qua may chu tile 127.0.0.1) + bien bao,
/// camera, POI. Cac nut tu an sau 5 giay, cham vao ban do de hien lai.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const Duration _hideAfter = Duration(seconds: 5);
  static const double _tilt = 60;
  static const double _followZoom = 17;

  late final MapSourceService _service = ref.read(mapSourceServiceProvider);
  String? _baseUrl;
  PmTilesHeader? _header;
  String? _error;
  bool _loading = true;

  String _theme = 'auto'; // auto | light | dark
  Timer? _themeTimer;
  Timer? _hideTimer;
  bool _uiVisible = true;
  bool _following = true;

  MapLibreMapController? _map;
  bool _styleReady = false;
  final Set<String> _icons = <String>{};
  final HeadingTracker _heading = HeadingTracker();

  int _speedKmh = 0;
  int _limitKmh = 0;
  String _street = '';
  NearestPoi? _fuel;
  NearestPoi? _ev;
  List<NearbySign> _ahead = const <NearbySign>[];
  int _lat = 0, _lng = 0;
  bool _hasPos = false;
  int _lastStreetMs = 0;

  @override
  void initState() {
    super.initState();
    _start();
    _showUi();
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_theme == 'auto' && mounted) _applyTheme();
    });
  }

  bool get _light {
    if (_theme == 'light') return true;
    if (_theme == 'dark') return false;
    return !isNightVn(ref.read(clockProvider)());
  }

  String? get _styleUrl => _baseUrl == null ? null : _service.styleUrlFor(light: _light);

  Future<void> _start() async {
    try {
      _theme = await _service.loadTheme();
      final String? path = await _service.savedPath();
      if (path == null) {
        setState(() => _loading = false);
        return;
      }
      final String url = await _service.startFromPath(path);
      if (!mounted) return;
      setState(() {
        _baseUrl = url;
        _header = _service.header;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không mở được file bản đồ: $e';
        });
      }
    }
  }

  Future<void> _pick() async {
    setState(() => _loading = true);
    try {
      final String? dest = await _service.pickAndImport();
      if (dest == null) {
        setState(() => _loading = false);
        return;
      }
      _styleReady = false;
      _map = null;
      await _start();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'File không phải bản đồ PMTiles hợp lệ: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _themeTimer?.cancel();
    _service.stop();
    super.dispose();
  }

  // ---- giao dien tu an sau 5 giay ----
  void _showUi() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _uiVisible = false);
    });
    if (!_uiVisible && mounted) setState(() => _uiVisible = true);
  }

  // ---- giao dien Sang / Toi / Tu dong ----
  void _cycleTheme() {
    _showUi();
    setState(() => _theme = _theme == 'auto' ? 'light' : (_theme == 'light' ? 'dark' : 'auto'));
    _service.saveTheme(_theme);
    _applyTheme();
  }

  void _applyTheme() {
    // Doi styleString -> MapLibre nap lai style, goi onStyleLoaded.
    _styleReady = false;
    _icons.clear();
    if (mounted) setState(() {});
  }

  // ---- lop du lieu tren ban do ----
  Future<void> _onStyleLoaded() async {
    final MapLibreMapController? m = _map;
    if (m == null) return;
    await m.addGeoJsonSource('signs', signsGeoJson(const <NearbySign>[]));
    await m.addSymbolLayer(
      'signs',
      'signs-layer',
      const SymbolLayerProperties(
        iconImage: <Object>['get', 'icon'],
        iconSize: 0.6,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconPitchAlignment: 'viewport',
      ),
    );
    await m.addGeoJsonSource('poi', poiGeoJson(const <Poi>[]));
    await m.addSymbolLayer(
      'poi',
      'poi-layer',
      const SymbolLayerProperties(
        iconImage: <Object>['get', 'icon'],
        iconSize: 0.65,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconPitchAlignment: 'viewport',
      ),
    );
    _styleReady = true;
    await _refreshOverlays();
  }

  Future<void> _ensureIcons(Iterable<String> names) async {
    final MapLibreMapController? m = _map;
    if (m == null) return;
    for (final String n in names) {
      if (_icons.contains(n)) continue;
      final bytes = await renderMapIcon(n);
      if (bytes == null) continue;
      await m.addImage(n, bytes);
      _icons.add(n);
    }
  }

  bool _refreshing = false;
  bool _pending = false;

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
        final List<NearbySign> v = viewportSigns(idx, lat, lng, cam.zoom);
        await _ensureIcons(v.map((NearbySign n) => signIconName(n.sign)).toSet());
        await m.setGeoJsonSource('signs', signsGeoJson(v));
      }
      final List<Poi>? poi = ref.read(poiProvider).valueOrNull;
      if (poi != null) {
        final List<Poi> v = viewportPoi(poi, lat, lng, cam.zoom);
        await _ensureIcons(v.map(poiIconName).toSet());
        await m.setGeoJsonSource('poi', poiGeoJson(v));
      }
    } catch (_) {
      // Ve lai o lan camera dung tiep theo.
    } finally {
      _refreshing = false;
    }
    if (_pending && mounted) {
      _pending = false;
      await _refreshOverlays();
    }
  }

  // ---- vi tri nguoi dung ----
  Future<void> _onLocation(UserLocation loc) async {
    final int lat = (loc.position.latitude * 10000000).round();
    final int lng = (loc.position.longitude * 10000000).round();
    _lat = lat;
    _lng = lng;
    final bool first = !_hasPos;
    _hasPos = true;
    _heading.update(lat, lng);
    final double? b = loc.bearing;
    final int h = (b != null && b >= 0 && (loc.speed ?? 0) > 1) ? b.round() % 360 : _heading.headingDeg;
    final int kmh = ((loc.speed ?? 0) * 3.6).round();

    final SignIndex? idx = ref.read(signIndexProvider).valueOrNull;
    int limit = _limitKmh;
    List<NearbySign> ahead = const <NearbySign>[];
    if (idx != null) {
      final List<NearbySign> near = idx.nearby(lat, lng, 600);
      if (h >= 0) {
        final NearbySign? lim = currentSpeedLimit(near, h);
        if (lim != null) limit = lim.sign.speedKmh;
        ahead = signsAhead(near, h).where((NearbySign n) => n.distanceM > 5).take(3).toList();
      } else {
        ahead = near.take(3).toList();
      }
    }
    final List<Poi>? poi = ref.read(poiProvider).valueOrNull;
    NearestPoi? fuel = _fuel, ev = _ev;
    if (poi != null) {
      fuel = nearestPoi(poi, lat, lng, <String>{'fuel'});
      ev = nearestPoi(poi, lat, lng, <String>{'charging_station', 'charging_station_motorcycle'});
    }
    if (!mounted) return;
    setState(() {
      _speedKmh = kmh;
      _limitKmh = limit;
      _ahead = ahead;
      _fuel = fuel;
      _ev = ev;
    });

    if (first || _following) {
      // Giu goc nhin 3D nghieng, huong theo chieu di.
      await _map?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: loc.position,
        zoom: _followZoom,
        tilt: _tilt,
        bearing: h >= 0 ? h.toDouble() : 0,
      )));
    }
    await _updateStreet(loc.position);
  }

  /// Ten duong: doc tu tile dang hien thi tai vi tri nguoi dung (khong can mang).
  Future<void> _updateStreet(LatLng pos) async {
    final MapLibreMapController? m = _map;
    final int now = ref.read(clockProvider)();
    if (m == null || !_styleReady || now - _lastStreetMs < 1500) return;
    _lastStreetMs = now;
    try {
      final Point<num> sp = await m.toScreenLocation(pos);
      final List<dynamic> feats = await m.queryRenderedFeatures(
          Point<double>(sp.x.toDouble(), sp.y.toDouble()), <String>[], null);
      String name = '';
      for (final dynamic f in feats) {
        final dynamic props = f is Map ? f['properties'] : null;
        if (props is Map) {
          final dynamic n = props['name:vi'] ?? props['name'] ?? props['name_vi'];
          if (n is String && n.isNotEmpty) {
            name = n;
            break;
          }
        }
      }
      if (mounted && name != _street) setState(() => _street = name);
    } catch (_) {}
  }

  Future<void> _recenter() async {
    _showUi();
    setState(() => _following = true);
    if (_hasPos) {
      await _map?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(_lat / 1e7, _lng / 1e7),
        zoom: _followZoom,
        tilt: _tilt,
        bearing: _heading.headingDeg >= 0 ? _heading.headingDeg.toDouble() : 0,
      )));
    }
  }

  Future<void> _report() async {
    _showUi();
    if (!_hasPos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có vị trí GPS để báo cáo.')),
      );
      return;
    }
    final bool saved = await showReportSheet(context, ref, latE7: _lat, lngE7: _lng);
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu báo cáo biển báo.')),
      );
    }
  }

  // ---- giao dien ----
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SignIndex>>(signIndexProvider, (_, __) => _refreshOverlays());
    ref.listen<AsyncValue<List<Poi>>>(poiProvider, (_, __) => _refreshOverlays());
    return Scaffold(
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_styleUrl == null || _header == null) {
      return SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned(top: 8, left: 8, child: BackButton(onPressed: () => Navigator.maybePop(context))),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
            ),
          ],
        ),
      );
    }
    final PmTilesHeader h = _header!;
    final bool over = _limitKmh > 0 && _speedKmh > _limitKmh;
    return Stack(
      children: <Widget>[
        MapLibreMap(
          key: const ValueKey<String>('map'),
          styleString: _styleUrl!,
          initialCameraPosition: CameraPosition(
            target: LatLng(h.centerLatE7 / 1e7, h.centerLonE7 / 1e7),
            zoom: h.centerZoom.toDouble().clamp(h.minZoom.toDouble(), h.maxZoom.toDouble()),
            tilt: _tilt,
          ),
          minMaxZoomPreference: MinMaxZoomPreference(h.minZoom.toDouble(), h.maxZoom.toDouble() + 2),
          trackCameraPosition: true,
          compassEnabled: false,
          myLocationEnabled: true,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          myLocationRenderMode: MyLocationRenderMode.gps,
          onMapCreated: (MapLibreMapController c) => _map = c,
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraIdle: _refreshOverlays,
          onUserLocationUpdated: _onLocation,
          onMapClick: (_, __) => _showUi(),
          onCameraTrackingDismissed: () {
            if (mounted) setState(() => _following = false);
          },
        ),
        // Nut + thong tin: an sau 5 giay, cham ban do de hien lai.
        AnimatedOpacity(
          opacity: _uiVisible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !_uiVisible,
            child: SafeArea(child: _overlay(over)),
          ),
        ),
      ],
    );
  }

  Widget _glass({required Widget child, EdgeInsets padding = const EdgeInsets.all(10)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
      );

  Widget _roundButton(Key key, IconData icon, VoidCallback onTap, {String? tooltip, bool active = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.black.withOpacity(0.55),
          shape: const CircleBorder(),
          child: IconButton(
            key: key,
            tooltip: tooltip,
            iconSize: 28,
            color: active ? Colors.amber : Colors.white,
            icon: Icon(icon),
            onPressed: onTap,
          ),
        ),
      );

  Widget _poiChip(Key key, IconData icon, Color color, String label, NearestPoi? p) {
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                p.poi.name.isEmpty ? label : p.poi.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(formatDistance(p.distanceM), style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _overlay(bool over) {
    final IconData themeIcon = _theme == 'auto'
        ? Icons.brightness_auto
        : (_theme == 'light' ? Icons.light_mode : Icons.dark_mode);
    return Stack(
      children: <Widget>[
        // Tren: quay lai + POI gan nhat kem khoang cach.
        Positioned(
          top: 8,
          left: 8,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _roundButton(const Key('back'), Icons.arrow_back, () => Navigator.maybePop(context)),
              _poiChip(const Key('poi_fuel'), Icons.local_gas_station, Colors.lightBlueAccent, 'Trạm xăng', _fuel),
              _poiChip(const Key('poi_ev'), Icons.ev_station, Colors.greenAccent, 'Trạm sạc', _ev),
            ],
          ),
        ),
        // Phai: vi tri, giao dien, chon ban do.
        Positioned(
          right: 12,
          top: 120,
          child: Column(
            children: <Widget>[
              _roundButton(const Key('locate'), Icons.my_location, _recenter,
                  tooltip: 'Vị trí của tôi', active: _following),
              _roundButton(const Key('theme'), themeIcon, _cycleTheme,
                  tooltip: _theme == 'auto' ? 'Tự động theo giờ' : (_theme == 'light' ? 'Sáng' : 'Tối')),
              _roundButton(const Key('pick_map'), Icons.folder_open, _pick, tooltip: 'Chọn file bản đồ'),
            ],
          ),
        ),
        // Trai duoi: bien phia truoc, gioi han toc do, toc do, bao cao.
        Positioned(
          left: 12,
          bottom: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_ahead.isNotEmpty)
                _glass(
                  child: Column(
                    key: const Key('ahead'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final NearbySign n in _ahead)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('${signLabel(n.sign.kind)}'
                              '${n.sign.kind == SignKind.maxSpeed ? ' ${n.sign.speedKmh}' : ''}'
                              '  ${formatDistance(n.distanceM)}'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              if (_limitKmh > 0) SpeedLimitSign(kmh: _limitKmh, size: 76),
              const SizedBox(height: 10),
              Container(
                key: const Key('speedometer'),
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.6),
                  border: Border.all(color: over ? Colors.redAccent : Colors.white54, width: 4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('$_speedKmh',
                        style: TextStyle(
                            color: over ? Colors.redAccent : Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800)),
                    const Text('km/h', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.black.withOpacity(0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  key: const Key('report'),
                  iconSize: 28,
                  color: Colors.white,
                  icon: const Icon(Icons.add_location_alt),
                  tooltip: 'Báo cáo biển báo',
                  onPressed: _report,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 2),
                child: Text('Báo cáo', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ),
        // Duoi: ten duong.
        Positioned(
          left: 110,
          right: 12,
          bottom: 16,
          child: _glass(
            child: Column(
              key: const Key('street'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Đang đi', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(
                  _street.isEmpty ? '—' : _street,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

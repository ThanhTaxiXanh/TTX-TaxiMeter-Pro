import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/map/map_source_service.dart';

class MapSettingsScreen extends ConsumerStatefulWidget {
  const MapSettingsScreen({super.key});

  @override
  ConsumerState<MapSettingsScreen> createState() => _MapSettingsScreenState();
}

class _MapSettingsScreenState extends ConsumerState<MapSettingsScreen> {
  String _theme = 'auto';
  String _family = 'standard';
  int _warn = 300;
  bool _hasFile = false;
  String? _msg;
  bool _loaded = false;

  MapSourceService get _svc => ref.read(mapSourceServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String t = await _svc.loadTheme();
    final String f = await _svc.loadFamily();
    final int w = await _svc.loadWarnM();
    final bool has = await _svc.savedPath() != null;
    if (mounted) {
      setState(() {
        _theme = t;
        _family = f;
        _warn = w;
        _hasFile = has;
        _loaded = true;
      });
    }
  }

  Future<void> _pick() async {
    try {
      final String? dest = await _svc.pickAndImport();
      if (dest != null) {
        setState(() {
          _hasFile = true;
          _msg = 'Đã nhận file bản đồ.';
        });
      }
    } catch (e) {
      setState(() => _msg = 'File không phải bản đồ PMTiles hợp lệ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(appBar: AppBar(title: const Text('Bản đồ')), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Bản đồ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_hasFile ? Icons.check_circle : Icons.error_outline),
            title: Text(_hasFile ? 'Đã có file bản đồ offline' : 'Chưa có file bản đồ'),
            trailing: FilledButton(key: const Key('map_pick'), onPressed: _pick, child: const Text('Chọn file')),
          ),
          if (_msg != null) Text(_msg!),
          const SizedBox(height: 16),
          const Text('Giao diện bản đồ'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('map_theme'),
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'auto', label: Text('Tự động')),
              ButtonSegment<String>(value: 'light', label: Text('Sáng')),
              ButtonSegment<String>(value: 'dark', label: Text('Tối')),
            ],
            selected: <String>{_theme},
            onSelectionChanged: (Set<String> v) {
              setState(() => _theme = v.first);
              _svc.saveTheme(v.first);
            },
          ),
          const SizedBox(height: 16),
          const Text('Kiểu bản đồ'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('map_family'),
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'standard', label: Text('Chuẩn 3D')),
              ButtonSegment<String>(value: 'modern', label: Text('Hiện đại 3D')),
            ],
            selected: <String>{_family},
            onSelectionChanged: (Set<String> v) {
              setState(() => _family = v.first);
              _svc.saveFamily(v.first);
            },
          ),
          const SizedBox(height: 16),
          const Text('Cảnh báo khoảng cách tới biển'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const Key('map_warn'),
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 200, label: Text('200 m')),
              ButtonSegment<int>(value: 300, label: Text('300 m')),
              ButtonSegment<int>(value: 500, label: Text('500 m')),
            ],
            selected: <int>{_warn},
            onSelectionChanged: (Set<int> v) {
              setState(() => _warn = v.first);
              _svc.saveWarnM(v.first);
            },
          ),
        ],
      ),
    );
  }
}

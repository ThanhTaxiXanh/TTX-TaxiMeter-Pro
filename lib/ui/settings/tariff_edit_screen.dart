import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/tariff/tariff_repository.dart';

class _Tier {
  _Tier(String upTo, String price)
      : upTo = TextEditingController(text: upTo),
        price = TextEditingController(text: price);
  final TextEditingController upTo;
  final TextEditingController price;
}

/// Sua/tao bieu gia: gia mo cua, cac bac gia theo km (them/bot bac), gia cho, lam tron.
/// Luu thanh phien ban moi; chuyen dang chay khong bi anh huong.
class TariffEditScreen extends ConsumerStatefulWidget {
  const TariffEditScreen({super.key, required this.base, required this.isNew, required this.wasActive});

  final Map<String, dynamic> base;
  final bool isNew; // true: tao moi/nhan ban (cho phep doi ten)
  final bool wasActive;

  @override
  ConsumerState<TariffEditScreen> createState() => _TariffEditScreenState();
}

class _TariffEditScreenState extends ConsumerState<TariffEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _openFare;
  late final TextEditingController _openKm;
  late final TextEditingController _wait;
  late final TextEditingController _round;
  final List<_Tier> _tiers = <_Tier>[];
  late bool _activate;
  String? _err;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> b = widget.base;
    final Map<String, dynamic> open = b['opening'] as Map<String, dynamic>;
    _name = TextEditingController(text: b['configId'] as String);
    _openFare = TextEditingController(text: '${open['fareVnd']}');
    _openKm = TextEditingController(text: metersToKmText(open['includedMeters'] as int));
    _wait = TextEditingController(text: '${(b['waiting'] as Map<String, dynamic>)['ratePerHourVnd']}');
    _round = TextEditingController(text: '${(b['rounding'] as Map<String, dynamic>)['unitVnd']}');
    for (final dynamic t in b['distanceTiers'] as List<dynamic>) {
      final Map<String, dynamic> m = t as Map<String, dynamic>;
      _tiers.add(_Tier(m['upToMeters'] == null ? '' : metersToKmText(m['upToMeters'] as int), '${m['pricePerKmVnd']}'));
    }
    _activate = widget.wasActive || widget.isNew;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _openFare, _openKm, _wait, _round]) {
      c.dispose();
    }
    for (final _Tier t in _tiers) {
      t.upTo.dispose();
      t.price.dispose();
    }
    super.dispose();
  }

  void _addTier() {
    setState(() {
      // Chen truoc bac cuoi (bac cuoi luon khong gioi han).
      _tiers.insert(_tiers.length - 1, _Tier('', _tiers[_tiers.length - 2 < 0 ? 0 : _tiers.length - 2].price.text));
    });
  }

  void _removeTier(int i) {
    if (_tiers.length <= 1) return;
    setState(() {
      final _Tier t = _tiers.removeAt(i);
      t.upTo.dispose();
      t.price.dispose();
    });
  }

  Future<void> _save() async {
    int? n(TextEditingController c) => int.tryParse(c.text.trim());
    final int? fare = n(_openFare), rate = n(_wait), unit = n(_round);
    final int? incl = parseKmToMeters(_openKm.text);
    if (fare == null || fare < 0 || incl == null || rate == null || rate < 0 || unit == null || unit < 1) {
      setState(() => _err = 'Kiểm tra lại các ô số (giá mở cửa, km đã gồm, giá chờ, làm tròn).');
      return;
    }
    final List<Map<String, dynamic>> tiers = <Map<String, dynamic>>[];
    int prev = 0;
    for (int i = 0; i < _tiers.length; i++) {
      final int? price = n(_tiers[i].price);
      if (price == null || price <= 0) {
        setState(() => _err = 'Bậc ${i + 1}: nhập giá mỗi km (số nguyên > 0).');
        return;
      }
      final bool last = i == _tiers.length - 1;
      int? up;
      if (!last) {
        up = parseKmToMeters(_tiers[i].upTo.text);
        if (up == null || up <= prev) {
          setState(() => _err = 'Bậc ${i + 1}: "đến km" phải là số lớn hơn bậc trước.');
          return;
        }
        prev = up;
      }
      tiers.add(<String, dynamic>{'index': i, 'upToMeters': up, 'pricePerKmVnd': price});
    }
    final Map<String, dynamic> j = Map<String, dynamic>.of(widget.base)
      ..['configId'] = _name.text.trim()
      ..['opening'] = <String, dynamic>{'fareVnd': fare, 'includedMeters': incl}
      ..['distanceTiers'] = tiers
      ..['waiting'] = <String, dynamic>{...(widget.base['waiting'] as Map<String, dynamic>), 'ratePerHourVnd': rate}
      ..['rounding'] = <String, dynamic>{...(widget.base['rounding'] as Map<String, dynamic>), 'unitVnd': unit};
    try {
      await ref.read(tariffRepositoryProvider).saveVersion(j, nowMs: ref.read(clockProvider)(), activate: _activate);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _err = e.toString());
    }
  }

  Widget _num(String label, TextEditingController c, {Key? key, bool decimal = false, String? suffix}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))],
          decoration: InputDecoration(labelText: label, suffixText: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isNew ? 'Biểu giá mới' : 'Sửa biểu giá')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('tariff_name'),
            controller: _name,
            enabled: widget.isNew,
            decoration: const InputDecoration(labelText: 'Tên biểu giá (vd taxi-4-cho)'),
          ),
          const SizedBox(height: 12),
          _num('Giá mở cửa', _openFare, key: const Key('open_fare'), suffix: 'đ'),
          _num('Số km đã gồm trong giá mở cửa', _openKm, key: const Key('open_km'), decimal: true, suffix: 'km'),
          const Divider(),
          Text('Các bậc giá theo km', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (int i = 0; i < _tiers.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Bậc ${i + 1}'),
                          const SizedBox(height: 8),
                          if (i == _tiers.length - 1)
                            const Text('Từ đây trở đi (không giới hạn)')
                          else
                            _num('Đến km thứ', _tiers[i].upTo, key: Key('tier_up_$i'), decimal: true, suffix: 'km'),
                          _num('Giá mỗi km', _tiers[i].price, key: Key('tier_price_$i'), suffix: 'đ/km'),
                        ],
                      ),
                    ),
                    IconButton(
                      key: Key('tier_del_$i'),
                      tooltip: 'Bớt bậc này',
                      onPressed: _tiers.length > 1 ? () => _removeTier(i) : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(key: const Key('tier_add'), onPressed: _addTier, icon: const Icon(Icons.add), label: const Text('Thêm bậc giá')),
          const Divider(height: 32),
          _num('Giá chờ mỗi giờ', _wait, key: const Key('wait_rate'), suffix: 'đ/giờ'),
          _num('Làm tròn cước đến', _round, key: const Key('round_unit'), suffix: 'đ'),
          SwitchListTile(
            key: const Key('tariff_activate'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Dùng cho các chuyến mới'),
            subtitle: const Text('Chuyến đang chạy luôn giữ biểu giá lúc bắt đầu.'),
            value: _activate,
            onChanged: (bool v) => setState(() => _activate = v),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('tariff_save'), onPressed: _save, child: const Text('Lưu biểu giá')),
        ],
      ),
    );
  }
}

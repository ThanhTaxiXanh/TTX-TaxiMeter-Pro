import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/trip/trip_store.dart';
import 'package:ttx/domain/models/tariff_config_v2.dart';
import 'package:ttx/domain/trip/active_trip_session.dart';

import '../test_support.dart';

void main() {
  late AppDatabase db;
  late DriftTripStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftTripStore(db);
  });
  tearDown(() async => db.close());

  Future<ActiveTripSession> startTrip() async {
    final TariffConfigV2 cfg = await store.resolveActiveTariff(baseTsMs);
    return ActiveTripSession(
      tripId: 'trip-db-1',
      startedAtMs: baseTsMs,
      config: cfg,
      contexts: contextsAt(baseTsMs),
    );
  }

  void drive(ActiveTripSession s, int fromM, int toM) {
    for (int i = fromM; i <= toM; i++) {
      s.addSample(gs(i * 1000, latE7: latE7ForMeters(i * 10)));
    }
  }

  test('lan dau tao bieu gia mac dinh, lan sau dung lai', () async {
    final TariffConfigV2 a = await store.resolveActiveTariff(baseTsMs);
    final TariffConfigV2 b = await store.resolveActiveTariff(baseTsMs + 1);
    expect(a.contentSha256, b.contentSha256);
    final List<QueryRow> n = await db.customSelect('SELECT COUNT(*) c FROM tariff_config').get();
    expect(n.first.read<int>('c'), 1);
  });

  test('crash giua chuyen -> khoi phuc cuoc y het', () async {
    final ActiveTripSession s = await startTrip();
    drive(s, 0, 200);
    await store.saveProgress(session: s, fromSeq: 0, nowMs: baseTsMs + 200000);
    drive(s, 201, 300);
    await store.saveProgress(session: s, fromSeq: 201, nowMs: baseTsMs + 300000);

    // "Tat app": store moi tren cung co so du lieu.
    final RestoredTrip? r = await DriftTripStore(db).loadActive();
    expect(r, isNotNull);
    expect(r!.session.tripId, 'trip-db-1');
    expect(r.session.sampleCount, s.sampleCount);
    expect(r.session.finalFare(), s.finalFare());
    expect(r.session.liveFare, s.liveFare);
  });

  test('khong resolve lai config giua chuyen', () async {
    final ActiveTripSession s = await startTrip();
    drive(s, 0, 50);
    await store.saveProgress(session: s, fromSeq: 0, nowMs: baseTsMs + 50000);

    // Bieu gia moi (gia khac) duoc kich hoat luc dang chay.
    final Map<String, dynamic> j = jsonDecode(jsonEncode(fixtureConfigJson()));
    j['configId'] = 'moi';
    await db.customStatement(
      'INSERT INTO tariff_config(config_id, config_version, effective_from, '
      "effective_to, status, json_body, sha256, created_at) VALUES ('moi', 1, 1, NULL, 'ACTIVE', ?, 'x', 1)",
      <Object?>[jsonEncode(j)],
    );
    final RestoredTrip? r = await store.loadActive();
    expect(r!.session.config.configId, s.config.configId);
    expect(r.session.config.contentSha256, s.config.contentSha256);
  });

  test('snapshot hong config (sha khong khop) -> khong khoi phuc', () async {
    final ActiveTripSession s = await startTrip();
    drive(s, 0, 10);
    await store.saveProgress(session: s, fromSeq: 0, nowMs: baseTsMs);
    await db.customStatement("UPDATE active_trip_snapshot SET config_sha256 = 'sai'");
    expect(await store.loadActive(), isNull);
  });

  test('ket thuc chuyen: ghi trip_record dung cuoc, xoa snapshot', () async {
    final ActiveTripSession s = await startTrip();
    drive(s, 0, 300);
    await store.saveProgress(session: s, fromSeq: 0, nowMs: baseTsMs + 300000);
    await store.finishTrip(session: s, endedAtMs: baseTsMs + 300000, nowMs: baseTsMs + 300001);

    final List<QueryRow> t = await db.customSelect('SELECT * FROM trip_record').get();
    expect(t, hasLength(1));
    expect(t.first.read<int>('fare_total_vnd'), s.finalFare().fareTotal);
    expect(t.first.read<String>('fare_hash'), s.finalFare().fareHash);
    expect(t.first.read<int>('duration_sec'), 300);
    expect(await store.loadActive(), isNull);
    final List<QueryRow> m = await db.customSelect('SELECT point_count FROM raw_trace_meta').get();
    expect(m.first.read<int>('point_count'), 301);
  });

  test('bo chuyen: xoa snapshot + diem tho, khong co trip_record', () async {
    final ActiveTripSession s = await startTrip();
    drive(s, 0, 10);
    await store.saveProgress(session: s, fromSeq: 0, nowMs: baseTsMs);
    await store.discardActive();
    expect(await store.loadActive(), isNull);
    final List<QueryRow> c = await db.customSelect('SELECT COUNT(*) c FROM raw_gps_points').get();
    expect(c.first.read<int>('c'), 0);
    final List<QueryRow> t = await db.customSelect('SELECT COUNT(*) c FROM trip_record').get();
    expect(t.first.read<int>('c'), 0);
  });
}

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/app/providers.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/domain/models/gps_sample.dart';
import 'package:ttx/domain/traffic/traffic_models.dart';
import 'package:ttx/platform/location_service.dart';
import 'package:ttx/platform/screen_awake.dart';
import 'package:ttx/ui/dashboard/trip_controller.dart';

import '../test_support.dart';

class FakeLocation implements LocationService {
  FakeLocation(this.permission);
  LocationPermissionState permission;
  StreamController<GpsSample> ctl = StreamController<GpsSample>.broadcast();

  @override
  Future<LocationPermissionState> ensurePermission() async => permission;

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Stream<GpsSample> start() => ctl.stream;
}

class FakeAwake implements ScreenAwake {
  int on = 0, off = 0;
  @override
  Future<void> enable() async => on++;
  @override
  Future<void> disable() async => off++;
}

void main() {
  late AppDatabase db;
  late FakeLocation loc;
  late FakeAwake awake;
  late int now;

  List<TrafficSign> signs = <TrafficSign>[];

  ProviderContainer make() {
    final ProviderContainer c = ProviderContainer(overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      locationServiceProvider.overrideWithValue(loc),
      screenAwakeProvider.overrideWithValue(awake),
      clockProvider.overrideWithValue(() => now),
      signIndexProvider.overrideWith((Ref ref) async => SignIndex(signs)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    loc = FakeLocation(LocationPermissionState.granted);
    awake = FakeAwake();
    now = baseTsMs;
    signs = <TrafficSign>[];
  });
  tearDown(() async => db.close());

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('bat dau -> nhan GPS -> cuoc tang -> ket thuc ghi so cai', () async {
    final ProviderContainer c = make();
    final TripController ctl = c.read(tripControllerProvider.notifier);
    await ctl.startTrip();
    expect(c.read(tripControllerProvider).running, isTrue);
    expect(awake.on, 1);

    for (int i = 0; i <= 300; i++) {
      now = baseTsMs + i * 1000;
      loc.ctl.add(gs(i * 1000, latE7: latE7ForMeters(i * 10)));
      await pump();
    }
    final TripUiState s = c.read(tripControllerProvider);
    expect(s.fareVnd, greaterThan(12000));
    expect(s.distanceM, greaterThan(2900));
    expect(s.gps, GpsStatus.good);

    await ctl.stopTrip();
    final TripUiState end = c.read(tripControllerProvider);
    expect(end.phase, TripPhase.idle);
    expect(end.finished, isNotNull);
    expect(end.finished!.fareTotal % 1000, 0);
    expect(awake.off, 1);

    final rows = await db.customSelect('SELECT fare_total_vnd FROM trip_record').get();
    expect(rows, hasLength(1));
    expect(rows.first.read<int>('fare_total_vnd'), end.finished!.fareTotal);
  });

  test('xin quyen ngay khi mo app; bi chan -> bao loi', () async {
    loc.permission = LocationPermissionState.denied;
    final ProviderContainer c = make();
    await c.read(tripControllerProvider.notifier).requestPermissionsOnLaunch();
    expect(c.read(tripControllerProvider).error, isNotNull);
  });

  test('bien bao: gioi han toc do va canh bao camera phia truoc', () async {
    signs = <TrafficSign>[
      TrafficSign(latE7: latE7ForMeters(150), lngE7: 0, kind: SignKind.maxSpeed, dirDeg: 0, speedKmh: 60),
      TrafficSign(latE7: latE7ForMeters(400), lngE7: 0, kind: SignKind.speedCamera, dirDeg: -1, speedKmh: -1),
      TrafficSign(latE7: latE7ForMeters(100), lngE7: 0, kind: SignKind.maxSpeed, dirDeg: 180, speedKmh: 30),
    ];
    final ProviderContainer c = make();
    await c.read(signIndexProvider.future);
    final TripController ctl = c.read(tripControllerProvider.notifier);
    await ctl.startTrip();
    for (int i = 0; i <= 40; i++) {
      now = baseTsMs + i * 1000;
      loc.ctl.add(gs(i * 1000, latE7: latE7ForMeters(i * 10)));
      await pump();
    }
    final TripUiState s = c.read(tripControllerProvider);
    expect(s.speedLimitKmh, 60); // bien nguoc huong (30) bi bo qua
    expect(s.cameraAheadM, greaterThanOrEqualTo(0));
    expect(s.cameraAheadM, lessThanOrEqualTo(500));
    await ctl.stopTrip();
  });

  test('thieu quyen vi tri -> bao loi, khong tao chuyen', () async {
    loc.permission = LocationPermissionState.deniedForever;
    final ProviderContainer c = make();
    await c.read(tripControllerProvider.notifier).startTrip();
    final TripUiState s = c.read(tripControllerProvider);
    expect(s.running, isFalse);
    expect(s.error, isNotNull);
    final rows = await db.customSelect('SELECT COUNT(*) c FROM active_trip_snapshot').get();
    expect(rows.first.read<int>('c'), 0);
  });

  test('app bi tat giua chuyen -> mo lai khoi phuc dung cuoc', () async {
    final ProviderContainer c1 = make();
    final TripController a = c1.read(tripControllerProvider.notifier);
    await a.startTrip();
    for (int i = 0; i <= 120; i++) {
      now = baseTsMs + i * 1000;
      loc.ctl.add(gs(i * 1000, latE7: latE7ForMeters(i * 10)));
      await pump();
    }
    await a.flush();
    final int fareBefore = c1.read(tripControllerProvider).fareVnd;
    final int distBefore = c1.read(tripControllerProvider).distanceM;
    c1.dispose(); // app bi giet

    loc.ctl = StreamController<GpsSample>.broadcast();
    final ProviderContainer c2 = make();
    await c2.read(tripControllerProvider.notifier).restoreOnLaunch();
    final TripUiState s = c2.read(tripControllerProvider);
    expect(s.running, isTrue);
    expect(s.restored, isTrue);
    expect(s.fareVnd, fareBefore);
    expect(s.distanceM, distBefore);
  });
}

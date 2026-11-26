import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/app/providers.dart';
import 'package:ttx/data/bank/bank_repository.dart';
import 'package:ttx/data/bank/bank_seed.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/payment/payment_repository.dart';
import 'package:ttx/payment/vietqr_payload_builder.dart';
import 'package:ttx/platform/brightness_control.dart';
import 'package:ttx/ui/payment/payment_dialog.dart';

import '../test_support.dart';

class FakeBrightness implements BrightnessControl {
  int max = 0, restored = 0;
  @override
  Future<void> setMax() async => max++;
  @override
  Future<void> restore() async => restored++;
}

Future<void> insertTrip(AppDatabase db, String id, int startedAt) {
  return db.customStatement(
    'INSERT INTO trip_record(trip_id, started_at, ended_at, duration_sec, distance_m, '
    'waiting_sec, fare_opening_vnd, fare_distance_vnd, fare_waiting_vnd, fare_total_vnd, '
    'config_id, config_version, config_sha256, fare_hash, created_at) '
    "VALUES (?, ?, ?, 60, 1000, 0, 10000, 0, 0, 12000, 'c', 1, 's', 'h', ?)",
    <Object?>[id, startedAt, startedAt + 60000, startedAt],
  );
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('danh muc ngan hang: seed idempotent, BIN hop le, khong trung', () async {
    final BankRepository r = BankRepository(db);
    await r.ensureSeeded(1);
    await r.ensureSeeded(2);
    final List<BankInfo> banks = await r.listBanks();
    expect(banks.length, bankSeeds.length);
    expect(banks.map((BankInfo b) => b.bin).toSet().length, banks.length);
    for (final BankInfo b in banks) {
      expect(RegExp(r'^\d{6}$').hasMatch(b.bin), isTrue, reason: b.shortName);
    }
    expect((await r.findByBin('970436'))!.shortName, 'Vietcombank');
  });

  test('tai khoan chu xe: luu/doc/ghi de, tu choi thieu thong tin', () async {
    final BankRepository r = BankRepository(db);
    expect(await r.getDriverAccount(), isNull);
    await r.saveDriverAccount(
        const DriverAccount(bin: '970436', accountNumber: '0123456789', holder: 'NGUYEN VAN A'), 5);
    await r.saveDriverAccount(
        const DriverAccount(bin: '970422', accountNumber: '999', holder: 'NGUYEN VAN A'), 6);
    final DriverAccount a = (await r.getDriverAccount())!;
    expect(a.bin, '970422');
    expect(a.accountNumber, '999');
    expect(
        () => r.saveDriverAccount(const DriverAccount(bin: '1', accountNumber: '', holder: ''), 7),
        throwsArgumentError);
  });

  test('so thu tu chuyen trong ngay (gio VN)', () async {
    final PaymentRepository p = PaymentRepository(db);
    await insertTrip(db, 'a', baseTsMs); // 10:00 24/11
    await insertTrip(db, 'b', baseTsMs + 3600000);
    await insertTrip(db, 'c', baseTsMs + 86400000); // hom sau
    expect(await p.sequenceInDay(baseTsMs), 1);
    expect(await p.sequenceInDay(baseTsMs + 3600000), 2);
    expect(await p.sequenceInDay(baseTsMs + 86400000), 1);
  });

  test('ghi thanh toan: tien mat PAID; QR UNPAID -> markPaid', () async {
    final PaymentRepository p = PaymentRepository(db);
    await insertTrip(db, 't1', baseTsMs);
    await insertTrip(db, 't2', baseTsMs + 1000);
    await p.record(tripId: 't1', method: 'CASH', state: 'PAID', amountVnd: 50000, nowMs: 10);
    await p.record(
        tripId: 't2', method: 'QR', state: 'UNPAID', amountVnd: 70000, nowMs: 11, qrContent: 'x');
    expect((await p.get('t1'))!.state, 'PAID');
    expect((await p.get('t2'))!.state, 'UNPAID');
    await p.markPaid('t2', 20);
    expect((await p.get('t2'))!.state, 'PAID');
    expect(await p.get('zzz'), isNull);
  });

  group('PaymentDialog', () {
    late FakeBrightness br;

    Future<void> open(WidgetTester tester) async {
      br = FakeBrightness();
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          brightnessProvider.overrideWithValue(br),
          clockProvider.overrideWithValue(() => baseTsMs + 5000),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext c) => TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => const PaymentDialog(
                    tripId: 'T1',
                    startedAtMs: baseTsMs,
                    amountVnd: 88000,
                    distanceM: 5000,
                    waitingSec: 0,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('tien mat -> ghi PAID', (WidgetTester tester) async {
      await tester.runAsync(() => insertTrip(db, 'T1', baseTsMs));
      await open(tester);
      await tester.tap(find.byKey(const Key('pay_cash')));
      await tester.pumpAndSettle();
      final PaymentInfo? info = await tester
          .runAsync<PaymentInfo?>(() => PaymentRepository(db).get('T1'));
      expect(info!.method, 'CASH');
      expect(info.state, 'PAID');
    });

    testWidgets('QR khi chua cai tai khoan -> bao loi, khong ghi', (WidgetTester tester) async {
      await tester.runAsync(() => insertTrip(db, 'T1', baseTsMs));
      await open(tester);
      await tester.tap(find.byKey(const Key('pay_qr')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa cài tài khoản'), findsOneWidget);
      expect(await tester.runAsync<PaymentInfo?>(() => PaymentRepository(db).get('T1')), isNull);
    });

    testWidgets('QR dung payload; xac nhan da nhan tien -> PAID', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await insertTrip(db, 'T1', baseTsMs);
        await BankRepository(db).saveDriverAccount(
            const DriverAccount(bin: '970436', accountNumber: '0123456789', holder: 'NGUYEN VAN A'), 1);
      });
      await open(tester);
      await tester.tap(find.byKey(const Key('pay_qr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qr')), findsOneWidget);
      expect(br.max, 1);

      final String expected = VietQrPayload.build(
          bin: '970436', account: '0123456789', amountVnd: 88000, content: 'TTX261124001');
      final List<Object?>? row = await tester.runAsync(() async {
        final r = await db.customSelect('SELECT qr_content, state FROM trip_payment').get();
        return <Object?>[r.first.read<String>('qr_content'), r.first.read<String>('state')];
      });
      expect(row![0], expected);
      expect(row[1], 'UNPAID');

      await tester.tap(find.byKey(const Key('qr_paid')));
      await tester.pumpAndSettle();
      expect((await tester.runAsync<PaymentInfo?>(() => PaymentRepository(db).get('T1')))!.state, 'PAID');
      expect(br.restored, 1);
    });
  });
}

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/payment/payment_repository.dart';
import 'package:ttx/data/trip/tombstone_repository.dart';
import 'package:ttx/data/trip/trip_models.dart';
import 'package:ttx/data/trip/trip_repository.dart';
import 'package:ttx/domain/time/local_time.dart';

import '../test_support.dart';
import '../payment/payment_data_test.dart' show insertTrip;

void main() {
  late AppDatabase db;
  late TripRepository trips;
  late TombstoneRepository tombs;
  late PaymentRepository pay;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    trips = TripRepository(db);
    tombs = TombstoneRepository(db);
    pay = PaymentRepository(db);
  });
  tearDown(() async => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) c FROM $table').get()).first.read<int>('c');

  test('local_time: ngay/thang/dinh dang theo gio VN', () {
    expect(formatLocalDateTime(baseTsMs), '24/11/2026 10:00');
    expect(localDayStartMs(baseTsMs), baseTsMs - 10 * 3600000);
    // 24/11 -> dau thang = 1/11
    expect(localMonthStartMs(baseTsMs), baseTsMs - 10 * 3600000 - 23 * 86400000);
    // 00:30 VN = 17:30 UTC hom truoc
    final int t = baseTsMs - 10 * 3600000 + 30 * 60000;
    expect(formatLocalDateTime(t), '24/11/2026 00:30');
  });

  test('danh sach, chi tiet, dieu chinh khong sua cuoc goc', () async {
    await insertTrip(db, 'a', baseTsMs);
    await trips.addAdjustment(tripId: 'a', amountVnd: -2000, reason: 'Khach xin giam', nowMs: 1);
    await trips.addAdjustment(tripId: 'a', amountVnd: 5000, reason: 'Phi cau duong', nowMs: 2);
    final TripListItem it = (await trips.listTrips()).single;
    expect(it.fareTotalVnd, 12000);
    expect(it.adjustmentVnd, 3000);
    expect(it.effectiveTotalVnd, 15000);
    final TripDetail d = (await trips.getTrip('a'))!;
    expect(d.adjustments, hasLength(2));
    // cuoc goc trong so cai van nguyen
    final QueryRow r = (await db.customSelect('SELECT fare_total_vnd FROM trip_record').get()).first;
    expect(r.read<int>('fare_total_vnd'), 12000);
    expect(() => trips.addAdjustment(tripId: 'a', amountVnd: 0, reason: 'x', nowMs: 3), throwsArgumentError);
    expect(() => trips.addAdjustment(tripId: 'a', amountVnd: 1, reason: ' ', nowMs: 3), throwsArgumentError);
  });

  test('sua ghi chu/chay thu ghi trip_edit_log; khong doi thi khong ghi', () async {
    await insertTrip(db, 'a', baseTsMs);
    await trips.editMeta(tripId: 'a', note: 'Khach quen', isTest: false, nowMs: 5);
    await trips.editMeta(tripId: 'a', note: 'Khach quen', isTest: false, nowMs: 6);
    expect(await count('trip_edit_log'), 1);
    await trips.editMeta(tripId: 'a', note: 'Khach quen', isTest: true, nowMs: 7);
    expect(await count('trip_edit_log'), 2);
    final TripDetail d = (await trips.getTrip('a'))!;
    expect(d.editCount, 2);
    expect(d.item.isTest, isTrue);
    expect(d.item.note, 'Khach quen');
  });

  test('thung rac: dua vao, khoi phuc, khong hien trong danh sach chinh', () async {
    await insertTrip(db, 'a', baseTsMs);
    await trips.moveToTrash('a', 'nham', 100);
    expect(await trips.listTrips(), isEmpty);
    final TripListItem t = (await trips.listTrash()).single;
    expect(t.archived, isTrue);
    expect(t.archivedAt, 100);
    await trips.restoreFromTrash('a');
    expect(await trips.listTrash(), isEmpty);
    expect(await trips.listTrips(), hasLength(1));
  });

  test('xoa vinh vien: bia mo + xoa trong 1 transaction, don du lieu phu', () async {
    await insertTrip(db, 'a', baseTsMs);
    await pay.record(tripId: 'a', method: 'CASH', state: 'PAID', amountVnd: 12000, nowMs: 1);
    await trips.addAdjustment(tripId: 'a', amountVnd: 1000, reason: 'x', nowMs: 2);
    await db.customStatement(
        "INSERT INTO raw_gps_points(trip_id, seq, ts_ms, lat_e7, lng_e7, accuracy_mm, speed_mmps, source, decision) VALUES ('a',0,1,1,1,1,1,'GPS','RAW')");
    await tombs.deletePermanently(tripId: 'a', reason: 'DUPLICATE', note: 'trung', nowMs: 50);
    expect(await count('trip_record'), 0);
    expect(await count('trip_payment'), 0);
    expect(await count('trip_adjustment'), 0);
    expect(await count('raw_gps_points'), 0);
    final TombstoneItem t = (await tombs.list()).single;
    expect(t.fareTotalVnd, 12000);
    expect(t.paymentMethod, 'CASH');
    expect(t.paymentState, 'PAID');
    expect(t.deletedReason, 'DUPLICATE');
    expect(t.deletedNote, 'trung');
    expect(t.reconciled, isFalse);
  });

  test('xoa vinh vien: ly do sai / khong ton tai -> khong de lai bia mo', () async {
    await insertTrip(db, 'a', baseTsMs);
    expect(() => tombs.deletePermanently(tripId: 'a', reason: 'KHAC', nowMs: 1), throwsArgumentError);
    await expectLater(tombs.deletePermanently(tripId: 'zzz', reason: 'OTHER', nowMs: 1), throwsStateError);
    expect(await count('trip_tombstone'), 0);
    expect(await count('trip_record'), 1);
  });

  test('trigger van chan DELETE truc tiep khi chua co bia mo', () async {
    await insertTrip(db, 'a', baseTsMs);
    await expectLater(db.customStatement("DELETE FROM trip_record WHERE trip_id = 'a'"), throwsA(anything));
    await expectLater(db.customStatement("UPDATE trip_record SET fare_total_vnd = 1 WHERE trip_id = 'a'"), throwsA(anything));
  });

  test('doi soat: chi sua cot doi soat, loc theo trang thai', () async {
    await insertTrip(db, 'a', baseTsMs);
    await insertTrip(db, 'b', baseTsMs + 1000);
    await tombs.deletePermanently(tripId: 'a', reason: 'TEST', nowMs: 1);
    await tombs.deletePermanently(tripId: 'b', reason: 'OTHER', nowMs: 2);
    expect(await tombs.list(reconciled: false), hasLength(2));
    await tombs.setReconciled(tripId: 'a', reconciled: true, note: 'khop so', nowMs: 9);
    expect((await tombs.list(reconciled: false)).single.tripId, 'b');
    final TombstoneItem a = (await tombs.list(reconciled: true)).single;
    expect(a.reconciledAt, 9);
    expect(a.reconciliationNote, 'khop so');
    // cot bat bien van bi chan
    await expectLater(db.customStatement("UPDATE trip_tombstone SET fare_total_vnd = 1 WHERE trip_id = 'a'"), throwsA(anything));
  });

  test('khoi phuc tu bia mo: tao lai chuyen is_reconstructed, giu cuoc va thanh toan', () async {
    await insertTrip(db, 'a', baseTsMs);
    await pay.record(tripId: 'a', method: 'QR', state: 'UNPAID', amountVnd: 12000, nowMs: 1, bankBin: '970436', bankAccount: '123', accountHolder: 'A');
    await tombs.deletePermanently(tripId: 'a', reason: 'WRONG_ENTRY', nowMs: 10);
    await tombs.restore('a', 20);
    final TripDetail d = (await trips.getTrip('a'))!;
    expect(d.isReconstructed, isTrue);
    expect(d.item.fareTotalVnd, 12000);
    expect(d.fareHash, 'h');
    expect(d.item.paymentMethod, 'QR');
    expect(d.item.paymentState, 'UNPAID');
    expect((await tombs.list()).single.restoredAt, 20);
    await expectLater(tombs.restore('a', 21), throwsStateError);
    // xoa lai duoc, bo dau da khoi phuc
    await tombs.deletePermanently(tripId: 'a', reason: 'OTHER', nowMs: 30);
    expect(await count('trip_record'), 0);
    expect((await tombs.list()).single.restoredAt, isNull);
  });

  test('doanh thu: bo qua thung rac va chay thu, chia theo thanh toan', () async {
    await insertTrip(db, 'cash', baseTsMs);
    await insertTrip(db, 'qr', baseTsMs + 1000);
    await insertTrip(db, 'unpaid', baseTsMs + 2000);
    await insertTrip(db, 'test', baseTsMs + 3000);
    await insertTrip(db, 'trash', baseTsMs + 4000);
    await insertTrip(db, 'old', baseTsMs - 3 * 86400000);
    await pay.record(tripId: 'cash', method: 'CASH', state: 'PAID', amountVnd: 12000, nowMs: 1);
    await pay.record(tripId: 'qr', method: 'QR', state: 'PAID', amountVnd: 12000, nowMs: 1);
    await trips.addAdjustment(tripId: 'qr', amountVnd: 3000, reason: 'boa', nowMs: 2);
    await trips.editMeta(tripId: 'test', note: null, isTest: true, nowMs: 3);
    await trips.moveToTrash('trash', null, 4);

    final int day = localDayStartMs(baseTsMs);
    final RevenueSummary today =
        RevenueSummary.from(await trips.tripsInRange(day, day + 86400000));
    expect(today.tripCount, 3);
    expect(today.totalVnd, 12000 + 15000 + 12000);
    expect(today.cashVnd, 12000);
    expect(today.qrPaidVnd, 15000);
    expect(today.unpaidVnd, 12000);
    final RevenueSummary week =
        RevenueSummary.from(await trips.tripsInRange(day - 6 * 86400000, day + 86400000));
    expect(week.tripCount, 4);
  });
}

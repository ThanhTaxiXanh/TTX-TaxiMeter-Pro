import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/db/app_database.dart';

const List<String> expectedTables = <String>[
  'active_trip_snapshot',
  'bank_directory',
  'bank_directory_meta',
  'driver_account',
  'driver_bank_account',
  'raw_gps_points',
  'raw_trace_meta',
  'tariff_config',
  'traffic_override',
  'traffic_report',
  'trip_adjustment',
  'trip_edit_log',
  'trip_payment',
  'trip_record',
  'trip_tombstone',
];

const List<String> expectedIndexes = <String>[
  'idx_gps_trip',
  'idx_report_status',
  'idx_tombstone_date',
  'idx_tombstone_reconciled',
  'idx_trip_archived',
  'idx_trip_hash',
  'idx_trip_started',
];

const List<String> expectedTriggers = <String>[
  'trg_adjustment_delete_needs_tombstone',
  'trg_adjustment_no_update',
  'trg_edit_log_no_update',
  'trg_tombstone_immutable',
  'trg_trip_record_delete_needs_tombstone',
  'trg_trip_record_fare_immutable',
];

Future<List<String>> names(AppDatabase db, String type) async {
  final List<QueryRow> rows = await db
      .customSelect(
        'SELECT name FROM sqlite_master WHERE type = ? '
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        variables: <Variable<Object>>[Variable<String>(type)],
      )
      .get();
  return rows.map((QueryRow r) => r.read<String>('name')).toList();
}

Future<int> count(AppDatabase db, String table, [String where = '1=1']) async {
  final QueryRow row =
      await db.customSelect('SELECT COUNT(*) AS c FROM $table WHERE $where').getSingle();
  return row.read<int>('c');
}

Future<void> insertTrip(AppDatabase db, String id, {int total = 40000}) {
  return db.customStatement(
    'INSERT INTO trip_record (trip_id, started_at, ended_at, duration_sec, '
    'distance_m, waiting_sec, fare_opening_vnd, fare_distance_vnd, '
    'fare_waiting_vnd, fare_total_vnd, config_id, config_version, '
    'config_sha256, fare_hash, created_at) '
    "VALUES (?, 1000, 2000, 1000, 3000, 0, 10000, 30000, 0, ?, 'cfg', 1, 'sha', 'hash', 3000)",
    <Object>[id, total],
  );
}

Future<void> insertTombstone(AppDatabase db, String id, {int total = 40000}) {
  return db.customStatement(
    'INSERT INTO trip_tombstone (trip_id, deleted_at, deleted_reason, '
    'trip_started_at, trip_ended_at, fare_total_vnd, fare_hash) '
    "VALUES (?, 5000, 'TEST', 1000, 2000, ?, 'hash')",
    <Object>[id, total],
  );
}

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('schema: du 15 bang, 7 index, 6 trigger, user_version = schemaVersion', () async {
    expect(await names(db, 'table'), expectedTables);
    expect(await names(db, 'index'), expectedIndexes);
    expect(await names(db, 'trigger'), expectedTriggers);
    final QueryRow v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), appSchemaVersion);
  });

  test('mo lai file DB: onCreate khong chay lai, du lieu con nguyen', () async {
    final Directory dir = Directory.systemTemp.createTempSync('ttx_db_test_');
    final File file = File('${dir.path}/t.db');
    try {
      final AppDatabase first = AppDatabase(NativeDatabase(file));
      await insertTrip(first, 'T1');
      await first.close();

      final AppDatabase second = AppDatabase(NativeDatabase(file));
      expect(await count(second, 'trip_record'), 1);
      expect(await names(second, 'trigger'), expectedTriggers);
      final QueryRow v = await second.customSelect('PRAGMA user_version').getSingle();
      expect(v.read<int>('user_version'), appSchemaVersion);
      await second.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('so cai bat bien', () {
    test('khong UPDATE truong cuoc/config cua trip_record', () async {
      await insertTrip(db, 'T1');
      for (final String set in <String>[
        'fare_total_vnd = 1',
        'fare_total_vnd = 40000', // ca khi ghi lai cung gia tri
        'fare_distance_vnd = 1',
        'fare_hash = \'x\'',
        'config_sha256 = \'x\'',
        'distance_m = 1',
      ]) {
        await expectLater(
          db.customStatement("UPDATE trip_record SET $set WHERE trip_id = 'T1'"),
          throwsA(anything),
          reason: set,
        );
      }
      expect(await count(db, 'trip_record', 'fare_total_vnd = 40000'), 1);
    });

    test('van sua duoc ghi chu / luu tru / dem sua', () async {
      await insertTrip(db, 'T1');
      await db.customStatement(
        "UPDATE trip_record SET note = 'ghi chu', archived = 1, archived_at = 9, "
        "edit_count = edit_count + 1, edited_at = 9 WHERE trip_id = 'T1'",
      );
      expect(await count(db, 'trip_record', "note = 'ghi chu' AND archived = 1"), 1);
    });

    test('DELETE trip_record khi chua co tombstone -> bi tu choi', () async {
      await insertTrip(db, 'T1');
      await expectLater(
        db.customStatement("DELETE FROM trip_record WHERE trip_id = 'T1'"),
        throwsA(anything),
      );
      expect(await count(db, 'trip_record'), 1);
    });

    test('xoa vinh vien: tombstone + DELETE trong cung transaction -> thanh cong', () async {
      await insertTrip(db, 'T1');
      await db.transaction(() async {
        await insertTombstone(db, 'T1');
        await db.customStatement("DELETE FROM trip_record WHERE trip_id = 'T1'");
      });
      expect(await count(db, 'trip_record'), 0);
      expect(await count(db, 'trip_tombstone', "trip_id = 'T1' AND fare_total_vnd = 40000"), 1);
    });

    test('loi giua transaction -> rollback, khong mat chuyen, khong co tombstone', () async {
      await insertTrip(db, 'T1');
      await expectLater(
        db.transaction(() async {
          await insertTombstone(db, 'T1');
          await db.customStatement("DELETE FROM trip_record WHERE trip_id = 'T1'");
          throw StateError('loi gia lap sau khi xoa');
        }),
        throwsStateError,
      );
      expect(await count(db, 'trip_record'), 1);
      expect(await count(db, 'trip_tombstone'), 0);
    });

    test('trip_adjustment chi them dong; xoa chi khi chuyen da co tombstone', () async {
      await insertTrip(db, 'T1');
      await db.customStatement(
        "INSERT INTO trip_adjustment (trip_id, amount_vnd, reason, created_at) "
        "VALUES ('T1', -5000, 'giam gia', 4000)",
      );
      await expectLater(
        db.customStatement('UPDATE trip_adjustment SET amount_vnd = 0'),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('DELETE FROM trip_adjustment'),
        throwsA(anything),
      );
      expect(await count(db, 'trip_adjustment'), 1);

      await db.transaction(() async {
        await insertTombstone(db, 'T1');
        await db.customStatement("DELETE FROM trip_adjustment WHERE trip_id = 'T1'");
        await db.customStatement("DELETE FROM trip_record WHERE trip_id = 'T1'");
      });
      expect(await count(db, 'trip_adjustment'), 0);
    });

    test('trip_edit_log chi them dong', () async {
      await db.customStatement(
        "INSERT INTO trip_edit_log (trip_id, field, old_value, new_value, edited_at) "
        "VALUES ('T1', 'note', NULL, 'a', 1)",
      );
      await expectLater(
        db.customStatement("UPDATE trip_edit_log SET new_value = 'b'"),
        throwsA(anything),
      );
    });

    test('tombstone: chi sua cot doi soat, khong sua so lieu', () async {
      await insertTombstone(db, 'T1');
      await db.customStatement(
        "UPDATE trip_tombstone SET reconciled = 1, reconciled_at = 7, "
        "reconciliation_note = 'ok', restored_at = 8 WHERE trip_id = 'T1'",
      );
      expect(await count(db, 'trip_tombstone', 'reconciled = 1'), 1);
      await expectLater(
        db.customStatement(
          "UPDATE trip_tombstone SET fare_total_vnd = 1 WHERE trip_id = 'T1'",
        ),
        throwsA(anything),
      );
      expect(await count(db, 'trip_tombstone', 'fare_total_vnd = 40000'), 1);
    });
  });

  group('rang buoc', () {
    test('active_trip_snapshot chi 1 dong (id = 1); ghi de bang REPLACE', () async {
      const String cols =
          'trip_id, started_at, config_id, config_version, config_sha256, state_json, updated_at';
      await db.customStatement(
        "INSERT INTO active_trip_snapshot (id, $cols) VALUES (1, 'T1', 1, 'c', 1, 's', '{}', 1)",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO active_trip_snapshot (id, $cols) VALUES (2, 'T2', 1, 'c', 1, 's', '{}', 1)",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT OR REPLACE INTO active_trip_snapshot (id, $cols) VALUES (1, 'T1', 1, 'c', 1, 's', '{\"a\":1}', 4)",
      );
      expect(await count(db, 'active_trip_snapshot'), 1);
      expect(await count(db, 'active_trip_snapshot', 'updated_at = 4'), 1);
    });

    test('tariff_config.status va tombstone.deleted_reason chi nhan gia tri hop le', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO tariff_config (config_id, config_version, effective_from, status, json_body, sha256, created_at) "
          "VALUES ('c', 1, 1, 'WRONG', '{}', 'h', 1)",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT INTO tariff_config (config_id, config_version, effective_from, status, json_body, sha256, created_at) "
        "VALUES ('c', 1, 1, 'ACTIVE', '{}', 'h', 1)",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO trip_tombstone (trip_id, deleted_at, deleted_reason, trip_started_at, trip_ended_at, fare_total_vnd, fare_hash) "
          "VALUES ('T9', 1, 'BAD', 1, 2, 1, 'h')",
        ),
        throwsA(anything),
      );
    });

    test('trip_payment.method/state chi nhan gia tri hop le', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO trip_payment (trip_id, method, state, amount_vnd, created_at, updated_at) "
          "VALUES ('T1', 'CARD', 'PAID', 1, 1, 1)",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT INTO trip_payment (trip_id, method, state, amount_vnd, created_at, updated_at) "
        "VALUES ('T1', 'QR', 'UNPAID', 40000, 1, 1)",
      );
      expect(await count(db, 'trip_payment', "confirmed_by = 'DRIVER'"), 1);
    });
  });
}

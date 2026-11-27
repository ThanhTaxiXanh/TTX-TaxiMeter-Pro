import 'package:drift/drift.dart';

import 'schema_extras.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Phien ban schema hien tai. Doi schema -> tang so nay, them nhanh
/// `onUpgrade` tuong ung va test migration.
const int appSchemaVersion = 2;

@DriftDatabase(
  tables: <Type>[
    ActiveTripSnapshot,
    TariffConfig,
    DriverBankAccount,
    BankDirectory,
    BankDirectoryMeta,
    TripRecord,
    RawGpsPoints,
    RawTraceMeta,
    TripPayment,
    TripAdjustment,
    TripEditLog,
    TripTombstone,
    TrafficOverride,
    TrafficReport,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => appSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          for (final String sql in extraTableStatements) {
            await customStatement(sql);
          }
          for (final String sql in indexStatements) {
            await customStatement(sql);
          }
          for (final String sql in ledgerTriggerStatements) {
            await customStatement(sql);
          }
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            for (final String sql in extraTableStatements) {
              await customStatement(sql);
            }
            await customStatement(migrateAccountV2);
          }
        },
      );
}

// Drift tables theo master prompt Muc 4. Tien, khoang cach, thoi gian, toa do
// E7 deu la IntColumn. Ten bang SQL = snake_case cua ten lop.
import 'package:drift/drift.dart';

/// Snapshot phuc hoi chuyen dang chay (1 dong, ghi moi 3 giay).
@DataClassName('ActiveTripSnapshotRow')
class ActiveTripSnapshot extends Table {
  IntColumn get id =>
      integer().withDefault(const Constant(1)).check(id.equals(1))();
  TextColumn get tripId => text()();
  IntColumn get startedAt => integer()();
  TextColumn get configId => text()();
  IntColumn get configVersion => integer()();
  TextColumn get configSha256 => text()();
  TextColumn get stateJson => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('TariffConfigRow')
class TariffConfig extends Table {
  TextColumn get configId => text()();
  IntColumn get configVersion => integer()();
  IntColumn get effectiveFrom => integer()();
  IntColumn get effectiveTo => integer().nullable()();

  /// DRAFT | ACTIVE | RETIRED
  TextColumn get status =>
      text().check(status.isIn(const <String>['DRAFT', 'ACTIVE', 'RETIRED']))();
  TextColumn get jsonBody => text()();
  TextColumn get sha256 => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey =>
      <Column<Object>>{configId, configVersion};
}

@DataClassName('DriverBankAccountRow')
class DriverBankAccount extends Table {
  IntColumn get id =>
      integer().withDefault(const Constant(1)).check(id.equals(1))();
  TextColumn get bin => text()();

  /// Ma hoa bang flutter_secure_storage (xem skill ledger-and-backup).
  TextColumn get accountNumberEncrypted => text()();
  TextColumn get accountHolder => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('BankDirectoryRow')
class BankDirectory extends Table {
  TextColumn get bin => text()();
  TextColumn get code => text()();
  TextColumn get shortName => text()();
  IntColumn get transferSupported => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(9999))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bin};
}

@DataClassName('BankDirectoryMetaRow')
class BankDirectoryMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

@DataClassName('TripRecordRow')
class TripRecord extends Table {
  TextColumn get tripId => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer()();
  IntColumn get durationSec => integer()();
  IntColumn get distanceM => integer()();
  IntColumn get waitingSec => integer()();
  IntColumn get fareOpeningVnd => integer()();
  IntColumn get fareDistanceVnd => integer()();
  IntColumn get fareWaitingVnd => integer()();
  IntColumn get fareSurchargeVnd => integer().withDefault(const Constant(0))();
  IntColumn get fareTotalVnd => integer()();
  TextColumn get configId => text()();
  IntColumn get configVersion => integer()();
  TextColumn get configSha256 => text()();
  TextColumn get fareHash => text()();
  TextColumn get rawPointsHash => text().nullable()();
  IntColumn get startLatE7 => integer().nullable()();
  IntColumn get startLngE7 => integer().nullable()();
  IntColumn get endLatE7 => integer().nullable()();
  IntColumn get endLngE7 => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get isTest => integer().withDefault(const Constant(0))();
  IntColumn get isReconstructed => integer().withDefault(const Constant(0))();
  IntColumn get reconstructedAt => integer().nullable()();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  IntColumn get archivedAt => integer().nullable()();
  TextColumn get archiveReason => text().nullable()();
  IntColumn get editedAt => integer().nullable()();
  IntColumn get editCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{tripId};
}

@DataClassName('RawGpsPointRow')
class RawGpsPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tripId => text()();
  IntColumn get seq => integer()();
  IntColumn get tsMs => integer()();
  IntColumn get latE7 => integer()();
  IntColumn get lngE7 => integer()();
  IntColumn get accuracyMm => integer()();
  IntColumn get speedMmps => integer()();
  IntColumn get bearingMillideg => integer().nullable()();
  IntColumn get isMock => integer().withDefault(const Constant(0))();
  TextColumn get source => text()();
  TextColumn get decision => text()();
  TextColumn get rejectReason => text().nullable()();
}

@DataClassName('RawTraceMetaRow')
class RawTraceMeta extends Table {
  TextColumn get tripId => text()();
  IntColumn get pointCount => integer()();
  IntColumn get acceptedCount => integer()();
  IntColumn get sizeBytes => integer()();
  IntColumn get archivedAt => integer().nullable()();
  IntColumn get purgedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{tripId};
}

@DataClassName('TripPaymentRow')
class TripPayment extends Table {
  TextColumn get tripId => text()();

  /// CASH | QR
  TextColumn get method => text().check(method.isIn(const <String>['CASH', 'QR']))();

  /// UNPAID | PAID | VOID
  TextColumn get state =>
      text().check(state.isIn(const <String>['UNPAID', 'PAID', 'VOID']))();
  IntColumn get amountVnd => integer()();
  TextColumn get qrContent => text().nullable()();
  TextColumn get bankBin => text().nullable()();
  TextColumn get bankAccount => text().nullable()();
  TextColumn get accountHolder => text().nullable()();
  IntColumn get paidAt => integer().nullable()();
  TextColumn get confirmedBy => text().withDefault(const Constant('DRIVER'))();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{tripId};
}

/// Dieu chinh tien: chi them dong moi (append-only), khong sua/xoa.
@DataClassName('TripAdjustmentRow')
class TripAdjustment extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tripId => text()();
  IntColumn get amountVnd => integer()();
  TextColumn get reason => text()();
  IntColumn get createdAt => integer()();
  TextColumn get createdBy => text().withDefault(const Constant('DRIVER'))();
}

@DataClassName('TripEditLogRow')
class TripEditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tripId => text()();
  TextColumn get field => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  IntColumn get editedAt => integer()();
}

@DataClassName('TripTombstoneRow')
class TripTombstone extends Table {
  TextColumn get tripId => text()();
  IntColumn get deletedAt => integer()();

  /// DUPLICATE | TEST | WRONG_ENTRY | OTHER
  TextColumn get deletedReason => text().check(
        deletedReason.isIn(
          const <String>['DUPLICATE', 'TEST', 'WRONG_ENTRY', 'OTHER'],
        ),
      )();
  TextColumn get deletedNote => text().nullable()();
  IntColumn get tripStartedAt => integer()();
  IntColumn get tripEndedAt => integer()();
  IntColumn get durationSec => integer().nullable()();
  IntColumn get distanceM => integer().nullable()();
  IntColumn get waitingSec => integer().nullable()();
  IntColumn get fareOpeningVnd => integer().nullable()();
  IntColumn get fareDistanceVnd => integer().nullable()();
  IntColumn get fareWaitingVnd => integer().nullable()();
  IntColumn get fareSurchargeVnd => integer().nullable()();
  IntColumn get fareTotalVnd => integer()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get paymentState => text().nullable()();
  TextColumn get configId => text().nullable()();
  IntColumn get configVersion => integer().nullable()();
  TextColumn get configSha256 => text().nullable()();
  TextColumn get fareHash => text()();
  TextColumn get rawPointsHash => text().nullable()();
  TextColumn get bankBin => text().nullable()();
  TextColumn get bankAccount => text().nullable()();
  TextColumn get accountHolder => text().nullable()();
  TextColumn get driverNote => text().nullable()();
  IntColumn get reconciled => integer().withDefault(const Constant(0))();
  IntColumn get reconciledAt => integer().nullable()();
  TextColumn get reconciliationNote => text().nullable()();
  IntColumn get restoredAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{tripId};
}

@DataClassName('TrafficOverrideRow')
class TrafficOverride extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// SPEED_LIMIT | SIGN | CAMERA
  TextColumn get kind => text().check(
        kind.isIn(const <String>['SPEED_LIMIT', 'SIGN', 'CAMERA']),
      )();
  TextColumn get osmWayId => text().nullable()();
  IntColumn get latE7 => integer().nullable()();
  IntColumn get lngE7 => integer().nullable()();
  IntColumn get speedKmh => integer().nullable()();
  TextColumn get signCode => text().nullable()();
  TextColumn get cameraType => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('MANUAL'))();
  IntColumn get validFrom => integer().nullable()();
  IntColumn get validTo => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

@DataClassName('TrafficReportRow')
class TrafficReport extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  IntColumn get targetOverrideId => integer().nullable()();
  TextColumn get proposedData => text()();
  IntColumn get latE7 => integer().nullable()();
  IntColumn get lngE7 => integer().nullable()();
  TextColumn get evidencePath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  IntColumn get reportedAt => integer()();
  IntColumn get reviewedAt => integer().nullable()();
  TextColumn get reviewerNote => text().nullable()();
}

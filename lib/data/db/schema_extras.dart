// Index (co DESC) va trigger bat bien so cai, chay sau createAll().
//
// Trigger de DB tu tu choi cac thao tac bi cam, bat ke code app:
//  - UPDATE truong cuoc/config cua trip_record  (doi tien phai qua trip_adjustment)
//  - DELETE trip_record khi chua co trip_tombstone cung trip_id
//    (insert tombstone TRONG CUNG transaction truoc khi DELETE)
//  - UPDATE/DELETE trip_adjustment, UPDATE trip_edit_log (chi them dong)
//  - UPDATE cac cot so lieu cua trip_tombstone (chi cot doi soat duoc sua)

const List<String> indexStatements = <String>[
  'CREATE INDEX idx_trip_started ON trip_record(started_at DESC)',
  'CREATE INDEX idx_trip_archived ON trip_record(archived, started_at DESC)',
  'CREATE INDEX idx_trip_hash ON trip_record(fare_hash)',
  'CREATE INDEX idx_gps_trip ON raw_gps_points(trip_id, seq)',
  'CREATE INDEX idx_tombstone_date ON trip_tombstone(trip_started_at DESC)',
  'CREATE INDEX idx_tombstone_reconciled '
      'ON trip_tombstone(reconciled, trip_started_at DESC)',
  'CREATE INDEX idx_report_status ON traffic_report(status, reported_at DESC)',
];

const List<String> ledgerTriggerStatements = <String>[
  '''
CREATE TRIGGER trg_trip_record_fare_immutable
BEFORE UPDATE OF trip_id, started_at, ended_at, duration_sec, distance_m,
  waiting_sec, fare_opening_vnd, fare_distance_vnd, fare_waiting_vnd,
  fare_surcharge_vnd, fare_total_vnd, config_id, config_version,
  config_sha256, fare_hash ON trip_record
BEGIN
  SELECT RAISE(ABORT, 'trip_record: truong cuoc/config bat bien; doi tien qua trip_adjustment');
END''',
  '''
CREATE TRIGGER trg_trip_record_delete_needs_tombstone
BEFORE DELETE ON trip_record
WHEN NOT EXISTS (SELECT 1 FROM trip_tombstone WHERE trip_id = OLD.trip_id)
BEGIN
  SELECT RAISE(ABORT, 'trip_record: phai insert trip_tombstone truoc khi xoa');
END''',
  '''
CREATE TRIGGER trg_adjustment_no_update
BEFORE UPDATE ON trip_adjustment
BEGIN
  SELECT RAISE(ABORT, 'trip_adjustment: chi them dong, khong sua');
END''',
  '''
CREATE TRIGGER trg_adjustment_delete_needs_tombstone
BEFORE DELETE ON trip_adjustment
WHEN NOT EXISTS (SELECT 1 FROM trip_tombstone WHERE trip_id = OLD.trip_id)
BEGIN
  SELECT RAISE(ABORT, 'trip_adjustment: chi xoa khi chuyen da co tombstone');
END''',
  '''
CREATE TRIGGER trg_edit_log_no_update
BEFORE UPDATE ON trip_edit_log
BEGIN
  SELECT RAISE(ABORT, 'trip_edit_log: chi them dong, khong sua');
END''',
  '''
CREATE TRIGGER trg_tombstone_immutable
BEFORE UPDATE OF trip_id, deleted_at, deleted_reason, trip_started_at,
  trip_ended_at, duration_sec, distance_m, waiting_sec, fare_opening_vnd,
  fare_distance_vnd, fare_waiting_vnd, fare_surcharge_vnd, fare_total_vnd,
  payment_method, payment_state, config_id, config_version, config_sha256,
  fare_hash, raw_points_hash, bank_bin, bank_account, account_holder
ON trip_tombstone
BEGIN
  SELECT RAISE(ABORT, 'trip_tombstone: chi duoc sua cot doi soat (reconciled*, restored_at, ghi chu)');
END''',
];

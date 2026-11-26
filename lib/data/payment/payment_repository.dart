import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';

class PaymentInfo {
  const PaymentInfo({required this.method, required this.state, required this.amountVnd});
  final String method; // CASH | QR
  final String state; // UNPAID | PAID | VOID
  final int amountVnd;
}

/// Ghi nhan thanh toan cua chuyen (bang trip_payment). Khong sua trip_record.
class PaymentRepository {
  PaymentRepository(this._db);
  final AppDatabase _db;

  /// So thu tu chuyen trong ngay (1..999), tinh theo gio dia phuong.
  Future<int> sequenceInDay(int tripStartedAtMs, {int offsetMinutes = 420}) async {
    const int day = 86400000;
    final int local = tripStartedAtMs + offsetMinutes * 60000;
    int d = local ~/ day;
    if (local % day < 0) d -= 1;
    final int dayStart = d * day - offsetMinutes * 60000;
    final List<QueryRow> r = await _db.customSelect(
      'SELECT COUNT(*) c FROM trip_record WHERE started_at >= ? AND started_at <= ?',
      variables: <Variable<Object>>[
        Variable<int>(dayStart),
        Variable<int>(tripStartedAtMs),
      ],
    ).get();
    final int n = r.first.read<int>('c');
    return n < 1 ? 1 : (n > 999 ? 999 : n);
  }

  Future<void> record({
    required String tripId,
    required String method,
    required String state,
    required int amountVnd,
    required int nowMs,
    String? qrContent,
    String? bankBin,
    String? bankAccount,
    String? accountHolder,
  }) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO trip_payment(trip_id, method, state, amount_vnd, '
      'qr_content, bank_bin, bank_account, account_holder, paid_at, confirmed_by, '
      'created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,\'DRIVER\',?,?)',
      <Object?>[
        tripId, method, state, amountVnd, qrContent, bankBin, bankAccount,
        accountHolder, state == 'PAID' ? nowMs : null, nowMs, nowMs,
      ],
    );
  }

  Future<void> markPaid(String tripId, int nowMs) async {
    await _db.customStatement(
      "UPDATE trip_payment SET state = 'PAID', paid_at = ?, updated_at = ? "
      "WHERE trip_id = ? AND state = 'UNPAID'",
      <Object?>[nowMs, nowMs, tripId],
    );
  }

  Future<PaymentInfo?> get(String tripId) async {
    final List<QueryRow> r = await _db.customSelect(
      'SELECT method, state, amount_vnd FROM trip_payment WHERE trip_id = ?',
      variables: <Variable<Object>>[Variable<String>(tripId)],
    ).get();
    if (r.isEmpty) return null;
    return PaymentInfo(
      method: r.first.read<String>('method'),
      state: r.first.read<String>('state'),
      amountVnd: r.first.read<int>('amount_vnd'),
    );
  }
}

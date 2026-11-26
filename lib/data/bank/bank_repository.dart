import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';
import 'bank_seed.dart';

class BankInfo {
  const BankInfo({required this.bin, required this.code, required this.shortName});
  final String bin;
  final String code;
  final String shortName;
}

class DriverAccount {
  const DriverAccount({required this.bin, required this.accountNumber, required this.holder});
  final String bin;
  final String accountNumber;
  final String holder;
}

/// Danh muc ngan hang (offline) + tai khoan nhan tien cua chu xe.
///
/// Quyet dinh chu du an: so tai khoan nam trong database.db (de restore khong
/// phai nhap lai). Cot `account_number_encrypted` giu ten cu de on dinh schema
/// nhung luu so tai khoan o dang doc duoc.
class BankRepository {
  BankRepository(this._db);
  final AppDatabase _db;

  Future<void> ensureSeeded(int nowMs) async {
    await _db.transaction(() async {
      for (int i = 0; i < bankSeeds.length; i++) {
        final BankSeed b = bankSeeds[i];
        await _db.customStatement(
          'INSERT OR IGNORE INTO bank_directory(bin, code, short_name, '
          'transfer_supported, sort_order, updated_at) VALUES (?,?,?,1,?,?)',
          <Object?>[b.bin, b.code, b.shortName, i, nowMs],
        );
      }
    });
  }

  Future<List<BankInfo>> listBanks() async {
    final List<QueryRow> rows = await _db
        .customSelect('SELECT bin, code, short_name FROM bank_directory '
            'WHERE transfer_supported = 1 ORDER BY sort_order, short_name')
        .get();
    return rows
        .map((QueryRow r) => BankInfo(
              bin: r.read<String>('bin'),
              code: r.read<String>('code'),
              shortName: r.read<String>('short_name'),
            ))
        .toList();
  }

  Future<DriverAccount?> getDriverAccount() async {
    final List<QueryRow> rows =
        await _db.customSelect('SELECT * FROM driver_bank_account WHERE id = 1').get();
    if (rows.isEmpty) return null;
    final QueryRow r = rows.first;
    return DriverAccount(
      bin: r.read<String>('bin'),
      accountNumber: r.read<String>('account_number_encrypted'),
      holder: r.read<String>('account_holder'),
    );
  }

  Future<void> saveDriverAccount(DriverAccount a, int nowMs) async {
    if (a.bin.length != 6 || a.accountNumber.isEmpty || a.holder.trim().isEmpty) {
      throw ArgumentError('Thieu ngan hang, so tai khoan hoac ten chu tai khoan');
    }
    await _db.customStatement(
      'INSERT OR REPLACE INTO driver_bank_account(id, bin, account_number_encrypted, '
      'account_holder, updated_at) VALUES (1, ?, ?, ?, ?)',
      <Object?>[a.bin, a.accountNumber, a.holder.trim(), nowMs],
    );
  }

  Future<BankInfo?> findByBin(String bin) async {
    final List<QueryRow> rows = await _db.customSelect(
      'SELECT bin, code, short_name FROM bank_directory WHERE bin = ?',
      variables: <Variable<Object>>[Variable<String>(bin)],
    ).get();
    if (rows.isEmpty) return null;
    final QueryRow r = rows.first;
    return BankInfo(
        bin: r.read<String>('bin'),
        code: r.read<String>('code'),
        shortName: r.read<String>('short_name'));
  }
}

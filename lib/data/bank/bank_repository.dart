import 'dart:typed_data';

import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';
import 'bank_seed.dart';

class BankInfo {
  const BankInfo({required this.bin, required this.code, required this.shortName});
  final String bin;
  final String code;
  final String shortName;
}

/// Tai khoan nhan tien. Logo giua/duoi QR luu truc tiep (PNG da thu nho) de di theo ban sao luu.
class DriverAccount {
  const DriverAccount({
    required this.bin,
    required this.accountNumber,
    required this.holder,
    this.id,
    this.label = '',
    this.isDefault = false,
    this.centerLogo,
    this.bottomLogo,
  });
  final int? id;
  final String label;
  final String bin;
  final String accountNumber;
  final String holder;
  final bool isDefault;
  final Uint8List? centerLogo;
  final Uint8List? bottomLogo;

  DriverAccount copyWith({
    String? label,
    String? bin,
    String? accountNumber,
    String? holder,
    bool? isDefault,
    Uint8List? centerLogo,
    Uint8List? bottomLogo,
    bool clearCenter = false,
    bool clearBottom = false,
  }) =>
      DriverAccount(
        id: id,
        label: label ?? this.label,
        bin: bin ?? this.bin,
        accountNumber: accountNumber ?? this.accountNumber,
        holder: holder ?? this.holder,
        isDefault: isDefault ?? this.isDefault,
        centerLogo: clearCenter ? null : (centerLogo ?? this.centerLogo),
        bottomLogo: clearBottom ? null : (bottomLogo ?? this.bottomLogo),
      );
}

/// Danh muc ngan hang (offline) + cac tai khoan nhan tien cua chu xe (nhieu tai khoan, 1 mac dinh).
///
/// Quyet dinh chu du an: so tai khoan nam trong database.db (de restore khong phai nhap lai),
/// luu o dang doc duoc.
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

  DriverAccount _row(QueryRow r) => DriverAccount(
        id: r.read<int>('id'),
        label: r.read<String>('label'),
        bin: r.read<String>('bin'),
        accountNumber: r.read<String>('account_number'),
        holder: r.read<String>('account_holder'),
        isDefault: r.read<int>('is_default') == 1,
        centerLogo: r.readNullable<Uint8List>('center_logo'),
        bottomLogo: r.readNullable<Uint8List>('bottom_logo'),
      );

  /// Mac dinh dung dau danh sach.
  Future<List<DriverAccount>> listAccounts() async {
    final List<QueryRow> rows =
        await _db.customSelect('SELECT * FROM driver_account ORDER BY is_default DESC, id').get();
    return rows.map(_row).toList();
  }

  /// Tai khoan mac dinh (neu chua dat thi tai khoan dau tien); null neu chua co.
  Future<DriverAccount?> getDriverAccount() async {
    final List<DriverAccount> l = await listAccounts();
    return l.isEmpty ? null : l.first;
  }

  /// Them (id null) hoac sua tai khoan. Tai khoan dau tien luon la mac dinh. Tra ve id.
  Future<int> saveAccount(DriverAccount a, int nowMs) async {
    if (a.bin.length != 6 || a.accountNumber.isEmpty || a.holder.trim().isEmpty) {
      throw ArgumentError('Thieu ngan hang, so tai khoan hoac ten chu tai khoan');
    }
    final String label = a.label.trim();
    return _db.transaction(() async {
      final int count =
          (await _db.customSelect('SELECT COUNT(*) AS c FROM driver_account').getSingle()).read<int>('c');
      int id;
      if (a.id == null) {
        final bool makeDefault = a.isDefault || count == 0;
        if (makeDefault) await _db.customStatement('UPDATE driver_account SET is_default = 0');
        await _db.customStatement(
          'INSERT INTO driver_account(label, bin, account_number, account_holder, is_default, '
          'center_logo, bottom_logo, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
          <Object?>[label, a.bin, a.accountNumber, a.holder.trim(), makeDefault ? 1 : 0, a.centerLogo, a.bottomLogo, nowMs, nowMs],
        );
        id = (await _db.customSelect('SELECT MAX(id) AS m FROM driver_account').getSingle()).read<int>('m');
      } else {
        id = a.id!;
        await _db.customStatement(
          'UPDATE driver_account SET label=?, bin=?, account_number=?, account_holder=?, '
          'center_logo=?, bottom_logo=?, updated_at=? WHERE id=?',
          <Object?>[label, a.bin, a.accountNumber, a.holder.trim(), a.centerLogo, a.bottomLogo, nowMs, id],
        );
        if (a.isDefault) await setDefault(id);
      }
      return id;
    });
  }

  /// Giu tuong thich: luu thanh tai khoan mac dinh (sua tai khoan mac dinh hien co, hoac tao moi).
  Future<void> saveDriverAccount(DriverAccount a, int nowMs) async {
    final DriverAccount? cur = await getDriverAccount();
    await saveAccount(
      DriverAccount(
        id: cur?.id,
        label: a.label.isEmpty ? (cur?.label ?? '') : a.label,
        bin: a.bin,
        accountNumber: a.accountNumber,
        holder: a.holder,
        isDefault: true,
        centerLogo: a.centerLogo ?? cur?.centerLogo,
        bottomLogo: a.bottomLogo ?? cur?.bottomLogo,
      ),
      nowMs,
    );
  }

  Future<void> setDefault(int id) async {
    await _db.customStatement('UPDATE driver_account SET is_default = CASE WHEN id = ? THEN 1 ELSE 0 END', <Object?>[id]);
  }

  /// Xoa tai khoan; neu xoa tai khoan mac dinh thi tai khoan con lai dau tien len mac dinh.
  Future<void> deleteAccount(int id) async {
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM driver_account WHERE id = ?', <Object?>[id]);
      final List<QueryRow> d = await _db.customSelect('SELECT id FROM driver_account WHERE is_default = 1').get();
      if (d.isEmpty) {
        await _db.customStatement(
            'UPDATE driver_account SET is_default = 1 WHERE id = (SELECT MIN(id) FROM driver_account)');
      }
    });
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

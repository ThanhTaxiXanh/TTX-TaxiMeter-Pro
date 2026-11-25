import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// Mo co so du lieu that tren thiet bi (WAL de ghi snapshot ben hon).
AppDatabase openAppDatabase() {
  final LazyDatabase executor = LazyDatabase(() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dir.path, 'ttx_taximeter.db'));
    return NativeDatabase.createInBackground(
      file,
      setup: (dynamic db) {
        db.execute('PRAGMA journal_mode = WAL;');
      },
    );
  });
  return AppDatabase(executor);
}

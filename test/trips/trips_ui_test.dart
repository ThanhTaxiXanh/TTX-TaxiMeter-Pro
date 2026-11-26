import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/app/providers.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/trip/tombstone_repository.dart';
import 'package:ttx/data/trip/trip_models.dart';
import 'package:ttx/data/trip/trip_repository.dart';
import 'package:ttx/ui/ledger/revenue_screen.dart';
import 'package:ttx/ui/ledger/trash_screen.dart';
import 'package:ttx/ui/trips/trip_detail_screen.dart';
import 'package:ttx/ui/trips/trip_list_screen.dart';

import '../payment/payment_data_test.dart' show insertTrip;
import '../test_support.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget app(Widget home) => ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => baseTsMs + 60000),
        ],
        child: MaterialApp(home: home),
      );

  testWidgets('danh sach hien chuyen, mo chi tiet', (WidgetTester tester) async {
    await tester.runAsync(() => insertTrip(db, 'a', baseTsMs));
    await tester.pumpWidget(app(const TripListScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trip_a')), findsOneWidget);
    expect(find.textContaining('12.000'), findsWidgets);
    await tester.tap(find.byKey(const Key('trip_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('total')), findsOneWidget);
  });

  testWidgets('chi tiet: dieu chinh tien cap nhat tong', (WidgetTester tester) async {
    await tester.runAsync(() => insertTrip(db, 'a', baseTsMs));
    await tester.pumpWidget(app(const TripDetailScreen(tripId: 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn_adjust')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('adj_amount')), '3000');
    await tester.enterText(find.byKey(const Key('adj_reason')), 'boa');
    await tester.tap(find.byKey(const Key('adj_ok')));
    await tester.pumpAndSettle();
    final Text total = tester.widget<Text>(find.byKey(const Key('total')));
    expect(total.data, '15.000 ₫');
  });

  testWidgets('thung rac: khoi phuc va xoa vinh vien', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await insertTrip(db, 'a', baseTsMs);
      await insertTrip(db, 'b', baseTsMs + 1000);
      final TripRepository r = TripRepository(db);
      await r.moveToTrash('a', null, 1);
      await r.moveToTrash('b', null, 2);
    });
    await tester.pumpWidget(app(const TrashScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trash_a')), findsNothing);

    await tester.tap(find.byKey(const Key('forever_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('del_ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trash_b')), findsNothing);
    final List<TombstoneItem>? t =
        await tester.runAsync<List<TombstoneItem>>(() => TombstoneRepository(db).list());
    expect(t!.single.tripId, 'b');
    final List<TripListItem>? live =
        await tester.runAsync<List<TripListItem>>(() => TripRepository(db).listTrips());
    expect(live!.single.tripId, 'a');
  });

  testWidgets('doanh thu hom nay', (WidgetTester tester) async {
    await tester.runAsync(() => insertTrip(db, 'a', baseTsMs));
    await tester.pumpWidget(app(const RevenueScreen()));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('rev_total'))).data, '12.000 ₫');
    expect(tester.widget<Text>(find.byKey(const Key('rev_count'))).data, '1');
  });
}

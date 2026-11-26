class TripListItem {
  const TripListItem({
    required this.tripId,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
    required this.distanceM,
    required this.waitingSec,
    required this.fareTotalVnd,
    required this.adjustmentVnd,
    required this.paymentMethod,
    required this.paymentState,
    required this.isTest,
    required this.archived,
    required this.archivedAt,
    required this.archiveReason,
    required this.note,
  });

  final String tripId;
  final int startedAt;
  final int endedAt;
  final int durationSec;
  final int distanceM;
  final int waitingSec;
  final int fareTotalVnd;
  final int adjustmentVnd;
  final String? paymentMethod;
  final String? paymentState;
  final bool isTest;
  final bool archived;
  final int? archivedAt;
  final String? archiveReason;
  final String? note;

  /// Cuoc goc + cac dieu chinh (fare_total_vnd khong bao gio bi sua).
  int get effectiveTotalVnd => fareTotalVnd + adjustmentVnd;
}

class Adjustment {
  const Adjustment(this.id, this.amountVnd, this.reason, this.createdAt);
  final int id;
  final int amountVnd;
  final String reason;
  final int createdAt;
}

class TripDetail {
  const TripDetail({
    required this.item,
    required this.fareOpening,
    required this.fareDistance,
    required this.fareWaiting,
    required this.fareSurcharge,
    required this.configId,
    required this.configVersion,
    required this.fareHash,
    required this.adjustments,
    required this.editCount,
    required this.isReconstructed,
  });

  final TripListItem item;
  final int fareOpening;
  final int fareDistance;
  final int fareWaiting;
  final int fareSurcharge;
  final String configId;
  final int configVersion;
  final String fareHash;
  final List<Adjustment> adjustments;
  final int editCount;
  final bool isReconstructed;
}

class TombstoneItem {
  const TombstoneItem({
    required this.tripId,
    required this.deletedAt,
    required this.deletedReason,
    required this.deletedNote,
    required this.tripStartedAt,
    required this.tripEndedAt,
    required this.distanceM,
    required this.fareTotalVnd,
    required this.paymentMethod,
    required this.paymentState,
    required this.reconciled,
    required this.reconciledAt,
    required this.reconciliationNote,
    required this.restoredAt,
  });

  final String tripId;
  final int deletedAt;
  final String deletedReason;
  final String? deletedNote;
  final int tripStartedAt;
  final int tripEndedAt;
  final int? distanceM;
  final int fareTotalVnd;
  final String? paymentMethod;
  final String? paymentState;
  final bool reconciled;
  final int? reconciledAt;
  final String? reconciliationNote;
  final int? restoredAt;
}

/// Tong hop doanh thu (thuan, so nguyen).
class RevenueSummary {
  const RevenueSummary({
    required this.tripCount,
    required this.totalVnd,
    required this.cashVnd,
    required this.qrPaidVnd,
    required this.unpaidVnd,
    required this.distanceM,
  });

  factory RevenueSummary.from(Iterable<TripListItem> trips) {
    int n = 0, total = 0, cash = 0, qr = 0, unpaid = 0, dist = 0;
    for (final TripListItem t in trips) {
      if (t.archived || t.isTest) continue;
      n++;
      final int v = t.effectiveTotalVnd;
      total += v;
      dist += t.distanceM;
      if (t.paymentState == 'PAID') {
        if (t.paymentMethod == 'CASH') {
          cash += v;
        } else {
          qr += v;
        }
      } else if (t.paymentState != 'VOID') {
        unpaid += v;
      }
    }
    return RevenueSummary(
      tripCount: n,
      totalVnd: total,
      cashVnd: cash,
      qrPaidVnd: qr,
      unpaidVnd: unpaid,
      distanceM: dist,
    );
  }

  final int tripCount;
  final int totalVnd;
  final int cashVnd;
  final int qrPaidVnd;
  final int unpaidVnd;
  final int distanceM;
}

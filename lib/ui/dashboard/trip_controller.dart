import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/taximeter_engine.dart';
import '../../data/trip/trip_store.dart';
import '../../domain/models/gps_sample.dart';
import '../../domain/models/surcharge.dart';
import '../../domain/models/tariff_config_v2.dart';
import '../../domain/trip/active_trip_session.dart';
import '../../platform/location_service.dart';

enum TripPhase { idle, running, saving }

enum GpsStatus { none, searching, good, weak }

class TripUiState {
  const TripUiState({
    this.phase = TripPhase.idle,
    this.fareVnd = 0,
    this.distanceM = 0,
    this.waitingSec = 0,
    this.elapsedSec = 0,
    this.speedMmps = -1,
    this.waitingNow = false,
    this.gps = GpsStatus.none,
    this.error,
    this.finished,
    this.restored = false,
  });

  final TripPhase phase;
  final int fareVnd;
  final int distanceM;
  final int waitingSec;
  final int elapsedSec;
  final int speedMmps;
  final bool waitingNow;
  final GpsStatus gps;
  final String? error;

  /// Chuyen vua ket thuc (de hien tong ket 1 lan).
  final FareResult? finished;
  final bool restored;

  bool get running => phase == TripPhase.running;

  TripUiState copyWith({
    TripPhase? phase,
    int? fareVnd,
    int? distanceM,
    int? waitingSec,
    int? elapsedSec,
    int? speedMmps,
    bool? waitingNow,
    GpsStatus? gps,
    String? error,
    bool clearError = false,
    FareResult? finished,
    bool clearFinished = false,
    bool? restored,
  }) =>
      TripUiState(
        phase: phase ?? this.phase,
        fareVnd: fareVnd ?? this.fareVnd,
        distanceM: distanceM ?? this.distanceM,
        waitingSec: waitingSec ?? this.waitingSec,
        elapsedSec: elapsedSec ?? this.elapsedSec,
        speedMmps: speedMmps ?? this.speedMmps,
        waitingNow: waitingNow ?? this.waitingNow,
        gps: gps ?? this.gps,
        error: clearError ? null : (error ?? this.error),
        finished: clearFinished ? null : (finished ?? this.finished),
        restored: restored ?? this.restored,
      );
}

/// Dieu phoi chuyen dang chay: GPS -> session -> snapshot moi 3 giay.
class TripController extends Notifier<TripUiState> {
  static const Duration flushEvery = Duration(seconds: 3);
  static const Duration tickEvery = Duration(seconds: 1);
  static const int weakAccuracyMm = 35000;
  static const int staleMs = 5000;

  ActiveTripSession? _session;
  StreamSubscription<GpsSample>? _sub;
  Timer? _flushTimer;
  Timer? _tickTimer;
  int _flushedSeq = 0;
  int _lastSampleArrivalMs = 0;

  TripStore get _store => ref.read(tripStoreProvider);
  int _now() => ref.read(clockProvider)();

  @override
  TripUiState build() {
    ref.onDispose(_cancelAll);
    return const TripUiState();
  }

  /// Goi khi mo app: neu co chuyen dang do (app bi tat) thi chay tiep.
  Future<void> restoreOnLaunch() async {
    if (_session != null) return;
    final RestoredTrip? r = await _store.loadActive();
    if (r == null) return;
    _session = r.session;
    _flushedSeq = r.session.sampleCount;
    state = state.copyWith(restored: true);
    await _beginRunning(requirePermission: true);
  }

  Future<void> startTrip() async {
    if (_session != null) return;
    state = state.copyWith(clearError: true, clearFinished: true, restored: false);
    final int now = _now();
    try {
      final TariffConfigV2 cfg = await _store.resolveActiveTariff(now);
      _session = ActiveTripSession(
        tripId: 'ttx-$now',
        startedAtMs: now,
        config: cfg,
        contexts: SurchargeContexts(
          tripStartTimeMs: now,
          timezone: 'Asia/Ho_Chi_Minh',
          vehicleType: 'CAR_4',
          geofenceMatches: const <String>[],
        ),
      );
      _flushedSeq = 0;
      await _beginRunning(requirePermission: true);
    } catch (e) {
      _session = null;
      state = state.copyWith(error: 'Không bắt đầu được chuyến: $e');
    }
  }

  Future<void> _beginRunning({required bool requirePermission}) async {
    final LocationService loc = ref.read(locationServiceProvider);
    if (requirePermission) {
      final LocationPermissionState p = await loc.ensurePermission();
      if (p != LocationPermissionState.granted) {
        // Chuyen khoi phuc van con nguyen trong snapshot, se thu lai lan mo sau.
        _session = null;
        state = state.copyWith(error: _permissionMessage(p));
        return;
      }
    }
    await ref.read(screenAwakeProvider).enable();
    _lastSampleArrivalMs = _now();
    _sub = loc.start().listen(_onSample, onError: (Object e) {
      state = state.copyWith(error: 'Lỗi GPS: $e', gps: GpsStatus.none);
    });
    _flushTimer = Timer.periodic(flushEvery, (_) => flush());
    _tickTimer = Timer.periodic(tickEvery, (_) => tick());
    _publish(phase: TripPhase.running, gps: GpsStatus.searching);
    await flush();
  }

  String _permissionMessage(LocationPermissionState p) {
    switch (p) {
      case LocationPermissionState.serviceOff:
        return 'GPS đang tắt. Hãy bật định vị rồi thử lại.';
      case LocationPermissionState.deniedForever:
        return 'Quyền vị trí bị chặn. Vào Cài đặt Android > Ứng dụng > TTX để cấp quyền.';
      case LocationPermissionState.denied:
      case LocationPermissionState.granted:
        return 'Cần cấp quyền vị trí để tính cước.';
    }
  }

  void _onSample(GpsSample s) {
    final ActiveTripSession? ses = _session;
    if (ses == null) return;
    ses.addSample(s);
    _lastSampleArrivalMs = _now();
    _publish();
  }

  /// Moi giay: cap nhat dong ho va tinh trang GPS.
  void tick() => _publish();

  /// Moi 3 giay: ghi mau moi + snapshot.
  Future<void> flush() async {
    final ActiveTripSession? ses = _session;
    if (ses == null) return;
    final int from = _flushedSeq;
    final int count = ses.sampleCount;
    try {
      await _store.saveProgress(session: ses, fromSeq: from, nowMs: _now());
      if (_flushedSeq == from) _flushedSeq = count;
    } catch (e) {
      state = state.copyWith(error: 'Không ghi được dữ liệu chuyến: $e');
    }
  }

  void _publish({TripPhase? phase, GpsStatus? gps}) {
    final ActiveTripSession? ses = _session;
    if (ses == null) return;
    final FareResult f = ses.liveFare;
    final GpsSample? last = ses.lastSample;
    final int now = _now();
    GpsStatus g = GpsStatus.searching;
    if (last != null) {
      final bool stale = now - _lastSampleArrivalMs > staleMs;
      g = (stale || last.accuracyMm > weakAccuracyMm) ? GpsStatus.weak : GpsStatus.good;
    }
    state = state.copyWith(
      phase: phase ?? state.phase,
      fareVnd: f.fareTotal,
      distanceM: f.distanceM,
      waitingSec: f.waitingSec,
      elapsedSec: (now - ses.startedAtMs) ~/ 1000,
      speedMmps: f.lastSpeedMmps,
      waitingNow: f.waitingNow,
      gps: gps != null && last == null ? gps : g,
    );
  }

  /// Ket thuc chuyen: chot cuoc (lam tron theo config) va ghi so cai.
  Future<void> stopTrip() async {
    final ActiveTripSession? ses = _session;
    if (ses == null || state.phase == TripPhase.saving) return;
    state = state.copyWith(phase: TripPhase.saving);
    _cancelAll();
    await ref.read(screenAwakeProvider).disable();
    try {
      final int now = _now();
      await _store.saveProgress(session: ses, fromSeq: _flushedSeq, nowMs: now);
      await _store.finishTrip(session: ses, endedAtMs: now, nowMs: now);
      final FareResult fin = ses.finalFare();
      _session = null;
      _flushedSeq = 0;
      state = TripUiState(finished: fin);
    } catch (e) {
      _session = null;
      state = TripUiState(error: 'Không lưu được chuyến: $e');
    }
  }

  void dismissFinished() => state = state.copyWith(clearFinished: true);
  void dismissError() => state = state.copyWith(clearError: true);

  void _cancelAll() {
    _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }
}

final NotifierProvider<TripController, TripUiState> tripControllerProvider =
    NotifierProvider<TripController, TripUiState>(TripController.new);

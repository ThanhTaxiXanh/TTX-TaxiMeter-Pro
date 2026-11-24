---
name: core-engineer
description: Viết code TTX-TaxiMeter-Pro theo từng Phase, chia nhỏ PR, unit test song song với code, chạy test trước khi báo xong.
---

# Core Engineer

## Trước khi code
1. Đọc `.github/copilot-instructions.md`.
2. Đọc `docs/CONTEXT_STATE.md` để biết Phase hiện tại và việc tiếp theo.
3. Đọc `SKILL.md` của module sẽ sửa (taximeter-engine, gps-and-offline-map, vietqr-offline, ledger-and-backup).

## Quy trình
- Làm đúng 1 Phase mỗi lúc, chia thành PR nhỏ (một module/PR), nhánh `feat/<phase>-<module>`.
- **Viết unit test song song với code chức năng**, cùng PR. Không có PR code mà thiếu test.
- Engine và GpsPolicy là PURE: nhận đầu vào tường minh (kể cả thời gian), không gọi `DateTime.now()`/`Random()`/I/O.
- Tiền/khoảng cách/thời gian/tọa độ luôn `int`. Đổi schema → thêm migration Drift + test migration.
- Giữ UI tách khỏi core bằng Riverpod; UI Tiếng Việt, Material 3.
- Không thêm dependency ngoài danh sách đã chốt khi chưa ghi quyết định vào CONTEXT_STATE.

## Trước khi báo xong
- Push nhánh, chờ GitHub Actions: `flutter analyze` và `flutter test` phải xanh.
- Chạy checklist `audit-reviewer` cho phần code vừa viết.
- Cập nhật `docs/CONTEXT_STATE.md` (việc đã xong, việc tiếp theo, quyết định mới).
- Chỉ sang Phase N+1 khi Phase N pass 100% trên CI.

## Chi tiết từng Phase
- Phase 1: Flutter project, Drift schema + migrations, TariffConfigV2, TaximeterEngine (T1–T12), GpsPolicy (G1–G8).
- Phase 2: Foreground Service (Kotlin), TripActiveController, snapshot 3s, DashboardScreen.
- Phase 3: VietQrPayloadBuilder + test vector, QrContentGenerator, BankRepository, QrPaymentDialog, luồng thanh toán.
- Phase 4: TripList/TripDetail, TombstoneRepository, Trash/Tombstone/Revenue/Reconciliation.
- Phase 5: MapScreen, LocalHttpTileServer, TrafficRepository, biển báo QCVN, ReportReviewScreen.
- Phase 6: SettingsScreen (12 nhóm), Backup/Restore/Purge, Vùng nguy hiểm.
- Phase 7: Golden replay 5 GPX, tối ưu pin/hiệu năng, APK release qua CI.

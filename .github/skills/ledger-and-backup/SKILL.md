---
name: ledger-and-backup
description: Sổ cái bất biến (trip_adjustment, tombstone), active_trip_snapshot, backup/restore ZIP có SHA256, purge theo hạn lưu.
---

# Skill: ledger-and-backup

## Sổ cái bất biến
- Không `UPDATE trip_record SET fare_total_vnd` hay bất kỳ `fare_*_vnd`. Muốn đổi tiền → insert `trip_adjustment (trip_id, amount_vnd, reason, created_at)`. Tổng thu = `fare_total_vnd` + Σ adjustment.
- Sửa trường không phải tiền (ghi chú...) → ghi `trip_edit_log` (field, old, new), tăng `edit_count`, đặt `edited_at`.
- Mỗi chuyến lưu `config_id`, `config_version`, `config_sha256`, `fare_hash`, `raw_points_hash`.

## Vòng đời chuyến
1. Xóa mềm: `archived=1`, `archived_at`, `archive_reason` → Thùng rác 30 ngày (có thể khôi phục).
2. Xóa vĩnh viễn: trong **cùng 1 SQLite transaction**: (a) insert `trip_tombstone` sao chép đủ số liệu tiền, payment, hash, bank, ghi chú; (b) xóa `raw_gps_points`, `trip_payment`, `trip_adjustment`...; (c) `DELETE FROM trip_record`. Lỗi bất kỳ → rollback toàn bộ.
3. Tombstone giữ vĩnh viễn mặc định; chỉ cập nhật `reconciled`, `reconciled_at`, `reconciliation_note`, `restored_at`.
4. Purge: raw GPS quá hạn bị xóa nhưng giữ `raw_points_hash` và `raw_trace_meta.purged_at`; thùng rác quá 30 ngày → xuất CSV trước khi xóa.

## active_trip_snapshot (crash-safe)
- Bảng 1 dòng (`id = 1`). Khi có chuyến active, ghi `state_json` mỗi 3 giây (upsert), cùng `trip_id`, `started_at`, `config_id/version/sha256`.
- Mở app: nếu có snapshot → khôi phục chuyến (engine state + điểm GPS đã lưu), tiếp tục; kết thúc chuyến → xóa snapshot trong cùng transaction lưu `trip_record`.
- `state_json` chỉ chứa số nguyên/chuỗi; test serialize/deserialize round-trip khớp byte.

## Backup (`backup_service.dart`)
ZIP gồm: `database.db`, `preferences.json` (KHÔNG chứa số TK ngân hàng), `manifest.json` (phiên bản app, schema, thời điểm), `checksums.sha256` (SHA256 từng file).

## Restore (`restore_service.dart`)
1. Verify checksum từng file. Sai → dừng.
2. Tự backup bản hiện tại.
3. Restore trong transaction; lỗi → rollback, giữ nguyên dữ liệu cũ.
4. Kiểm tra schema version; migration nếu cần.

## Purge (`purge_service.dart`) & Vùng nguy hiểm
- Xóa dữ liệu phải gõ đúng `XOA`. Không bao giờ xóa tombstone nếu người dùng chưa xác nhận riêng.

## Test bắt buộc
- Xóa vĩnh viễn: tombstone có đủ dữ liệu; lỗi giữa chừng → không mất chuyến.
- Không có đường nào UPDATE fare trực tiếp (test repository + audit).
- Snapshot round-trip và khôi phục.
- Backup → restore khớp checksum; file bị sửa 1 byte → restore bị từ chối.
- Backup không chứa số TK.

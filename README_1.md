# PoKalkulatorP2P
Flutter 3.35 / Dart 3.9 / Android+iOS / Material 3 kertas nota

## Jalankan
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run --flavor dev

## Struktur
lib/features/po, customer, calculator/po_calculator.dart, core/

## Alur
Home -> PO Baru -> ketik "2x semen 50kg 50rb" -> hitungPO() -> Kirim (PDF+WA) -> status Dikirim

Offline-first: Hive + SecureStorage + SharedPreferences. Tanpa login, deep link /po/:id.

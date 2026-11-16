import 'package:freezed_annotation/freezed_annotation.dart';
part 'po_models.freezed.dart';
part 'po_models.g.dart';

@freezed
class Customer with _$Customer {
  const factory Customer({
    required String id,
    required String namaOrang,
    required String nomorWA,
    @Default('') String alamat,
  }) = _Customer;
  factory Customer.fromJson(Map<String, dynamic> j) => _$CustomerFromJson(j);
}

@freezed
class PoItem with _$PoItem {
  const factory PoItem({
    required String namaBarang,
    @Default(1) int qty,
    @Default(0) int hargaSatuan,
    @Default(0) int diskonItem,
    @Default('') String kodeBarang,
    @Default('') String variasi,
    @Default('pcs') String satuan,
  }) = _PoItem;
  factory PoItem.fromJson(Map<String, dynamic> j) => _$PoItemFromJson(j);
}

enum PoStatus { draft, dikirim, dikonfirmasi, lunas, batal }

@freezed
class PoOrder with _$PoOrder {
  const factory PoOrder({
    required String id,
    required Customer customer,
    @Default([]) List<PoItem> items,
    required DateTime tanggal,
    @Default(0) int ongkir,
    @Default(0) int diskonTotal,
    @Default(0) int dp,
    @Default(PoStatus.draft) PoStatus status,
    @Default('') String catatan,
  }) = _PoOrder;
  factory PoOrder.fromJson(Map<String, dynamic> j) => _$PoOrderFromJson(j);
}

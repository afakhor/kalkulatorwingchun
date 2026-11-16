// JANTUNG - TIDAK BOLEH ADA DI UI. Harus di po_calculator.dart
import '../po/po_models.dart';

class HasilHitung {
  final int subtotal, totalAkhir, sisaBayar;
  const HasilHitung(this.subtotal, this.totalAkhir, this.sisaBayar);
}

HasilHitung hitungPO(PoOrder po) {
  final subtotal = po.items.fold<int>(0, (a, i) => a + (i.qty * i.hargaSatuan - i.diskonItem));
  final totalSetelahDiskon = subtotal - po.diskonTotal;
  var totalAkhir = totalSetelahDiskon + po.ongkir;
  totalAkhir = ((totalAkhir + 250) ~/ 500) * 500; // bulatkan ke 500 terdekat
  return HasilHitung(subtotal, totalAkhir, totalAkhir - po.dp);
}

import 'po_models.dart';
import '../../core/formatter.dart';

// "2x kaos 50rb" -> PoItem(qty=2, nama=kaos, harga=50000)
// "2x semen 50kg 50rb" -> nama="semen 50kg"
PoItem? parseInputCepat(String raw) {
  final r = RegExp(r'^(\d+)\s*x\s*(.+?)\s+(\d+[.,\d]*\s*(?:rb|k|jt|ribu)?)$', caseSensitive: false);
  final m = r.firstMatch(raw.trim());
  if (m == null) return null;
  return PoItem(
    qty: int.parse(m.group(1)!),
    namaBarang: m.group(2)!.trim(),
    hargaSatuan: parseHarga(m.group(3)!),
  );
}

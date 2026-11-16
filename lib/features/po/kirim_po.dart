import 'package:flutter/foundation.dart';
import 'po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

// Template: Chat / Nota / Kalkulator - hanya ubah tampilan, jangan ubah data
String teksWA(PoOrder po, int total) =>
    'Halo ${po.customer.namaOrang}, ini PO-nya, total ${formatRupiah(total)}';

Future<void> kirimPO(PoOrder po) async {
  final total = hitungPO(po).totalAkhir;
  debugPrint('buatPDF Nota: ${po.id} total $total');
  debugPrint('share_plus + url_launcher: ${teksWA(po, total)}');
  // setelah kirim -> status = Dikirim, simpan ke Hive
}

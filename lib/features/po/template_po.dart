import 'po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

enum TemplatePO { chat, nota, kalkulator }

// TEMPLATE = ganti tampilan saja, JANGAN ubah data PoOrder
// Chat -> ringkas untuk WA, Nota -> rapi untuk PDF, Kalkulator -> hanya angka
String renderTemplate(TemplatePO t, PoOrder po) {
  final h = hitungPO(po);
  switch (t) {
    case TemplatePO.chat:
      return 'Halo ${po.customer.namaOrang}, ini PO-nya, total ${formatRupiah(h.totalAkhir)}';
    case TemplatePO.nota:
      return 'NOTA ${po.id}\n${po.customer.namaOrang}\nTotal: ${formatRupiah(h.totalAkhir)}\nSisa: ${formatRupiah(h.sisaBayar)}';
    case TemplatePO.kalkulator:
      return '${formatRupiah(h.subtotal)} -> ${formatRupiah(h.totalAkhir)}';
  }
}

String gantiTemplate(TemplatePO baru) => 'Template diubah ke: ${baru.name}';

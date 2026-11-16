import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

// buatPDF template Nota - rapi untuk PDF, data dari PoOrder asli, tanpa dummy
Future<File> buatPDFNota(PoOrder po, Directory dir, {String namaToko = 'TOKO BANGUNAN'}) async {
  final h = hitungPO(po);
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    build: (c) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(namaToko, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text('${po.id} - ${formatTanggal(po.tanggal)}'),
        pw.Text('Customer: ${po.customer.namaOrang} - ${po.customer.nomorWA}'),
        pw.Divider(),
        ...po.items.map((i) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text('${i.namaBarang} ${i.qty}x'), pw.Text(formatRupiah(i.qty * i.hargaSatuan - i.diskonItem))],
            )),
        pw.Divider(),
        pw.Text('Diskon: ${formatRupiah(po.diskonTotal)}'),
        pw.Text('Ongkir: ${formatRupiah(po.ongkir)}'),
        pw.Text('TOTAL: ${formatRupiah(h.totalAkhir)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text('DP: ${formatRupiah(po.dp)}'),
        pw.Text('Sisa Bayar: ${formatRupiah(h.sisaBayar)}'),
        pw.SizedBox(height: 12),
        pw.Text('Catatan: ${po.catatan}'),
        pw.Text('Status: ${po.status.name}'),
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('Terima kasih')),
      ],
    ),
  ));
  final f = File('${dir.path}/${po.id}.pdf');
  await f.writeAsBytes(await pdf.save());
  return f;
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

// PDF FAKTUR - layout SAMA PERSIS dengan NotaPreview
// Batch & ED + Disc HAPUS. Harga = Harga ACUAN (Harga Satuan x Unit). No. Telp = No. WA.
Future<File> buatPDFNota(PoOrder po, Directory dir, {String namaToko = 'BASKORO WINGCHUN'}) async {
  final h = hitungPO(po);
  final pdf = pw.Document();
  final telp = po.customer.nomorWA.trim();
  pdf.addPage(pw.Page(
    build: (c) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(namaToko, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.Text('BABE INFO', style: const pw.TextStyle(fontSize: 12)),
          ]),
          pw.Text('FAKTUR', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 12),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Nama Pelanggan : ${po.customer.namaOrang}'),
            if (telp.isNotEmpty) pw.Text('No. Telp : $telp'),
          ])),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Tanggal : ${formatTanggal(po.tanggal)}'),
            pw.Text('No. Faktur : ${po.id}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ]),
        ]),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          columnWidths: {0: const pw.FixedColumnWidth(32), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(44), 3: const pw.FixedColumnWidth(64), 4: const pw.FixedColumnWidth(110), 5: const pw.FixedColumnWidth(120)},
          children: [
            pw.TableRow(children: [
              for (final t in ['No', 'Nama Barang', 'Qty', 'Satuan', 'Harga', 'Subtotal'])
                pw.Container(padding: pw.EdgeInsets.all(6), color: PdfColors.grey200, child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
            ]),
            ...List.generate(po.items.length, (idx) {
              final i = po.items[idx];
              final sub = i.qty * i.hargaSatuan - i.diskonItem;
              return pw.TableRow(children: [
                pw.Container(padding: pw.EdgeInsets.all(6), child: pw.Text('${idx + 1}', textAlign: pw.TextAlign.center)),
                pw.Container(padding: pw.EdgeInsets.all(6), child: pw.Text(i.namaBarang)),
                pw.Container(padding: pw.EdgeInsets.all(6), child: pw.Text(formatHasil(i.qty.toDouble()), textAlign: pw.TextAlign.center)),
                pw.Container(padding: pw.EdgeInsets.all(6), child: pw.Text('')),
                pw.Container(padding: pw.EdgeInsets.all(6), alignment: pw.Alignment.centerRight, child: pw.Text(formatRupiah(i.hargaSatuan.toInt()))),
                pw.Container(padding: pw.EdgeInsets.all(6), alignment: pw.Alignment.centerRight, child: pw.Text(formatRupiah(sub.toInt()))),
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Catatan :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(po.catatan.isEmpty ? 'Terima kasih. Telah berkurang, semoga sehat selalu.' : po.catatan),
            pw.SizedBox(height: 16),
            pw.Text('Penerima / Pembeli'),
          ])),
          pw.SizedBox(width: 12),
          pw.SizedBox(width: 220, child: pw.Column(children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total'), pw.Text(formatRupiah((h.totalAkhir + po.diskonTotal - po.ongkir).toInt()))]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Diskon'), pw.Text(formatRupiah(po.diskonTotal.toInt()))]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Pajak'), pw.Text(formatRupiah(0))]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Grand Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(formatRupiah(h.totalAkhir.toInt()), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('DP'), pw.Text(formatRupiah(po.dp.toInt()))]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Sisa Bayar'), pw.Text(formatRupiah(h.sisaBayar.toInt()))]),
          ])),
        ]),
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('Terima kasih')),
      ],
    ),
  ));
  final f = File('${dir.path}/${po.id}.pdf');
  await f.writeAsBytes(await pdf.save());
  return f;
}

// FIX SHARE WA PDF: buat file di getTemporaryDirectory, pakai Share.shareXFiles
// Jangan pakai path_provider getApplicationDocumentsDirectory yang kadang WA tidak bisa baca,
// dan jangan pakai Share.share (teks) untuk PDF.
Future<void> shareNotaPdf(PoOrder po, {String namaToko = 'BASKORO WINGCHUN'}) async {
  final dir = await getTemporaryDirectory();
  final file = await buatPDFNota(po, dir, namaToko: namaToko);
  // Pastikan file benar-benar ada sebelum share
  if (!await file.exists()) throw Exception('PDF gagal dibuat');
  await Share.shareXFiles(
    [XFile(file.path, name: '${po.id}.pdf', mimeType: 'application/pdf')],
    text: 'FAKTUR ${po.id} - ${po.customer.namaOrang}\nGrand Total: ${formatRupiah(hitungPO(po).totalAkhir.toInt())}',
    subject: 'FAKTUR ${po.id}',
  );
}

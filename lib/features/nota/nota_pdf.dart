import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/formatter.dart';
import '../calculator/po_calculator.dart';
import '../po/po_models.dart';

const Map<String, List<String>> _gly = {
  '0': [
    '01110',
    '10001',
    '10011',
    '10101',
    '11001',
    '10001',
    '01110',
  ],
  '1': [
    '00100',
    '01100',
    '00100',
    '00100',
    '00100',
    '00100',
    '01110',
  ],
  '2': [
    '01110',
    '10001',
    '00001',
    '00110',
    '01000',
    '10000',
    '11111',
  ],
  '3': [
    '11110',
    '00001',
    '00001',
    '01110',
    '00001',
    '00001',
    '11110',
  ],
  '4': [
    '00010',
    '00110',
    '01010',
    '10010',
    '11111',
    '00010',
    '00010',
  ],
  '5': [
    '11111',
    '10000',
    '11110',
    '00001',
    '00001',
    '10001',
    '01110',
  ],
  '6': [
    '01110',
    '10000',
    '11110',
    '10001',
    '10001',
    '10001',
    '01110',
  ],
  '7': [
    '11111',
    '00001',
    '00010',
    '00100',
    '01000',
    '01000',
    '01000',
  ],
  '8': [
    '01110',
    '10001',
    '10001',
    '01110',
    '10001',
    '10001',
    '01110',
  ],
  '9': [
    '01110',
    '10001',
    '10001',
    '01111',
    '00001',
    '00001',
    '01110',
  ],
  '`': ['00100', '01000', '00000', '00000', '00000', '00000', '00000'],
  '.': ['00000', '00000', '00000', '00000', '00000', '01100', '01100'],
  ',': ['00000', '00000', '00000', '00000', '00000', '01100', '01000'],
  '-': ['00000', '00000', '00000', '11111', '00000', '00000', '00000'],
  ' ': ['000', '000', '000', '000', '000', '000', '000'],
};

pw.Widget _dotGlyph(String ch, double pitch, double r, PdfColor c) {
  final rows = _gly[ch] ?? _gly[' ']!;
  final cols = rows[0].length;
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      for (final row in rows)
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (var k = 0; k < cols; k++)
              pw.SizedBox(
                width: pitch,
                height: pitch,
                child: row[k] == '1'
                    ? pw.Center(
                        child: pw.Container(
                          width: r * 2,
                          height: r * 2,
                          decoration: pw.BoxDecoration(
                              shape: pw.BoxShape.circle, color: c),
                        ),
                      )
                    : pw.SizedBox(),
              ),
          ],
        ),
    ],
  );
}

pw.Widget _dotLine(
    String teks, double pitch, double r, double gap, PdfColor c) {
  final list = teks.split('');
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      for (var i = 0; i < list.length; i++) ...[
        _dotGlyph(list[i], pitch, r, c),
        if (i < list.length - 1) pw.SizedBox(width: gap),
      ],
    ],
  );
}

pw.Widget _dotAngka(num v, {double maxW = 86, double pitch = 1.45}) {
  final teks = formatRupiah(v.round()).replaceAll('Rp ', '').trim();
  const rpW = 18.0;
  final w = (maxW - rpW).clamp(32.0, maxW);
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Text('Rp ', style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(
        width: w,
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          alignment: pw.Alignment.centerRight,
          child: _dotLine(teks, pitch, pitch * 0.44, 1.0, PdfColors.black),
        ),
      ),
    ],
  );
}

Future<Uint8List> buatPDFNota(PoOrder po,
    {String namaToko = 'BASKORO WINGCHUN'}) async {
  final doc = pw.Document();
  final h = hitungPO(po);
  final telp = po.customer.nomorWA.trim();
  final subtotal =
      po.items.fold<double>(0, (a, i) => a + i.qty * i.hargaSatuan);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (ctx) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(namaToko,
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('BABE INFO', style: const pw.TextStyle(fontSize: 10)),
                ]),
            pw.Text('FAKTUR',
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1)),
          ]),
      pw.SizedBox(height: 10),
      pw.Text('Nama Pelanggan : ${po.customer.namaOrang}',
          style: const pw.TextStyle(fontSize: 11)),
      if (telp.isNotEmpty)
        pw.Text('No. Telp : $telp', style: const pw.TextStyle(fontSize: 11)),
      pw.Text('Tanggal : ${formatTanggal(po.tanggal)}',
          style: const pw.TextStyle(fontSize: 11)),
      pw.Text('No. Faktur : ${po.id}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(width: 0.8),
        columnWidths: {
          0: const pw.FixedColumnWidth(26),
          1: const pw.FlexColumnWidth(),
          2: const pw.FixedColumnWidth(34),
          3: const pw.FixedColumnWidth(46),
          4: const pw.FixedColumnWidth(78),
          5: const pw.FixedColumnWidth(84),
        },
        children: [
          pw.TableRow(children: [
            for (final t in [
              'No',
              'Nama Barang',
              'Qty',
              'Satuan',
              'Harga',
              'Subtotal'
            ])
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                color: PdfColors.grey200,
                child: pw.Text(
                  t,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 9),
                  textAlign: t == 'Nama Barang'
                      ? pw.TextAlign.left
                      : pw.TextAlign.center,
                ),
              ),
          ]),
          ...List.generate(po.items.length, (idx) {
            final i = po.items[idx];
            final sub = i.qty * i.hargaSatuan - i.diskonItem;
            return pw.TableRow(children: [
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: pw.Text('${idx + 1}',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: pw.Text(i.namaBarang,
                    style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: pw.Text(formatHasil(i.qty.toDouble()),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: pw.Text(i.satuan,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                alignment: pw.Alignment.centerRight,
                child: _dotAngka(i.hargaSatuan, maxW: 72),
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                alignment: pw.Alignment.centerRight,
                child: _dotAngka(sub, maxW: 78),
              ),
            ]);
          }),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Catatan :',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(po.catatan.isEmpty ? '-' : po.catatan,
                    style: const pw.TextStyle(fontSize: 11)),
              ]),
        ),
        pw.SizedBox(width: 12),
        pw.SizedBox(
          width: 210,
          child: pw.Column(children: [
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sub Total', style: const pw.TextStyle(fontSize: 11)),
                  _dotAngka(subtotal, maxW: 110),
                ]),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Diskon', style: const pw.TextStyle(fontSize: 11)),
                  _dotAngka(po.diskonTotal, maxW: 110),
                ]),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Biaya Kirim',
                      style: const pw.TextStyle(fontSize: 11)),
                  _dotAngka(po.ongkir, maxW: 110),
                ]),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  _dotAngka(h.totalAkhir, maxW: 110),
                ]),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DP', style: const pw.TextStyle(fontSize: 11)),
                  _dotAngka(po.dp, maxW: 110),
                ]),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sisa Bayar',
                      style: const pw.TextStyle(fontSize: 11)),
                  _dotAngka(h.sisaBayar, maxW: 110),
                ]),
          ]),
        ),
      ]),
      pw.SizedBox(height: 18),
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(children: [
              pw.Text('Penerima,', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 36),
              pw.Text('( ..................... )',
                  style: const pw.TextStyle(fontSize: 11)),
            ]),
            pw.Column(children: [
              pw.Text('Hormat Kami,', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 36),
              pw.Text('( $namaToko )',
                  style: const pw.TextStyle(fontSize: 11)),
            ]),
          ]),
    ]),
  ));
  return doc.save();
}

Future<void> shareNotaPdf(PoOrder po,
    {String namaToko = 'BASKORO WINGCHUN'}) async {
  final bytes = await buatPDFNota(po, namaToko: namaToko);
  await Printing.sharePdf(bytes: bytes, filename: 'nota_${po.id}.pdf');
}

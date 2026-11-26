import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

// PDF FAKTUR - layout SAMA dengan NotaPreview RAPI + angka DOT-MATRIX.
// PDF tidak bisa pakai CustomPainter Flutter, jadi dot-matrix digambar manual:
// tiap karakter = grid 5 kolom x 7 baris titik (lingkaran kecil). Hasilnya mirip DotMatrixText di layar,
// tapi tetap kebaca & muat di kolom (titik 1.1pt, bukan font 12 yang meluber).

// Pola dot-matrix 5x7 untuk karakter yang dipakai di angka: 0-9, ` , . - dan spasi.
// Tiap string = 7 baris, tiap baris 5 karakter, '#' = titik nyala, '.' = mati.
const Map<String, List<String>> _dotPola = {
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['.###.', '#....', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '..#..', '..#..', '..#..'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '....#', '.###.'],
  '`': ['.#...', '.#...', '..#..', '.....', '.....', '.....', '.....'],
  ',': ['.....', '.....', '.....', '.....', '.##..', '.##..', '.#...'],
  '.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
  '-': ['.....', '.....', '.....', '.###.', '.....', '.....', '.....'],
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
};

// Satu karakter dot-matrix: kolom titik, ukuran titik bisa diatur (kecil = muat kolom).
pw.Widget _dotChar(String ch, {double dot = 1.1, double gap = 0.35}) {
  final pola = _dotPola[ch] ?? _dotPola[' ']!;
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: List.generate(7, (r) {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: List.generate(5, (c) {
          final nyala = pola[r][c] == '#';
          return pw.Container(
            width: dot, height: dot, margin: pw.EdgeInsets.all(gap / 2),
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: nyala ? PdfColors.black : PdfColors.white,
            ),
          );
        }),
      );
    }),
  );
}

// Satu angka dot-matrix ADAPTIF: "Rp " kecil + karakter dot, total TIDAK PERNAH melebihi maxW (kolom).
// Dulu dot = 1.1 TETAP untuk semua panjang angka. Contoh 18`000`000 (10 karakter):
// 10 x 5 x (1.1 + 0.35) + 9 x 1.2 + 'Rp ' = ±98, kolom Harga cuma 74 -> meluber.
// Sekarang dot dihitung mundur dari maxW:
//   dot = (maxW - lebar 'Rp ' - jarak antar karakter) / (jumlah karakter x 5) - gap
// Makin panjang angkanya, makin kecil titiknya, tapi susunan 5x7 tetap rapi dan tidak meluber.
// maxDot = batas atas (angka pendek tetap pakai titik normal, tidak membesar).
pw.Widget _dotAngka(num v, {double maxW = 74, double maxDot = 1.1}) {
  final teks = formatRupiah(v.toInt()).replaceAll('Rp ', '').trim();
  const rpW = 15.0; // 'Rp ' font 8 + SizedBox 2
  const antarChar = 1.2;
  const gap = 0.35; // harus sama dengan gap default _dotChar
  final n = teks.isEmpty ? 1 : teks.length;
  var dot = (maxW - rpW - (n - 1) * antarChar) / (n * 5) - gap;
  if (dot > maxDot) dot = maxDot;
  if (dot < 0.45) dot = 0.45; // lantai: di bawah ini titik tidak kebaca lagi
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Text('Rp ', style: const pw.TextStyle(fontSize: 8)),
      pw.SizedBox(width: 2),
      pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        for (int k = 0; k < teks.length; k++) ...[
          _dotChar(teks[k], dot: dot),
          if (k != teks.length - 1) pw.SizedBox(width: antarChar),
        ],
      ]),
    ],
  );
}

Future<File> buatPDFNota(PoOrder po, Directory dir, {String namaToko = 'BASKORO WINGCHUN'}) async {
  final h = hitungPO(po);
  final pdf = pw.Document();
  final telp = po.customer.nomorWA.trim();
  final subtotal = po.items.fold<double>(0, (a, i) => a + i.qty * i.hargaSatuan);
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (c) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(namaToko, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('BABE INFO', style: const pw.TextStyle(fontSize: 10)),
          ])),
          pw.SizedBox(width: 8),
          pw.Text('FAKTUR', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 8),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Nama Pelanggan : ${po.customer.namaOrang}', style: const pw.TextStyle(fontSize: 10)),
          if (telp.isNotEmpty) pw.Text('No. Telp : $telp', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Tanggal : ${formatTanggal(po.tanggal)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('No. Faktur : ${po.id}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          columnWidths: {0: const pw.FixedColumnWidth(26), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(36), 3: const pw.FixedColumnWidth(40), 4: const pw.FixedColumnWidth(80), 5: const pw.FixedColumnWidth(86)},
          children: [
            pw.TableRow(children: [
              for (final t in ['No', 'Nama Barang', 'Qty', 'Satuan', 'Harga', 'Subtotal'])
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4), color: PdfColors.grey200, child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: t == 'Nama Barang' ? pw.TextAlign.left : pw.TextAlign.center)),
            ]),
            ...List.generate(po.items.length, (idx) {
              final i = po.items[idx];
              final sub = i.qty * i.hargaSatuan - i.diskonItem;
              return pw.TableRow(children: [
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: pw.Text('${idx + 1}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9))),
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: pw.Text(i.namaBarang, style: const pw.TextStyle(fontSize: 9))),
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: pw.Text(formatHasil(i.qty.toDouble()), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9))),
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: pw.Text('', textAlign: pw.TextAlign.center)),
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4), alignment: pw.Alignment.centerRight, child: _dotAngka(i.hargaSatuan, maxW: 74)), // kolom Harga 80 - padding 6
                pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4), alignment: pw.Alignment.centerRight, child: _dotAngka(sub, maxW: 80)), // kolom Subtotal 86 - padding 6
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Catatan :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(po.catatan.isEmpty ? 'Terima kasih. Telah berkurang, semoga sehat selalu.' : po.catatan, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 12),
            pw.Text('Penerima / Pembeli', style: const pw.TextStyle(fontSize: 10)),
          ])),
          pw.SizedBox(width: 8),
          pw.SizedBox(width: 170, child: pw.Column(children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total', style: const pw.TextStyle(fontSize: 10)), _dotAngka(subtotal, maxW: 95)]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Diskon', style: const pw.TextStyle(fontSize: 10)), _dotAngka(po.diskonTotal, maxW: 95)]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Ongkos', style: const pw.TextStyle(fontSize: 10)), _dotAngka(po.ongkir, maxW: 95)]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Grand Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)), _dotAngka(h.totalAkhir, maxW: 95, maxDot: 1.25)]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('DP', style: const pw.TextStyle(fontSize: 10)), _dotAngka(po.dp, maxW: 95)]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Sisa Bayar', style: const pw.TextStyle(fontSize: 10)), _dotAngka(h.sisaBayar, maxW: 95)]),
          ])),
        ]),
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text('Terima kasih', style: const pw.TextStyle(fontSize: 10))),
      ],
    ),
  ));
  final f = File('${dir.path}/${po.id}.pdf');
  await f.writeAsBytes(await pdf.save());
  return f;
}

Future<void> shareNotaPdf(PoOrder po, {String namaToko = 'BASKORO WINGCHUN'}) async {
  final dir = await getTemporaryDirectory();
  final file = await buatPDFNota(po, dir, namaToko: namaToko);
  if (!await file.exists()) throw Exception('PDF gagal dibuat');
  await Share.shareXFiles(
    [XFile(file.path, name: '${po.id}.pdf', mimeType: 'application/pdf')],
    text: 'FAKTUR ${po.id} - ${po.customer.namaOrang}\nGrand Total: ${formatRupiah(hitungPO(po).totalAkhir.toInt())}',
    subject: 'FAKTUR ${po.id}',
  );
}

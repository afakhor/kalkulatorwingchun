import 'package:flutter/material.dart';

// ============================================================
// formatter.dart - FINAL MERGED
// 1. Grouping ribuan backtick ` : 1`000`000, 20`000, 83`333
//    FIX grouping dari kanan, bukan kiri. 1`000`000 bukan 1000`000
// 2. DOT-MATRIX DISPLAY persis foto Casio DJ-120
//    Atas: titik-titik kecil (dot-matrix 5x7)
//    Bawah: garis putus-putus (segmen LCD putus-putus)
//    Pakai CustomPainter, bukan Text - font biasa tidak bisa dot-matrix
// 3. Tanggal manual tanpa intl - preview nota putih, tidak abu-abu
// Lolos flutter analyze: 0 issue
// ============================================================

String stripBacktick(String s) =>
    s.replaceAll('`', '').replaceAll('Rp', '').replaceAll('rp', '').replaceAll(' ', '').replaceAll(',', '').trim();

String _groupBacktick(String s) {
  if (s == 'E' || s.isEmpty) return s;
  var neg = false;
  if (s.startsWith('-')) {
    neg = true;
    s = s.substring(1);
  }
  var dotParts = s.split('.');
  var integer = dotParts[0].replaceAll(RegExp(r'[^0-9]'), '');
  if (integer.isEmpty) integer = '0';
  var rev = integer.split('').reversed.toList();
  var grouped = <String>[];
  for (var i = 0; i < rev.length; i++) {
    if (i > 0 && i % 3 == 0) grouped.add('`');
    grouped.add(rev[i]);
  }
  var hasil = grouped.reversed.join('');
  if (dotParts.length > 1 && dotParts[1].isNotEmpty) {
    // FIX analyze: ${hasil} -> $hasil, biar tidak unnecessary_brace_in_string_interps
    hasil = '$hasil.${dotParts[1]}';
  }
  return neg ? '-$hasil' : hasil;
}

String formatRupiah(num v) {
  if (v == 0) return 'Rp 0';
  var neg = v < 0;
  var absStr = v.abs().toInt().toString();
  var grouped = _groupBacktick(absStr);
  return neg ? 'Rp -$grouped' : 'Rp $grouped';
}

String formatHasil(double v) {
  if (v.isNaN || v.isInfinite) return 'E';
  var s = v.toStringAsFixed(0);
  return _groupBacktick(s);
}

// Tanggal manual tanpa intl - biar preview nota tidak abu-abu
const _namaBulanId = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const _namaHariId = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

String formatTanggal(DateTime d) {
  return '${d.day} ${_namaBulanId[d.month - 1]} ${d.year}';
}

String formatTanggalLengkap(DateTime d) {
  return '${_namaHariId[d.weekday - 1]}, ${d.day} ${_namaBulanId[d.month - 1]} ${d.year}';
}

int parseHarga(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll('rp', '').replaceAll('`', '').replaceAll(' ', '').trim();
  if (t.isEmpty) return 0;
  var neg = false;
  if (t.startsWith('-')) {
    neg = true;
    t = t.substring(1);
  }
  double pengali = 1;
  if (t.endsWith('rb') || t.endsWith('k')) {
    pengali = 1000;
    t = t.replaceAll('rb', '').replaceAll('k', '');
  } else if (t.endsWith('jt')) {
    pengali = 1000000;
    t = t.replaceAll('jt', '');
  }
  t = t.replaceAll(',', '.');
  var parts = t.split('.');
  double nilai;
  if (parts.length > 2) {
    t = t.replaceAll('.', '');
    nilai = double.tryParse(t) ?? 0;
  } else if (parts.length == 2 && pengali == 1) {
    if (parts[1].length == 3) {
      t = parts[0] + parts[1];
      nilai = double.tryParse(t) ?? 0;
    } else {
      nilai = double.tryParse(t) ?? 0;
    }
  } else {
    nilai = double.tryParse(t) ?? 0;
  }
  var hasil = (nilai * pengali).round();
  return neg ? -hasil : hasil;
}

// ============================================================
// DOT-MATRIX DISPLAY - MERGED KE SINI
// Cara pakai di home_daftar_po.dart:
//   DotMatrixText(text: "123456789012.", size: DotMatrixSize.small)
//   DotMatrixText(text: "1.23456789 12", size: DotMatrixSize.large)
// ============================================================

enum DotMatrixSize { small, large }

class DotMatrixText extends StatelessWidget {
  final String text;
  final DotMatrixSize size;
  final Color color;
  final TextAlign align;
  const DotMatrixText({super.key, required this.text, this.size = DotMatrixSize.large, this.color = Colors.black, this.align = TextAlign.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
      return CustomPaint(
        size: Size(maxW, size == DotMatrixSize.small ? 22 : 44),
        painter: _DotMatrixPainter(text: text, isSmall: size == DotMatrixSize.small, color: color, align: align),
      );
    });
  }
}

// Pola 5 kolom x 7 baris untuk tiap karakter. 1 = titik nyala, 0 = mati
const Map<String, List<String>> _dotMap = {
  '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  '3': ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
  '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
  '.': ['00000', '00000', '00000', '00000', '00000', '00000', '01100'],
  ',': ['00000', '00000', '00000', '00000', '00000', '01100', '01000'],
  '-': ['00000', '00000', '00000', '01110', '00000', '00000', '00000'],
  '`': ['01000', '01000', '00100', '00000', '00000', '00000', '00000'],
  ' ': ['00000', '00000', '00000', '00000', '00000', '00000', '00000'],
  'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
  '+': ['00000', '00100', '00100', '11111', '00100', '00100', '00000'],
  'x': ['00000', '10001', '01010', '00100', '01010', '10001', '00000'],
  '/': ['00001', '00010', '00010', '00100', '01000', '01000', '10000'],
  '=': ['00000', '00000', '11111', '00000', '11111', '00000', '00000'],
};

class _DotMatrixPainter extends CustomPainter {
  final String text;
  final bool isSmall;
  final Color color;
  final TextAlign align;
  _DotMatrixPainter({required this.text, required this.isSmall, required this.color, required this.align});

  @override
  void paint(Canvas canvas, Size size) {
    // Atas (small): titik bulat kecil, rapat -> kelihatan titik-titik kayak foto atas
    // Bawah (large): titik kotak memanjang + jarak -> kelihatan garis putus-putus kayak foto bawah
    final dotW = isSmall ? 2.2 : 4.2;
    final dotH = isSmall ? 2.2 : 4.2;
    final gapX = isSmall ? 1.1 : 1.6;
    final gapY = isSmall ? 1.1 : 1.6;
    final charW = 5 * (dotW + gapX);
    final charGap = isSmall ? 3.0 : 5.0;
    final totalW = text.length * (charW + charGap) - charGap;
    double startX = 0;
    if (align == TextAlign.right) startX = size.width - totalW;
    if (align == TextAlign.center) startX = (size.width - totalW) / 2;
    if (startX < 0) startX = 0;

    final paint = Paint()..color = color;
    for (var ci = 0; ci < text.length; ci++) {
      final ch = text[ci];
      final pattern = _dotMap[ch] ?? _dotMap[' ']!;
      final cx = startX + ci * (charW + charGap);
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          if (pattern[row][col] == '1') {
            final x = cx + col * (dotW + gapX);
            final y = row * (dotH + gapY);
            if (isSmall) {
              // ATAS: titik bulat kecil
              canvas.drawCircle(Offset(x + dotW / 2, y + dotH / 2), dotW / 2, paint);
            } else {
              // BAWAH: kotak putus-putus -> efek garis putus-putus LCD
              canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, dotW, dotH), const Radius.circular(1.2)), paint);
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotMatrixPainter old) => old.text != text || old.color != color || old.isSmall != isSmall;
}

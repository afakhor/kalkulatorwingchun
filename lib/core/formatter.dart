import 'dart:math';

// ============================================================
// formatter.dart — FIX LENGKAP
// Ribuan pakai backtick `: 1`000`000, 20`000, 83`333
// Sesuai gambar kalkulator 12 digit: 123456789012 / 123456789.12
// ============================================================

String stripBacktick(String s) =>
    s.replaceAll('`', '').replaceAll('Rp', '').replaceAll('rp', '').replaceAll(' ', '').replaceAll(',', '').trim();

String _groupBacktickFmt(String s) {
  if (s == "E" || s.isEmpty) return s;
  var neg = false;
  if (s.startsWith('-')) { neg = true; s = s.substring(1); }
  var parts = s.split('.');
  var integer = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
  if (integer.isEmpty) integer = "0";
  final rev = integer.split('').reversed.toList();
  final chunks = <String>[];
  for (var j = 0; j < rev.length; j += 3) {
    final end = (j + 3 < rev.length) ? j + 3 : rev.length;
    chunks.add(rev.sublist(j, end).join());
  }
  final groupedRev = chunks.join('`');
  var hasil = groupedRev.split('').reversed.join();
  if (parts.length > 1 && parts[1].isNotEmpty) hasil = "$hasil.${parts[1]}";
  return neg ? "-$hasil" : hasil;
}

String formatRupiah(int v) {
  if (v == 0) return "Rp 0";
  final absV = v.abs();
  final grouped = _groupBacktickFmt(absV.toString());
  final sign = v < 0 ? "-" : "";
  return "$sign" + "Rp $grouped";
}

String formatHasilSimple(double v) => _groupBacktickFmt(v.toStringAsFixed(0));

String formatTanggal(DateTime d) {
  const bulan = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
  return "${d.day} ${bulan[d.month-1]} ${d.year}";
}
String formatTanggalLengkap(DateTime d) {
  const bulan = ['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];
  const hari = ['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
  return "${hari[d.weekday-1]}, ${d.day} ${bulan[d.month-1]} ${d.year}";
}

const _namaBulanId = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];

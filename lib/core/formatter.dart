import 'package:intl/intl.dart';

// ============================================================
// formatter.dart — LENGKAP FIX
// 1 file untuk PO + SATUAN + NOTA + LAYAR KALKULATOR
// Semua pakai backtick ` sebagai pemisah ribuan:
// 1000 -> Rp 1`000 / 1`000
// 50000 -> Rp 50`000 / 50`000
// 25000 -> Rp 25`000 / 25`000
// ============================================================

// ---------- HELPER DASAR ----------

/// Buang `, Rp, spasi. WAJIB sebelum double.tryParse / int.tryParse.
/// Kalau tidak, double.tryParse("50`000") = null -> jadi 0.
String stripBacktick(String s) =>
    s.replaceAll('`', '').replaceAll('Rp', '').replaceAll('rp', '').replaceAll(' ', '').trim();

/// Grouping ribuan pakai backtick, desimal & minus tetap aman.
/// 50000 -> 50`000 | -1234567.89 -> -1`234`567.89 | 0. -> 0. | E -> E
String groupBacktick(String s) {
  if (s == 'E' || s.isEmpty) return s;
  // STRIP DULU — kalau s sudah "50`000", buang ` nya dulu jadi "50000".
  // Kalau tidak di-strip, grouping kedua akan geser jadi "50000`".
  s = stripBacktick(s);
  var neg = false;
  if (s.startsWith('-')) {
    neg = true;
    s = s.substring(1);
  }
  final parts = s.split('.');
  var integer = parts[0].isEmpty ? '0' : parts[0];
  // POTONG 3-3-3 DARI KANAN — tanpa reversed, tanpa StringBuffer dibalik.
  // 50000 -> ["50", "000"] -> "50`000"
  // 1000000 -> ["1", "000", "000"] -> "1`000`000"
  // 1000 -> ["1", "000"] -> "1`000"
  final groups = <String>[];
  while (integer.length > 3) {
    groups.insert(0, integer.substring(integer.length - 3));
    integer = integer.substring(0, integer.length - 3);
  }
  groups.insert(0, integer);
  var hasil = groups.join('`');
  if (parts.length > 1) hasil = '$hasil.${parts[1]}';
  return neg ? '-$hasil' : hasil;
}

/// Baca layar kalkulator yang sudah berisi ` -> angka.
/// parseLayar("50`000") = 50000.0, bukan 0.
double parseLayar(String s) => double.tryParse(stripBacktick(s)) ?? 0;

/// Sama kayak parseLayar, tapi int.
int parseLayarInt(String s) => int.tryParse(stripBacktick(s)) ?? 0;

// ---------- RUPIAH (PO / SATUAN / NOTA) ----------

/// Format Rupiah pakai backtick ` — VERSI ASLI KAMU, dipertahankan + diperkuat.
/// 1000 -> Rp 1`000
/// 50000 -> Rp 50`000
/// -25000 -> -Rp 25`000
/// 1234567.89 -> Rp 1`234`567 (desimal dibuang, karena Rupiah tidak pakai sen)
/// Kalau mau tampil tanpa "Rp", pakai denganRp: false.
String formatRupiah(num v, {bool denganRp = true, int desimal = 0}) {
  final neg = v < 0;
  final abs = v.abs();
  final s = desimal == 0
      ? abs.toInt().toString()
      : abs.toStringAsFixed(desimal);
  final parts = s.split('.');
  final hasilInteger = groupBacktick(parts[0]);
  var hasil = hasilInteger;
  if (parts.length > 1) hasil = '$hasil.${parts[1]}';
  if (neg) hasil = '-$hasil';
  return denganRp ? 'Rp $hasil' : hasil;
}

/// Rupiah tanpa "Rp" — untuk field input / layar kecil.
String formatAngka(num v) => formatRupiah(v, denganRp: false);

// ---------- LAYAR KALKULATOR (formatHasil) ----------

/// INI KUNCI KENAPA TADI LAYAR MASIH POLOS:
/// Layar kalkulator TIDAK pakai formatRupiah(), tapi pakai formatHasil().
/// formatHasil lama cuma toStringAsFixed(), tanpa grouping.
/// formatHasil baru ini: hitung mentah dulu persis kayak dulu,
/// baru grouping pakai ` di akhir. Jadi logika hitung tidak berubah.
///
/// desimal: 0 | 2 | 3
/// modeRound: "5/4" (bulat biasa) | "CUT" (potong ke bawah) | "F" (bebas)
/// modeHitung: "PEMBULATAN" | "ORIGINAL"
String formatHasil(
  double v, {
  int desimal = 2,
  String modeRound = '5/4',
  String modeHitung = 'PEMBULATAN',
}) {
  if (v.isNaN || v.isInfinite) return 'E';
  String mentah;
  if (modeHitung == 'ORIGINAL') {
    mentah = v.toStringAsFixed(desimal);
  } else if (modeRound == 'CUT') {
    // CUT: potong ke bawah, bukan dibulatkan. Buat nota biar tidak kelebihan tagih.
    double p = 1;
    for (int i = 0; i < desimal; i++) {
      p *= 10;
    }
    final potong = (v * p).truncate() / p;
    mentah = desimal == 0 ? potong.round().toString() : potong.toStringAsFixed(desimal);
  } else if (modeRound == 'F') {
    // F: bebas, buang nol belakang. 1.500000 -> 1.5
    mentah = _buangNolBelakang(v.toStringAsFixed(6));
  } else if (desimal == 0) {
    mentah = v.round().toString();
  } else {
    mentah = v.toStringAsFixed(desimal);
  }
  return groupBacktick(mentah);
}

String _buangNolBelakang(String s) {
  if (!s.contains('.')) return s;
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s.isEmpty ? '0' : s;
}

// ---------- TANGGAL ----------

String formatTanggal(DateTime d) => DateFormat('d MMM yyyy', 'id_ID').format(d);

String formatTanggalLengkap(DateTime d) =>
    DateFormat('EEEE, d MMM yyyy', 'id_ID').format(d);

// ---------- PARSE HARGA (INPUT CEPAT) ----------

/// Parse input harga / qty yang diketik user.
/// Bisa terima: "Rp 50`000", "50.000", "50,000", "50rb", "50k", "1,5jt", "1.5jt", "2jt"
/// "50rb" -> 50000 | "50k" -> 50000 | "1,5jt" -> 1500000 | "Rp 50`000" -> 50000
int parseHarga(String s) {
  var t = s.toLowerCase().replaceAll('rp', '').replaceAll('`', '').replaceAll(' ', '').trim();
  if (t.isEmpty) return 0;
  final neg = t.startsWith('-');
  if (neg) t = t.substring(1);

  double pengali = 1;
  if (t.endsWith('rb') || t.endsWith('k')) {
    pengali = 1000;
    t = t.replaceAll('rb', '').replaceAll('k', '');
  } else if (t.endsWith('jt')) {
    pengali = 1000000;
    t = t.replaceAll('jt', '');
  }

  // 1,5jt -> 1.5 | 50.000 -> 50000 (titik ribuan dibuang kalau bukan desimal jt/rb)
  double nilai;
  if (pengali > 1) {
    // Ada rb/k/jt: koma jadi titik desimal
    t = t.replaceAll(',', '.');
    nilai = double.tryParse(t) ?? 0;
  } else {
    // Tanpa rb/k/jt: titik & koma adalah pemisah ribuan
    t = t.replaceAll('.', '').replaceAll(',', '');
    nilai = double.tryParse(t) ?? 0;
  }
  final hasil = (nilai * pengali).round();
  return neg ? -hasil : hasil;
}

/// Parse qty / angka biasa (boleh desimal, boleh `).
double parseAngka(String s) => double.tryParse(stripBacktick(s).replaceAll(',', '.')) ?? 0;

// ---------- PERSEN ----------

String formatPersen(double v, {int desimal = 1}) =>
    '${v.toStringAsFixed(desimal)}%';

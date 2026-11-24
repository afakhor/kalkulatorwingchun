// formatter.dart - FINAL FIX lolos flutter analyze + grouping kanan benar
// 1`000`000 bukan 1000`000, 20`000 bukan 20000`, 83`333 benar
// Preview nota putih, tidak abu-abu (tanpa intl DateFormat)

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
  // hilangkan titik ribuan jika ada, kecuali desimal
  var parts = t.split('.');
  double nilai;
  if (parts.length > 2) {
    // banyak titik -> anggap ribuan
    t = t.replaceAll('.', '');
    nilai = double.tryParse(t) ?? 0;
  } else if (parts.length == 2 && pengali == 1) {
    // 1 titik tanpa rb/jt -> bisa ribuan atau desimal, cek panjang
    if (parts[1].length == 3) {
      // 50.000 -> 50000
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

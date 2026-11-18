import 'package:intl/intl.dart';

// Format Rupiah pakai backtick `
// 1000 -> Rp 1`000
// 50000 -> Rp 50`000
// 25000 -> Rp 25`000
String formatRupiah(num v) {
  final s = v.toInt().toString();
  final buf = StringBuffer();
  int c = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    buf.write(s[i]);
    c++;
    if (c % 3 == 0 && i != 0) buf.write('`');
  }
  final hasil = buf.toString().split('').reversed.join();
  return 'Rp $hasil';
}

String formatTanggal(DateTime d) => DateFormat('d MMM yyyy', 'id_ID').format(d);

int parseHarga(String s) {
  var t = s.toLowerCase().replaceAll('rp', '').replaceAll('.', '').replaceAll(',', '').replaceAll('`', '').replaceAll(' ', '').trim();
  if (t.endsWith('rb') || t.endsWith('k')) {
    t = '${t.replaceAll('rb', '').replaceAll('k', '')}000';
  }
  if (t.endsWith('jt')) t = '${t.replaceAll('jt', '')}000000';
  return int.tryParse(t) ?? 0;
}
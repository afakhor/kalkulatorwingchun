import 'package:intl/intl.dart';

final _rp = NumberFormat('#,##0', 'id_ID');
String formatRupiah(num v) => 'Rp ${_rp.format(v).replaceAll(',', '.')}';
String formatTanggal(DateTime d) => DateFormat('d MMM yyyy', 'id_ID').format(d);

int parseHarga(String s) {
  var t = s.toLowerCase().replaceAll('rp', '').replaceAll('.', '').replaceAll(',', '').trim();
  if (t.endsWith('rb') || t.endsWith('k')) {
    t = '${t.replaceAll('rb', '').replaceAll('k', '')}000';
  }
  if (t.endsWith('jt')) t = '${t.replaceAll('jt', '')}000000';
  return int.tryParse(t) ?? 0;
}

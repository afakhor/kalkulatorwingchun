import 'package:flutter/material.dart';
import '../core/formatter.dart';
import '../features/calculator/po_calculator.dart';
import '../features/po/po_models.dart';

// Kartu PO di Home - tanpa dummy, hanya tampil kalau ada PO beneran
class KartuPO extends StatelessWidget {
  final PoOrder po;
  final VoidCallback onTap;
  const KartuPO({super.key, required this.po, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = hitungPO(po);
    final catatanBersih = po.catatan.trim();
    final subtitleText = catatanBersih.isEmpty
        ? '${po.items.length} item - ${formatTanggal(po.tanggal)}'
        : '${po.items.length} item - ${formatTanggal(po.tanggal)}\nCatatan: $catatanBersih';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Text('${po.id} - ${po.customer.namaOrang}'),
        subtitle: Text(subtitleText),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatRupiah(h.totalAkhir),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(po.status.name, style: const TextStyle(fontSize: 11)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

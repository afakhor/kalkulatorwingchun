import 'package:flutter/material.dart';
import '../features/po/po_models.dart';
import '../features/calculator/po_calculator.dart';
import '../core/formatter.dart';

// Kartu PO di Home - tanpa dummy, hanya tampil kalau ada PO beneran
class KartuPO extends StatelessWidget {
  final PoOrder po;
  final VoidCallback onTap;
  const KartuPO({super.key, required this.po, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = hitungPO(po);
    return Card(
      child: ListTile(
        title: Text('${po.id} - ${po.customer.namaOrang}'),
        subtitle: Text('${po.items.length} item - ${formatTanggal(po.tanggal)}\nCatatan: ${po.catatan}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text(formatRupiah(h.totalAkhir), style: const TextStyle(fontWeight: FontWeight.bold)), Text(po.status.name)],
        ),
        onTap: onTap,
      ),
    );
  }
}

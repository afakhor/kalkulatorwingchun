import 'package:flutter/material.dart';
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

// Preview Nota putih bersih buat screenshot - tanpa tombol, tanpa UI lain
class NotaPreview extends StatelessWidget {
  final PoOrder po;
  final String namaToko;
  const NotaPreview({super.key, required this.po, this.namaToko = 'TOKO BANGUNAN'});

  @override
  Widget build(BuildContext context) {
    final h = hitungPO(po);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(namaToko, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('${po.id} - ${formatTanggal(po.tanggal)}'),
          Text('Customer: ${po.customer.namaOrang} - ${po.customer.nomorWA}'),
          const Divider(),
          ...po.items.map((i) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('${i.namaBarang} ${i.qty}x'), Text(formatRupiah(i.qty * i.hargaSatuan - i.diskonItem))],
              )),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Diskon'), Text(formatRupiah(po.diskonTotal))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Ongkir'), Text(formatRupiah(po.ongkir))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)), Text(formatRupiah(h.totalAkhir), style: const TextStyle(fontWeight: FontWeight.bold))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('DP'), Text(formatRupiah(po.dp))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sisa Bayar'), Text(formatRupiah(h.sisaBayar))]),
          const SizedBox(height: 12),
          Text('Catatan: ${po.catatan}'),
          Text('Status: ${po.status.name}'),
          const SizedBox(height: 12),
          const Center(child: Text('Terima kasih')),
        ],
      ),
    );
  }
}

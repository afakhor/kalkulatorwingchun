import 'package:flutter/material.dart';
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';

// ============================================================
// Preview Nota - ANGKA pakai DotMatrixText persis layar Casio
// - Nama barang / label / "Rp" tetap pakai Text biasa (DotMatrix hanya angka)
// - Angka harga / qty / total pakai DotMatrixText:
//   * Baris item, Diskon, Ongkir, DP, Sisa = DotMatrixSize.nota (28px, garis putus-putus kecil)
//   * TOTAL = DotMatrixSize.large (44px, garis putus-putus besar, kayak layar bawah Casio)
//   * No. PO di header = DotMatrixSize.small (22px, titik-titik kecil, kayak layar atas Casio)
// ============================================================

class NotaPreview extends StatelessWidget {
  final PoOrder po;
  final String namaToko;
  const NotaPreview({super.key, required this.po, this.namaToko = 'TOKO BANGUNAN'});

  // Angka nota: "Rp " pakai Text, angkanya pakai DotMatrix
  // width dihitung dari panjang angka biar tidak overflow di Row
  Widget _angkaNota(num v, {DotMatrixSize size = DotMatrixSize.nota, Color color = Colors.black}) {
    final teks = _groupNota(v);
    // Perkiraan lebar: tiap karakter ~ (dotW+gap)*5 + gap. nota ~19px/karakter, large ~29px/karakter
    final perChar = size == DotMatrixSize.large ? 29.0 : size == DotMatrixSize.small ? 19.0 : 22.0;
    final w = (teks.length * perChar + 4).clamp(60.0, 320.0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Rp ', style: TextStyle(fontSize: size == DotMatrixSize.large ? 16 : 12, color: color)),
      SizedBox(width: w, child: DotMatrixText(text: teks, size: size, color: color)),
    ]);
  }

  // Angka nota tanpa "Rp ", sudah grouping backtick: 1`500`000
  String _groupNota(num v) {
    // formatHasil sudah grouping backtick, tapi tanpa Rp. Pakai itu, lalu buang "Rp "
    final s = formatRupiah(v.toInt());
    return s.replaceAll('Rp ', '').replaceAll('Rp', '').trim();
  }

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
          // No. PO + tanggal: nomor PO pakai dot-matrix kecil (layar atas Casio)
          Row(children: [
            const Text('No. PO: ', style: TextStyle(fontSize: 13)),
            SizedBox(width: 180, child: DotMatrixText(text: po.id.replaceAll(RegExp(r'[^0-9]'), ''), size: DotMatrixSize.small)),
            const SizedBox(width: 8),
            Expanded(child: Text('- ${formatTanggal(po.tanggal)}', style: const TextStyle(fontSize: 13))),
          ]),
          Text('Customer: ${po.customer.namaOrang} - ${po.customer.nomorWA}'),
          const Divider(),
          // Baris item: nama + qty pakai Text, harga pakai DotMatrix nota
          ...po.items.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('${i.namaBarang} ${formatHasil(i.qty.toDouble())}x', style: const TextStyle(fontSize: 13))),
                    _angkaNota(i.qty * i.hargaSatuan - i.diskonItem),
                  ],
                ),
              )),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Diskon'), _angkaNota(po.diskonTotal)]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Ongkir'), _angkaNota(po.ongkir)]),
          const SizedBox(height: 6),
          // TOTAL: paling besar, kayak layar bawah Casio
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xFFDDE8D0), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              _angkaNota(h.totalAkhir, size: DotMatrixSize.large),
            ]),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('DP'), _angkaNota(po.dp)]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sisa Bayar'), _angkaNota(h.sisaBayar)]),
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

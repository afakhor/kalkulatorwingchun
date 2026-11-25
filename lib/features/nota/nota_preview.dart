import 'package:flutter/material.dart';
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';
import 'nota_pdf.dart';

// Preview Nota FAKTUR RAPI - FIX overflow screenshot 25 Nov:
// - Semua dibungkus SingleChildScrollView + padding 12 (bukan 20), jadi tidak kepotong.
// - Header dibungkus Flexible, BASKORO WINGCHUN (16) + FAKTUR (18) tidak tabrakan lagi.
// - Tabel: total kolom dikecilkan, Nama Barang Flex, Harga/Subtotal pakai DotMatrix SMALL (bukan nota/large).
// - _angkaNota: perChar kecil (10.5) + lebar di-clamp ke kolom, jadi angka tidak meluber keluar tabel.
// - Kolom total kanan: 170 (bukan 240), font 11, field edit 110.

class NotaPreview extends StatefulWidget {
  final PoOrder po;
  final String namaToko;
  final void Function(PoOrder updated)? onChanged;
  const NotaPreview({super.key, required this.po, this.namaToko = 'BASKORO WINGCHUN', this.onChanged});
  @override
  State<NotaPreview> createState() => _NotaPreviewState();
}

class _NotaPreviewState extends State<NotaPreview> {
  late TextEditingController _dpCtrl;
  late TextEditingController _ongkirCtrl;
  late TextEditingController _diskonPersenCtrl;
  late TextEditingController _sisaCtrl;
  bool _editSisa = false;

  @override
  void initState() {
    super.initState();
    _dpCtrl = TextEditingController(text: '${widget.po.dp.toInt()}');
    _ongkirCtrl = TextEditingController(text: '${widget.po.ongkir.toInt()}');
    final sub = widget.po.items.fold<double>(0, (a, i) => a + i.qty * i.hargaSatuan);
    final persen = sub == 0 ? 0.0 : widget.po.diskonTotal / sub * 100;
    _diskonPersenCtrl = TextEditingController(text: persen.toStringAsFixed(persen % 1 == 0 ? 0 : 1));
    _sisaCtrl = TextEditingController(text: '${hitungPO(widget.po).sisaBayar.toInt()}');
  }

  @override
  void dispose() {
    _dpCtrl.dispose(); _ongkirCtrl.dispose(); _diskonPersenCtrl.dispose(); _sisaCtrl.dispose();
    super.dispose();
  }

  PoOrder get _poNow {
    final sub = widget.po.items.fold<double>(0, (a, i) => a + i.qty * i.hargaSatuan);
    final persen = double.tryParse(_diskonPersenCtrl.text.replaceAll(',', '.')) ?? 0;
    final diskon = sub * persen / 100;
    final ongkir = double.tryParse(_ongkirCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final dp = double.tryParse(_dpCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    return PoOrder(id: widget.po.id, tanggal: widget.po.tanggal, customer: widget.po.customer, items: widget.po.items, catatan: widget.po.catatan, dp: dp.toInt(), diskonTotal: diskon.toInt(), ongkir: ongkir.toInt(), status: widget.po.status);
  }

  void _apply() {
    final h = hitungPO(_poNow);
    if (!_editSisa) { _sisaCtrl.text = '${h.sisaBayar.toInt()}'; }
    widget.onChanged?.call(_poNow);
    setState(() {});
  }

  // ANGKA NOTA KECIL: pakai DotMatrix SMALL, lebar menyesuaikan kolom (tidak meluber).
  Widget _angkaNota(num v, {DotMatrixSize size = DotMatrixSize.small, double maxW = 78}) {
    final teks = formatRupiah(v.toInt()).replaceAll('Rp ', '').trim();
    final perChar = size == DotMatrixSize.large ? 13.0 : 10.5;
    final w = (teks.length * perChar + 2).clamp(44.0, maxW);
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
      const Text('Rp ', style: TextStyle(fontSize: 9)),
      SizedBox(width: w, child: DotMatrixText(text: teks, size: size)),
    ]);
  }

  Widget _editRow(String label, TextEditingController ctrl, {String suffix = '', void Function()? onDone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        SizedBox(
          width: 110,
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
            decoration: InputDecoration(suffixText: suffix, suffixStyle: const TextStyle(fontSize: 11), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), isDense: true),
            onSubmitted: (_) { onDone?.call(); _apply(); },
            onChanged: (_) { if (label != 'Sisa Bayar') _apply(); },
          ),
        ),
      ]),
    );
  }

  Widget _sel(String t, {bool bold = false, bool kanan = false, double size = 10}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(t, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal), textAlign: kanan ? TextAlign.right : TextAlign.left, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final po = _poNow;
    final h = hitungPO(po);
    final telp = po.customer.nomorWA.trim();
    final subtotal = po.items.fold<double>(0, (a, i) => a + i.qty * i.hargaSatuan);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.namaToko, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2),
              const SizedBox(height: 2),
              const Text('BABE INFO', style: TextStyle(fontSize: 10)),
            ])),
            const SizedBox(width: 8),
            const Text('FAKTUR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nama Pelanggan : ${po.customer.namaOrang}', style: const TextStyle(fontSize: 11)),
            if (telp.isNotEmpty) Text('No. Telp : $telp', style: const TextStyle(fontSize: 11)),
            Text('Tanggal : ${formatTanggal(po.tanggal)}', style: const TextStyle(fontSize: 11)),
            Text('No. Faktur : ${po.id}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(color: Colors.black, width: 0.8),
            // TOTAL KOLOM FIX = 26+36+40+72+78 = 252, sisanya untuk Nama Barang (Flex). Muat di layar HP.
            columnWidths: const {0: FixedColumnWidth(26), 1: FlexColumnWidth(), 2: FixedColumnWidth(36), 3: FixedColumnWidth(40), 4: FixedColumnWidth(72), 5: FixedColumnWidth(78)},
            children: [
              TableRow(children: [
                for (final t in ['No', 'Nama Barang', 'Qty', 'Satuan', 'Harga', 'Subtotal'])
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), color: Colors.grey.shade200, child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: t == 'Nama Barang' ? TextAlign.left : TextAlign.center)),
              ]),
              ...List.generate(po.items.length, (idx) {
                final i = po.items[idx];
                final sub = i.qty * i.hargaSatuan - i.diskonItem;
                return TableRow(children: [
                  _sel('${idx + 1}'),
                  _sel(i.namaBarang),
                  _sel(formatHasil(i.qty.toDouble()), kanan: true),
                  _sel('', kanan: true),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4), alignment: Alignment.centerRight, child: _angkaNota(i.hargaSatuan, maxW: 66)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4), alignment: Alignment.centerRight, child: _angkaNota(sub, maxW: 72)),
                ]);
              }),
            ],
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Catatan :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              Text(po.catatan.isEmpty ? 'Terima kasih. Telah berkurang, semoga sehat selalu.' : po.catatan, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 12),
              const Text('Penerima / Pembeli', style: TextStyle(fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total', style: TextStyle(fontSize: 11)), _angkaNota(subtotal, maxW: 100)]),
                _editRow('Diskon', _diskonPersenCtrl, suffix: '%'),
                _editRow('Ongkos', _ongkirCtrl),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Grand Total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), _angkaNota(h.totalAkhir, maxW: 100)]),
                _editRow('DP', _dpCtrl),
                _editRow('Sisa Bayar', _sisaCtrl, onDone: () {
                  _editSisa = true;
                  final grand = h.totalAkhir;
                  final sisa = double.tryParse(_sisaCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? grand;
                  _dpCtrl.text = '${(grand - sisa).toInt()}';
                  _editSisa = false;
                  _apply();
                }),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          const Center(child: Text('Terima kasih', style: TextStyle(fontSize: 11))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: () async { await shareNotaPdf(_poNow, namaToko: widget.namaToko); }, child: const Text('Share WA PDF'))),
          ]),
        ]),
      ),
    );
  }
}

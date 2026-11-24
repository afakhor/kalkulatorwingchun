import 'package:flutter/material.dart';
import '../po/po_models.dart';
import '../calculator/po_calculator.dart';
import '../../core/formatter.dart';
import 'nota_pdf.dart';

// Preview Nota FAKTUR - bisa EDIT di preview:
// DP, Ongkos, Diskon (%), Sisa Bayar bisa diisi di preview.
// Sisa Bayar = Grand Total - DP. Kalau Sisa Bayar diedit, DP ikut berubah (DP = Grand - Sisa).
// Header TANPA HUB. 082111122041, TANPA "(opsional)".

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
    // diskonTotal -> persen dari subtotal
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
    if (!_editSisa) {
      _sisaCtrl.text = '${h.sisaBayar.toInt()}';
    }
    widget.onChanged?.call(_poNow);
    setState(() {});
  }

  Widget _angkaNota(num v, {DotMatrixSize size = DotMatrixSize.nota}) {
    final teks = formatRupiah(v.toInt()).replaceAll('Rp ', '').trim();
    final perChar = size == DotMatrixSize.large ? 29.0 : 22.0;
    final w = (teks.length * perChar + 4).clamp(60.0, 320.0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Rp ', style: TextStyle(fontSize: size == DotMatrixSize.large ? 16 : 12)),
      SizedBox(width: w, child: DotMatrixText(text: teks, size: size)),
    ]);
  }

  Widget _editRow(String label, TextEditingController ctrl, {String suffix = '', void Function()? onDone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        SizedBox(
          width: 130,
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(suffixText: suffix, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), isDense: true),
            onSubmitted: (_) { onDone?.call(); _apply(); },
            onChanged: (_) { if (label != 'Sisa Bayar') _apply(); },
          ),
        ),
      ]),
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
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.namaToko, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('BABE INFO', style: TextStyle(fontSize: 12)),
          ]),
          const Text('FAKTUR', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nama Pelanggan : ${po.customer.namaOrang}', style: const TextStyle(fontSize: 13)),
            if (telp.isNotEmpty) Text('No. Telp : $telp', style: const TextStyle(fontSize: 13)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tanggal : ${formatTanggal(po.tanggal)}', style: const TextStyle(fontSize: 13)),
            Text('No. Faktur : ${po.id}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
        ]),
        const SizedBox(height: 12),
        Table(
          border: TableBorder.all(color: Colors.black, width: 0.8),
          columnWidths: const {0: FixedColumnWidth(32), 1: FlexColumnWidth(), 2: FixedColumnWidth(44), 3: FixedColumnWidth(64), 4: FixedColumnWidth(110), 5: FixedColumnWidth(120)},
          children: [
            TableRow(children: [
              for (final t in ['No', 'Nama Barang', 'Qty', 'Satuan', 'Harga', 'Subtotal'])
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), color: Colors.grey.shade200, child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: t == 'Nama Barang' ? TextAlign.left : TextAlign.center)),
            ]),
            ...List.generate(po.items.length, (idx) {
              final i = po.items[idx];
              final sub = i.qty * i.hargaSatuan - i.diskonItem;
              return TableRow(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('${idx + 1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text(i.namaBarang, style: const TextStyle(fontSize: 12))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text(formatHasil(i.qty.toDouble()), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), alignment: Alignment.centerRight, child: _angkaNota(i.hargaSatuan)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), alignment: Alignment.centerRight, child: _angkaNota(sub)),
              ]);
            }),
          ],
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Catatan :', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(po.catatan.isEmpty ? 'Terima kasih. Telah berkurang, semoga sehat selalu.' : po.catatan, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            const Text('Penerima / Pembeli', style: TextStyle(fontSize: 12)),
          ])),
          const SizedBox(width: 12),
          SizedBox(
            width: 240,
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total', style: TextStyle(fontSize: 12)), _angkaNota(subtotal)]),
              // Diskon dalam % - bisa diedit di preview
              _editRow('Diskon', _diskonPersenCtrl, suffix: '%'),
              // Ongkos (ongkir) - bisa diedit di preview
              _editRow('Ongkos', _ongkirCtrl),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Grand Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), _angkaNota(h.totalAkhir, size: DotMatrixSize.large)]),
              // DP - bisa diedit di preview
              _editRow('DP', _dpCtrl),
              // Sisa Bayar - bisa diedit, kalau diedit DP ikut berubah
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
        const SizedBox(height: 12),
        const Center(child: Text('Terima kasih', style: TextStyle(fontSize: 12))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(onPressed: () async { await shareNotaPdf(_poNow, namaToko: widget.namaToko); }, child: const Text('Share WA PDF'))),
        ]),
      ]),
    );
  }
}

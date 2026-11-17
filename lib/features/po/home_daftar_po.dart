import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/formatter.dart';
//import '../../core/theme.dart';
import 'po_provider.dart';
import 'parse_cepat.dart';
//import '../calculator/po_calculator.dart';

class HomeDaftarPO extends ConsumerStatefulWidget {
  const HomeDaftarPO({super.key});
  @override
  ConsumerState<HomeDaftarPO> createState() => _S();
}

class _S extends ConsumerState<HomeDaftarPO> {
  // LAYAR KALKULATOR
  String layar = "0";
  String layarKetik = "";
  String _operator = "";
  double _angka1 = 0;
  
  // MASTER BARANG - sesuai permintaanmu
  final kodeCtrl = TextEditingController();
  final kategoriCtrl = TextEditingController();
  final namaCtrl = TextEditingController();
  final variasiCtrl = TextEditingController();
  final satuanCtrl = TextEditingController(text: "pcs");
  final hargaCtrl = TextEditingController();

  // MENU BIRU & KUNING dropdown
  String menuBiru = "MASTER / TOTAL / KOREKSI / LOG / NOTA";
  String menuKuning = "PEMBULATAN / ORIGINAL";
  bool showMaster = true;
  bool showLog = false;

  // PROFIT INDICATOR
  double hargaDefault = 0;
  double ongkir = 0;
  double diskon = 0;

  Color _warnaProfit() {
    if (hargaDefault == 0) return Colors.black;
    final hargaJual = double.tryParse(layar) ?? 0;
    if (hargaJual == 0) return Colors.black;
    final modal = hargaDefault + ongkir - diskon;
    final persen = modal == 0 ? 0 : ((hargaJual - modal) / modal * 100);
    if (persen < -20) return Colors.red.shade900; // rugi besar
    if (persen < 0) return Colors.red; // rugi sedang
    if (persen < 5) return Colors.yellow.shade800; // warning operasional
    if (persen < 15) return const Color(0xFF7C4DFF); // violet untung kecil
    return Colors.green; // untung sedang/besar
  }

  String _teksPersen() {
    if (hargaDefault == 0) return "---";
    final hargaJual = double.tryParse(layar) ?? 0;
    if (hargaJual == 0) return "---";
    final modal = hargaDefault + ongkir - diskon;
    final persen = modal == 0 ? 0 : ((hargaJual - modal) / modal * 100);
    return "${persen.toStringAsFixed(1)}%";
  }

  void pencet(String t) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "C" || t == "AC") {
        layar = "0"; _operator = ""; _angka1 = 0; layarKetik = "";
      } else if (["+", "-", "x", "/"].contains(t)) {
        _angka1 = double.tryParse(layar) ?? 0;
        _operator = t;
        layar = "0";
      } else if (t == "=") {
        final a2 = double.tryParse(layar) ?? 0;
        double h = 0;
        if (_operator == "+") h = _angka1 + a2;
        if (_operator == "-") h = _angka1 - a2;
        if (_operator == "x") h = _angka1 * a2;
        if (_operator == "/") h = a2 == 0 ? 0 : _angka1 / a2;
        layar = h.toStringAsFixed(0);
        _operator = "";
      } else if (t == "M+") {
        // Masukkan ke PO - ini tombol hijau yang kamu lingkarin
        final item = parseInputCepat(layarKetik.isEmpty ? "${layar}x ${namaCtrl.text} ${hargaCtrl.text}" : layarKetik);
        if (item != null) {
          ref.read(poProvider.notifier).tambahItem(item);
        } else if (namaCtrl.text.isNotEmpty) {
          final qty = int.tryParse(layar) ?? 1;
          final harga = int.tryParse(hargaCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final it = parseInputCepat("$qty x ${namaCtrl.text} $harga");
          if (it != null) ref.read(poProvider.notifier).tambahItem(it);
        }
        layar = "0";
      } else if (t == "120") {
        layar = ((double.tryParse(layar) ?? 0) + 120).toStringAsFixed(0);
      } else if (t == "0" || t == "00" || t == "000" || RegExp(r'[0-9]').hasMatch(t)) {
        if (layar == "0") layar = t;
        else layar += t;
        if (t.length <= 1) layarKetik += t;
      }
    });
  }

  Widget tombol(String label, {Color? bg, Color? fg, bool besar = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          height: besar ? 72 : 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: bg ?? Colors.white,
              foregroundColor: fg ?? Colors.black,
              textStyle: TextStyle(fontSize: besar ? 22 : 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => pencet(label),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final po = ref.watch(poProvider);
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('ELECTRONIC CALCULATOR - 12 DIGITS', style: TextStyle(color: Colors.white70, fontSize: 10)),
        actions: [
          Text('MASTER BARANG', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // LAYAR IJO - sesuai foto kalkulator
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF8FA68E), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black, width: 3)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('M', style: TextStyle(color: Colors.black54)), Text('GT', style: TextStyle(color: Colors.black54)), Text('0', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))]),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFFA8C4A6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(layar, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _warnaProfit())),
                          Text(_teksPersen(), style: TextStyle(fontSize: 14, color: _warnaProfit(), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(layarKetik.isEmpty ? 'Logistik warna persediaan ->' : layarKetik, style: TextStyle(fontSize: 10, color: Colors.black87)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // MENU BIRU
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(20)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: menuBiru,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    dropdownColor: Colors.blue,
                    items: ["MASTER / TOTAL / KOREKSI / LOG / NOTA", "MASTER BARANG", "TOTAL", "KOREKSI PER BARIS", "LOG PO", "NOTA"].map((e) => DropdownMenuItem(value: e == "MASTER / TOTAL / KOREKSI / LOG / NOTA" ? menuBiru : e, child: Text(e, style: TextStyle(fontSize: 11)))).toList(),
                    onChanged: (v) {
                      setState(() {
                        menuBiru = v!;
                        showMaster = v.contains("MASTER");
                        showLog = v.contains("LOG");
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // MASTER BARANG - ini yang kamu minta ganti favorit jadi input kode/kategori/nama/variasi/satuan/harga
              if (showMaster)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFE8E0C8), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('— MASTER BARANG', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                      const SizedBox(height: 6),
                      Text('Hitung dulu sebelum masuk kalkulator, lalu kirim hasilnya ke PO. Semua angka dihitung real-time dalam format Rupiah Indonesia.', style: TextStyle(fontSize: 9)),
                      const SizedBox(height: 8),
                      Row(children: [Expanded(child: TextField(controller: kodeCtrl, decoration: InputDecoration(labelText: 'Kode Barang', isDense: true, border: OutlineInputBorder()))), const SizedBox(width: 6), Expanded(child: TextField(controller: kategoriCtrl, decoration: InputDecoration(labelText: 'Kategori', isDense: true, border: OutlineInputBorder())))]),
                      const SizedBox(height: 6),
                      TextField(controller: namaCtrl, decoration: InputDecoration(labelText: 'Nama Barang', isDense: true, border: OutlineInputBorder())),
                      const SizedBox(height: 6),
                      Row(children: [Expanded(child: TextField(controller: variasiCtrl, decoration: InputDecoration(labelText: 'Variasi', isDense: true, border: OutlineInputBorder()))), const SizedBox(width: 6), Expanded(child: TextField(controller: satuanCtrl, decoration: InputDecoration(labelText: 'Satuan / Custom', isDense: true, border: OutlineInputBorder()))), const SizedBox(width: 6), Expanded(child: TextField(controller: hargaCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Harga Satuan', isDense: true, border: OutlineInputBorder()), onChanged: (v) => setState(() => hargaDefault = double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)))])
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // MENU KUNING + PEMBULATAN
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text('5/4', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 8),
                      Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: menuKuning, isDense: true, style: TextStyle(color: Colors.white, fontSize: 10), dropdownColor: Colors.black, items: [menuKuning, "PEMBULATAN", "ORIGINAL"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(fontSize: 10)))).toList(), onChanged: (v) => setState(() => menuKuning = v!)))),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: ["A", "0", "2", "3", "F"].map((e) => Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: e == "F" ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(4)), child: Text(e, style: TextStyle(color: e == "F" ? Colors.white : Colors.black, fontSize: 10)))).toList()))),
              ]),
              const SizedBox(height: 12),
              // TOMBOL KALKULATOR - versi fisik
              Column(
                children: [
                  Row(children: [tombol("MC", bg: Colors.black, fg: Colors.white), tombol("MR", bg: Colors.black, fg: Colors.white), tombol("M-", bg: Colors.black, fg: Colors.white), tombol("M+", bg: const Color(0xFF2E7D32), fg: Colors.white, besar: true), tombol("GT", bg: Colors.black, fg: Colors.white)]),
                  Row(children: [tombol("AC", bg: Colors.red, fg: Colors.white), tombol("C/CE", bg: Colors.red, fg: Colors.white), tombol("%"), tombol("√"), tombol("÷")]),
                  Row(children: [tombol("7"), tombol("8"), tombol("9"), tombol("MRC", bg: Colors.black, fg: Colors.white), tombol("x")]),
                  Row(children: [tombol("4"), tombol("5"), tombol("6"), tombol("M-", bg: Colors.black, fg: Colors.white), tombol("-")]),
                  Row(children: [tombol("1"), tombol("2"), tombol("3"), tombol("M+", bg: const Color(0xFF2E7D32), fg: Colors.white, besar: true), tombol("+")]),
                  Row(children: [tombol("0"), tombol("00"), tombol("000"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true)]),
                  Row(children: [tombol("120", bg: Colors.orange, fg: Colors.white), tombol("000", bg: Colors.grey.shade300), const Spacer(), tombol("=", bg: Colors.blue, fg: Colors.white)]),
                ],
              ),
              const SizedBox(height: 12),
              // BARIS PO - MEMORI + TAMBAH PO
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF2E2E2E), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BARIS PO - MEMORI + TAMBAH PO', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    if (po.items.isEmpty) Text('Belum ada item - pencet M+ untuk tambah', style: TextStyle(color: Colors.white70, fontSize: 11))
                    else ...po.items.asMap().entries.map((e) => Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Expanded(child: Text('${e.key + 1}. ${e.value.namaBarang} - ${e.value.qty}x ${formatRupiah(e.value.hargaSatuan)}', style: TextStyle(fontSize: 11))),
                            Row(children: [
                              IconButton(icon: Icon(Icons.edit, size: 14), onPressed: () {}, padding: EdgeInsets.zero, constraints: BoxConstraints()),
                              IconButton(icon: Icon(Icons.delete, size: 14), onPressed: () => ref.read(poProvider.notifier).hapusItem(e.key), padding: EdgeInsets.zero, constraints: BoxConstraints()),
                            ])
                          ]),
                        )),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Subtotal: ${formatRupiah(hasil.subtotal)}', style: TextStyle(color: Colors.white, fontSize: 11)), Text('Total: ${formatRupiah(hasil.totalAkhir)}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: FilledButton(onPressed: () {}, child: Text('Kirim WA'))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () {}, child: Text('Screenshot Nota')))]),
            ],
          ),
        ),
      ),
    );
  }
}
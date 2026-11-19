import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/formatter.dart';
import 'po_provider.dart';
import 'parse_cepat.dart';

class SatuanItem {
  SatuanItem({required String satuan, required this.dasar, required String qty, required String isi, required this.op, required String nominal, String satuanBaru = ''})
      : namaCtrl = TextEditingController(text: satuan),
        qtyCtrl = TextEditingController(text: qty),
        isiCtrl = TextEditingController(text: isi),
        nominalCtrl = TextEditingController(text: nominal),
        satuanBaruCtrl = TextEditingController(text: satuanBaru);
  TextEditingController namaCtrl;
  TextEditingController qtyCtrl;
  TextEditingController isiCtrl;
  TextEditingController nominalCtrl;
  TextEditingController satuanBaruCtrl;
  bool dasar;
  String op;
  bool nominalManual = false;
  Map<String, dynamic> toMap() {
    return {"satuan": namaCtrl.text, "satuanBaru": satuanBaruCtrl.text, "dasar": dasar, "qty": qtyCtrl.text, "isi": isiCtrl.text, "op": op, "nominal": nominalCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')};
  }
  void dispose() { namaCtrl.dispose(); qtyCtrl.dispose(); isiCtrl.dispose(); nominalCtrl.dispose(); satuanBaruCtrl.dispose(); }
}

class _AutoField extends StatefulWidget {
  const _AutoField({required this.controller, this.hint = "", this.angka = false, this.onChanged, this.min = 44, this.max = 150});
  final TextEditingController controller; final String hint; final bool angka; final ValueChanged<String>? onChanged; final double min; final double max;
  @override State<_AutoField> createState() => _AutoFieldS();
}
class _AutoFieldS extends State<_AutoField> {
  double w = 56;
  @override void initState() { super.initState(); _ukur(); widget.controller.addListener(_ukur); }
  @override void dispose() { widget.controller.removeListener(_ukur); super.dispose(); }
  void _ukur() {
    final tp = TextPainter(text: TextSpan(text: widget.controller.text.isEmpty ? widget.hint : widget.controller.text, style: const TextStyle(fontSize: 13)), textDirection: TextDirection.ltr)..layout();
    final nw = (tp.width + 26).clamp(widget.min, widget.max);
    if ((nw - w).abs() > 1) setState(() => w = nw);
  }
  @override Widget build(BuildContext context) {
    return SizedBox(width: w, child: TextField(controller: widget.controller, keyboardType: widget.angka ? TextInputType.number : TextInputType.text, textAlign: widget.angka ? TextAlign.center : TextAlign.left, style: const TextStyle(fontSize: 13), decoration: InputDecoration(hintText: widget.hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11), border: const OutlineInputBorder()), onChanged: (v) { _ukur(); widget.onChanged?.call(v); }));
  }
}

class HomeDaftarPO extends ConsumerStatefulWidget {
  const HomeDaftarPO({super.key});
  @override ConsumerState<HomeDaftarPO> createState() => _S();
}

class _S extends ConsumerState<HomeDaftarPO> {
  // ===== MESIN CASIO - STATE ASLI, BUKAN LAYAR SAJA =====
  // layar = angka yang sedang diketik / hasil terakhir (entry)
  // akumulator = angka pertama yang disimpan saat pencet operator (Casio: operand 1)
  // opPending = operator yang menunggu operand 2
  // ekspresi = baris atas display, misal "5 x 80`000"
  // entryBaru = true berarti ketikan berikutnya ganti layar, bukan nempel
  // qtyHitung = angka SEBELUM operator (untuk M+ / PO). BUKAN hasil =.
  String layar = "0";
  String ekspresi = "";
  double akumulator = 0;
  String opPending = "";
  String op = ""; // alias lama, tetap ada biar tidak ada yang panggil op hilang
  double angka1 = 0; // alias akumulator
  bool entryBaru = true;
  bool adaError = false;
  String lastOp = "";
  double lastAngka2 = 0;
  double qtyHitung = 1;
  bool adaQtyHitung = false;
  double memori = 0;
  double grandTotal = 0;
  // ===== LACI MULTITASKING CASIO — BARU, TIDAK MENGHAPUS LACI LAMA =====
  double tarifPajak = 11;
  double laciCost = 0;
  double laciSell = 0;
  double laciMargin = 0;
  bool modeAdd2 = false;
  String modeRound = "5/4";
  List<String> antreanKetikan = [];
  bool tekanTombol = false;
  String tombolDitekan = "";
  Map<String, String>? barangDipilih;
  bool poTerbuka = false;
  // MERAH: Nomor series PO. Format: PO B•WC-001B•I, lalu 002, 003, dst. 00 = padding 3 digit.
  int nomorPO = 1;
  String get nomorPOSeries => "PO B\u2022WC-${nomorPO.toString().padLeft(3, '0')}B\u2022I";
  // PUTIH: tinggi panel PO, bisa dikecil-besarkan tanpa nutup kalkulator
  double poTinggi = 300;
  final List<Map<String, dynamic>> daftarBarang = [];
  String queryLS = "";
  final kodeCtrl = TextEditingController();
  final namaCtrl = TextEditingController();
  String kategoriPilih = "Semen";
  final List<String> listKategori = ["Semen", "Besi", "Cat", "Keramik", "Pipa"];
  final kategoriBaruCtrl = TextEditingController();
  final unitCtrl = TextEditingController(text: "sak");
  final harga1Ctrl = TextEditingController(text: "50000");
  final List<TextEditingController> varianCtrls = [TextEditingController(text: "Hitam")];
  final Set<String> daftarSatuan = {"sak", "kg", "kilo", "m", "3m", "pcs"};
  void tambahKeDaftarSatuan(String nama) {
    final v = nama.trim().toLowerCase();
    if (v.isEmpty) return;
    daftarSatuan.add(v);
  }
  InputDecoration dec(String hint, {String? prefix}) {
    return InputDecoration(hintText: hint, prefixText: prefix, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11), border: const OutlineInputBorder());
  }
  List<SatuanItem> satuanList = [
    SatuanItem(satuan: "sak", dasar: true, qty: "1", isi: "1", op: "x", nominal: "50000", satuanBaru: "sak"),
    SatuanItem(satuan: "sak", dasar: false, qty: "1", isi: "50", op: "÷", nominal: "1000", satuanBaru: "pcs"),
  ];
  String modeHitung = "PEMBULATAN";
  int desimal = 0;
  final List<Map<String, dynamic>> steps = [];
  double get hargaAcuan {
    if (barangDipilih != null) return double.tryParse("${barangDipilih!["harga1"]}") ?? 0;
    return 0;
  }
  double get manual => double.tryParse(_stripBacktick(layar)) ?? 0;
  double get persen {
    if (hargaAcuan == 0) return 0;
    if (manual == 0) return 0;
    return (manual - hargaAcuan) / hargaAcuan * 100;
  }
  Color warnaSaran() {
    if (hargaAcuan == 0) return Colors.black;
    if (manual == 0) return Colors.black;
    if (persen < -20) return const Color(0xFFB71C1C);
    if (persen < 0) return Colors.red;
    if (persen < 5) return const Color(0xFFB58900);
    if (persen < 15) return Colors.blue;
    return Colors.green;
  }
  String teksAcuan() {
    if (hargaAcuan == 0) return "---";
    return formatRupiah(hargaAcuan.toInt());
  }
  String teksSaran() {
    if (hargaAcuan == 0) return "---";
    if (manual == 0) return "---";
    return "${persen.toStringAsFixed(1)}%";
  }
  // ===== BACKTICK LAYAR KALKULATOR =====
  // Penyebab layar polos: layar pakai formatHasil(), bukan formatRupiah(). formatHasil lama cuma toStringAsFixed(), tanpa grouping.
  String _stripBacktick(String s) => s.replaceAll('`', '').replaceAll('Rp', '').replaceAll(' ', '');
  double _parseLayar() => double.tryParse(_stripBacktick(layar)) ?? 0;
  String _groupBacktick(String s) {
    if (s == "E" || s.isEmpty) return s;
    var neg = false; if (s.startsWith('-')) { neg = true; s = s.substring(1); }
    var parts = s.split('.'); var integer = parts[0].isEmpty ? "0" : parts[0];
    var buf = StringBuffer(); int c = 0;
    for (int i = integer.length - 1; i >= 0; i--) { buf.write(integer[i]); c++; if (c % 3 == 0 && i != 0) buf.write('`'); }
    var hasil = buf.toString().split('').reversed.join();
    if (parts.length > 1) hasil = "$hasil.${parts[1]}";
    return neg ? "-$hasil" : hasil;
  }
  String formatHasil(double v) {
    if (v.isNaN || v.isInfinite) return "E";
    String mentah;
    if (modeHitung == "ORIGINAL") mentah = v.toStringAsFixed(desimal);
    else if (modeRound == "CUT") { final p = desimal == 0 ? 1.0 : _pow10(desimal); final potong = (v * p).truncate() / p; mentah = desimal == 0 ? potong.round().toString() : potong.toStringAsFixed(desimal); }
    else if (modeRound == "F") mentah = _buangNolBelakang(v.toStringAsFixed(6));
    else if (desimal == 0) mentah = v.round().toString();
    else mentah = v.toStringAsFixed(desimal);
    return _groupBacktick(mentah);
  }
  double _pow10(int n) { double r = 1; for (int i = 0; i < n; i++) r *= 10; return r; }
  String _buangNolBelakang(String s) { if (!s.contains('.')) return s; while (s.endsWith('0')) s = s.substring(0, s.length - 1); if (s.endsWith('.')) s = s.substring(0, s.length - 1); return s.isEmpty ? "0" : s; }
  // Operasi dasar Casio: a op b. Bagi 0 -> error, bukan 0 diam-diam.
  double? hitungDasar(double a, String o, double b) {
    if (o == "+") return a + b;
    if (o == "-") return a - b;
    if (o == "x") return a * b;
    if (o == "÷" || o == "/") { if (b == 0) return null; return a / b; }
    return b;
  }
  // ===== RUMUS SATUAN - DARI HARGA 1, BUKAN DARI NOMINAL =====
  double hitungNominal(SatuanItem s) {
    final qty = double.tryParse(s.qtyCtrl.text) ?? 1;
    final isi = double.tryParse(s.isiCtrl.text) ?? 1;
    final hargaForm = double.tryParse(harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final harga = hargaForm > 0 ? hargaForm : hargaAcuan;
    if (s.dasar) return harga * qty;
    if (s.op == "÷") { if (isi == 0) return 0; return qty * (harga / isi); }
    return qty * harga * isi;
  }
  void refreshNominal(SatuanItem s) {
    if (s.nominalManual) return;
    final hasil = hitungNominal(s);
    s.nominalCtrl.text = hasil.toStringAsFixed(0);
  }
  void syncUnitDariDasar() {
    final dasar = satuanList.firstWhere((x) => x.dasar == true, orElse: () => satuanList.first);
    unitCtrl.text = dasar.namaCtrl.text;
  }
  // ===== INFO MERAH - HANYA INFO, TIDAK PERNAH BACA nominalCtrl =====
  // Edit field Rp nominal TIDAK mengubah baris ini, karena baris ini
  // dihitung ulang dari Harga 1 + qty/isi/op. Nominal = harga jual manual.
  String teksRumusSatuan(SatuanItem s) {
    final qty = s.qtyCtrl.text.isEmpty ? "1" : s.qtyCtrl.text;
    final isi = s.isiCtrl.text.isEmpty ? "1" : s.isiCtrl.text;
    final satuanBiru = s.namaCtrl.text;
    final unitHijau = s.satuanBaruCtrl.text.isEmpty ? satuanBiru : s.satuanBaruCtrl.text;
    final infoHasil = hitungNominal(s); // <-- dari Harga 1, bukan dari Rp nominal
    if (s.dasar) return "$qty $satuanBiru = ${formatRupiah(infoHasil.toInt())}  (info)";
    return "$qty $satuanBiru ${s.op} $isi $unitHijau = ${formatRupiah(infoHasil.toInt())}  (info)";
  }
  void dialogBabe() {
    final namaBarang = barangDipilih == null ? "Belum pilih barang (pencet LS)" : "${barangDipilih!["nama"]}";
    final acuan = hargaAcuan; final nilaiManual = manual; final warna = warnaSaran();
    final namaWarna = warna == Colors.black ? "HITAM - belum ada acuan" : warna == const Color(0xFFB71C1C) ? "MERAH TUA - rugi besar" : warna == Colors.red ? "MERAH - rugi" : warna == const Color(0xFFB58900) ? "KUNING - waspada" : warna == Colors.blue ? "BIRU - untung kecil" : "HIJAU - untung";
    final bep = acuan > 0 ? acuan * 1.1 : 0;
    final totalStep = steps.fold<double>(0, (a, x) => a + ((x["jumlah"] as num?)?.toDouble() ?? 0));
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("BABE.INFO - Dialog Uni"),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text("Barang: $namaBarang", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        Text("Unit Biru (auto sama): ${unitCtrl.text}", style: const TextStyle(fontSize: 11)),
        const Divider(),
        Text("Layar: $layar | Acuan: ${acuan == 0 ? "---" : formatRupiah(acuan.toInt())} | Persen: ${acuan == 0 || nilaiManual == 0 ? "---" : "${persen.toStringAsFixed(1)}%"}", style: TextStyle(fontSize: 11, color: warna)),
        Text("Warna: $namaWarna | BEP: ${bep == 0 ? "---" : formatRupiah(bep.toInt())} | Memori: ${formatRupiah(memori.toInt())}", style: const TextStyle(fontSize: 11)),
        const Divider(), const Text("SATUAN - Biru = dasar, Hijau = satuan baru", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        ...satuanList.map((x) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text("${teksRumusSatuan(x)}${x.nominalManual ? " • NOMINAL MANUAL" : " • NOMINAL AUTO"}", style: const TextStyle(fontSize: 11)))),
        const Divider(), const Text("CEK - STEP (riwayat hitung Casio)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        if (steps.isEmpty) const Text("Belum ada step.", style: TextStyle(fontSize: 11)),
        ...steps.asMap().entries.map((e) => Text("${e.key + 1}. ${e.value["rumus"] ?? e.value["item"]}", style: const TextStyle(fontSize: 11))),
        if (steps.isNotEmpty) Text("Total step: ${formatRupiah(totalStep.toInt())}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const Divider(), const Text("• Harga 1 = harga per Unit Biru.\n• 1 sak ÷ 50 pcs = 1`000 / pcs (info dari Harga 1)\n• 1 m x 3 3m = 75`000 / 3m\n• BEP = Acuan x 110%.", style: TextStyle(fontSize: 11)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup"))]));
  }
  void refreshSemuaNominal() { for (var s in satuanList) { refreshNominal(s); } }

  void bukaCek() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) => Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
        child: SizedBox(height: 480, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CEK - Riwayat Hitung (Casio)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
          const SizedBox(height: 4),
          const Text("CEK = riwayat, bukan PO. Edit 1 step di sini -> total CEK ikut berubah. PO / info satuan tidak berubah.", style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 6),
          Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: Text("TOTAL CEK = ${formatHasil(totalCek)}  |  GT = ${formatHasil(grandTotal)}  |  TAX = ${formatHasil(tarifPajak)}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(height: 8),
          if (steps.isEmpty) const Text("Belum ada step. Pencet = dulu."),
          Expanded(child: ListView.builder(itemCount: steps.length, itemBuilder: (_, i) {
            final st = steps[i];
            final ctrl = TextEditingController(text: "${(st["jumlah"] as num?)?.toDouble() ?? 0}");
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("${st["rumus"] ?? st["item"]}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Edit jumlah step ini", isDense: true, border: OutlineInputBorder()))),
                  const SizedBox(width: 6),
                  ElevatedButton(onPressed: () { final v = double.tryParse(ctrl.text) ?? 0; setSheet(() { _editStepCek(i, v); }); setState(() {}); }, child: const Text("SIMPAN")),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () { setSheet(() { _hapusStepCek(i); }); setState(() {}); }),
                ]),
              ]));
          })),
        ])))),
      );
  }
  void _inputAngka(String t) {
    if (adaError) { layar = "0"; ekspresi = ""; akumulator = 0; opPending = ""; op = ""; adaError = false; entryBaru = true; }
    layar = _stripBacktick(layar); // layar mungkin sudah berisi ` dari formatHasil sebelumnya
    if (entryBaru) { layar = (t == ".") ? "0." : t; entryBaru = false; adaQtyHitung = false; }
    else {
      if (t == "." && layar.contains(".")) return;
      if (layar.replaceAll("-", "").replaceAll(".", "").length >= 12) return; // Casio 12 digit, hitung digit saja, bukan `
      if (layar == "0" && t != ".") { layar = t; } else { layar += t; }
    }
    layar = _groupBacktick(layar); // langsung tampil 1`000 saat ketik, bukan nunggu =
  }
  void _inputOperator(String t) {
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    // FIX KEPENCET OPERATOR 2x: 1000 + lalu kepencet - -> cuma ganti operator, angka tetap 1000.
    if (opPending.isNotEmpty && entryBaru) { opPending = t; op = t; ekspresi = "${formatHasil(akumulator)} $t"; entryBaru = true; return; }
    // Casio chain: 2 + 3 + -> hitung 2+3 dulu, baru tunggu angka berikutnya
    if (opPending.isNotEmpty && !entryBaru) {
      final h = hitungDasar(akumulator, opPending, cur);
      if (h == null) { layar = "E"; adaError = true; return; }
      akumulator = h; angka1 = h; layar = formatHasil(h);
    } else if (opPending.isEmpty) {
      akumulator = cur; angka1 = cur;
      // Simpan qty SEBELUM operator untuk M+ nanti. Ini kuncinya: 5 x 80000 -> qtyHitung=5, bukan 400000.
      qtyHitung = cur; adaQtyHitung = true;
    }
    opPending = t; op = t;
    ekspresi = "${formatHasil(akumulator)} $t";
    entryBaru = true;
  }
  void _inputSamaDengan() {
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    double a, b; String o;
    if (opPending.isNotEmpty) {
      a = akumulator; b = cur; o = opPending;
      lastOp = o; lastAngka2 = b;
      // qtyHitung sudah disimpan saat pencet operator (angka pertama)
    } else if (lastOp.isNotEmpty) {
      // Casio: pencet = berulang -> ulangi operasi terakhir. 5 + = = = -> 10, 15, 20
      a = cur; b = lastAngka2; o = lastOp;
    } else { return; }
    final h = hitungDasar(a, o, b);
    if (h == null) { layar = "E"; ekspresi = "${formatHasil(a)} $o ${formatHasil(b)} = E"; adaError = true; return; }
    ekspresi = "${formatHasil(a)} $o ${formatHasil(b)} = ${formatHasil(h)}";
    // CEK step: simpan RUMUS lengkap, bukan harga x qty yang salah arti
    steps.add({"item": ekspresi, "rumus": ekspresi, "harga": a, "qty": b, "jumlah": h});
    grandTotal += h;
    akumulator = h; angka1 = h; layar = formatHasil(h);
    opPending = ""; op = "";
    entryBaru = true;
    // qtyHitung TETAP angka pertama, jangan ditimpa hasil. Inilah fix qty jadi subtotal.
  }
  void _inputPersen() {
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    // Casio %: 200 + 10% = 220 | 200 x 10% = 20 | 200 - 10% = 180 | 200 ÷ 10% = 2000
    double h;
    if (opPending == "+") { h = akumulator + (akumulator * cur / 100); }
    else if (opPending == "-") { h = akumulator - (akumulator * cur / 100); }
    else if (opPending == "x") { h = akumulator * cur / 100; }
    else if (opPending == "÷" || opPending == "/") { if (cur == 0) { layar = "E"; adaError = true; return; } h = akumulator / (cur / 100); }
    else { h = cur / 100; }
    ekspresi = opPending.isEmpty ? "$cur% = ${formatHasil(h)}" : "${formatHasil(akumulator)} $opPending $cur% = ${formatHasil(h)}";
    steps.add({"item": ekspresi, "rumus": ekspresi, "harga": akumulator, "qty": cur, "jumlah": h});
    layar = formatHasil(h); akumulator = h; angka1 = h; opPending = ""; op = ""; entryBaru = true;
  }
  // ===== TAX / CSM / ADD2 / ROUND — BARU, LACI TERPISAH =====
  double _angkaLayar() => _parseLayar();
  void _pencetTaxPlus() { final v = _angkaLayar(); final pajak = v * tarifPajak / 100; layar = formatHasil(v + pajak); ekspresi = "${formatHasil(v)} TAX+ ${tarifPajak}% = ${formatHasil(v + pajak)}"; steps.add({"item": ekspresi, "rumus": ekspresi, "harga": v, "qty": tarifPajak, "jumlah": v + pajak}); entryBaru = true; }
  void _pencetTaxMin() { final v = _angkaLayar(); final bersih = v / (1 + tarifPajak / 100); layar = formatHasil(bersih); ekspresi = "${formatHasil(v)} TAX- ${tarifPajak}% = ${formatHasil(bersih)}"; steps.add({"item": ekspresi, "rumus": ekspresi, "harga": v, "qty": tarifPajak, "jumlah": bersih}); entryBaru = true; }
  void _setTax() { final v = _angkaLayar(); if (v >= 0 && v <= 100) { tarifPajak = v; ekspresi = "SET TAX = ${formatHasil(v)}%"; layar = formatHasil(v); entryBaru = true; } }
  void _pencetCost() { laciCost = _angkaLayar(); ekspresi = "COST = ${formatHasil(laciCost)}"; entryBaru = true; _hitungCSM(); }
  void _pencetSell() { laciSell = _angkaLayar(); ekspresi = "SELL = ${formatHasil(laciSell)}"; entryBaru = true; _hitungCSM(); }
  void _pencetMargin() { final v = _angkaLayar(); if (v > 0 && v < 100) { laciMargin = v; ekspresi = "MARGIN = ${formatHasil(v)}%"; entryBaru = true; _hitungCSM(); } }
  void _hitungCSM() {
    if (laciCost > 0 && laciMargin > 0 && laciMargin < 100 && laciSell == 0) { laciSell = laciCost / (1 - laciMargin / 100); layar = formatHasil(laciSell); ekspresi = "SELL = COST / (1 - MARGIN) = ${formatHasil(laciSell)}"; }
    else if (laciSell > 0 && laciMargin > 0 && laciMargin < 100 && laciCost == 0) { laciCost = laciSell * (1 - laciMargin / 100); layar = formatHasil(laciCost); ekspresi = "COST = SELL x (1 - MARGIN) = ${formatHasil(laciCost)}"; }
    else if (laciCost > 0 && laciSell > 0 && laciSell != laciCost) { laciMargin = (laciSell - laciCost) / laciSell * 100; layar = formatHasil(laciMargin); ekspresi = "MARGIN = (SELL - COST) / SELL = ${formatHasil(laciMargin)}%"; }
    if (laciCost > 0 || laciSell > 0 || laciMargin > 0) steps.add({"item": ekspresi, "rumus": ekspresi, "harga": laciCost, "qty": laciMargin, "jumlah": laciSell});
  }
  void _resetCSM() { laciCost = 0; laciSell = 0; laciMargin = 0; ekspresi = "COST / SELL / MARGIN direset"; }
  void _gantiRound() { modeRound = modeRound == "5/4" ? "CUT" : modeRound == "CUT" ? "F" : "5/4"; ekspresi = "ROUND = $modeRound"; layar = formatHasil(_angkaLayar()); }
  void _gantiAdd2() { modeAdd2 = !modeAdd2; ekspresi = modeAdd2 ? "ADD2 ON: ketik 123 -> 1.23" : "ADD2 OFF"; }
  double _terapkanAdd2(double v) => modeAdd2 ? v / 100 : v;
  double get totalCek { double t = 0; for (final s in steps) { t += (s["jumlah"] as num?)?.toDouble() ?? 0; } return t; }
  void _editStepCek(int i, double jumlahBaru) { if (i < 0 || i >= steps.length) return; steps[i]["jumlah"] = jumlahBaru; steps[i]["rumus"] = "${steps[i]["rumus"]} -> ${formatHasil(jumlahBaru)}"; layar = formatHasil(totalCek); ekspresi = "CEK total = ${formatHasil(totalCek)}"; }
  void _hapusStepCek(int i) { if (i < 0 || i >= steps.length) return; steps.removeAt(i); layar = formatHasil(totalCek); ekspresi = "CEK total = ${formatHasil(totalCek)}"; }

  void pencet(String t) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC") {
        // Casio AC: hapus SEMUA - layar, akumulator, operator, ekspresi, error
        layar = "0"; ekspresi = ""; akumulator = 0; angka1 = 0; opPending = ""; op = ""; entryBaru = true; adaError = false; lastOp = ""; lastAngka2 = 0; adaQtyHitung = false; qtyHitung = 1;
      }
      else if (t == "ON/C") {
        // Casio ON/C: hapus entry saja, akumulator + operator tetap
        layar = "0"; entryBaru = true; adaError = false;
      }
      else if (t == "OFF") { layar = "0"; ekspresi = ""; entryBaru = true; }
      else if (t == "PO") { poTerbuka = true; }
      else if (t == "LS") { bukaListLS(); }
      else if (t == "CEK") { bukaCek(); }
      else if (t == "TAX+") { _pencetTaxPlus(); }
      else if (t == "TAX-") { _pencetTaxMin(); }
      else if (t == "SET TAX") { _setTax(); }
      else if (t == "COST") { _pencetCost(); }
      else if (t == "SELL") { _pencetSell(); }
      else if (t == "MARGIN") { _pencetMargin(); }
      else if (t == "CSM CLR") { _resetCSM(); }
      else if (t == "ROUND") { _gantiRound(); }
      else if (t == "ADD2") { _gantiAdd2(); }
      else if (t == "GT") { layar = formatHasil(grandTotal); ekspresi = "GT = ${formatHasil(grandTotal)}"; entryBaru = true; }
      else if (t == "BEP") {
        if (hargaAcuan > 0) { layar = formatHasil(hargaAcuan * 1.1); ekspresi = "BEP = Acuan x 110%"; }
        else { layar = formatHasil((double.tryParse(_stripBacktick(layar)) ?? 0) + 120); }
        entryBaru = true;
      }
      else if (t == "M+") {
        // FIX BIRU - QTY BUKAN LAYAR / HASIL:
        // Kalau habis hitung 5 x 80000 = 400000, qty = 5 (qtyHitung), bukan 400000 (layar).
        // Kalau belum hitung apa-apa, qty = angka di layar.
        // HITAM FIX: qty = angka PERTAMA sebelum operator (qtyHitung), BUKAN layar (hasil).
        // Contoh: ketik 5 x 50`000 = 250`000, lalu M+ -> qty harus 5, bukan 250`000.
        // Kalau adaQtyHitung false tapi lastOp == "x" dan lastAngka2 != 0, qtyHitung masih angka pertama.
        // HITAM FIX FINAL — qty TIDAK PERNAH = hasil.
        // Di screenshot: 50`000 x 5 = 250`000, lalu M+ -> qty jadi 250`000 (hasil) x 50`000 = 12`500`000`000. SALAH.
        // Yang benar: qty dicari dari 3 sumber, urut prioritas:
        // 1. hasil / hargaBarang kalau habis dibagi (250`000 / 50`000 = 5) — ini yang paling akurat, berlaku untuk 5 x 50`000 MAUPUN 50`000 x 5.
        // 2. angka KEDUA (lastAngka2) kalau lastOp == "x" — untuk 50`000 x 5, angka kedua = 5.
        // 3. angka PERTAMA (qtyHitung) kalau 5 x 50`000 dan belum ada barang — angka pertama = 5.
        // 4. layar langsung kalau belum hitung apa-apa (ketik 5 lalu M+).
        int qtyPO;
        {
          final hasilLayar = _parseLayar();
          final hargaB = barangDipilih != null ? (int.tryParse("${barangDipilih!["harga1"]}") ?? 0) : 0;
          if (hargaB > 0 && hasilLayar > 0 && hasilLayar % hargaB == 0 && (hasilLayar / hargaB) >= 1 && (hasilLayar / hargaB) <= 100000) {
            qtyPO = (hasilLayar / hargaB).round();
          } else if (lastOp == "x" && lastAngka2 > 0 && lastAngka2 <= 100000 && lastAngka2 != hasilLayar) {
            // 50`000 x 5 -> lastAngka2 = 5. Tapi kalau 5 x 50`000, lastAngka2 = 50`000, jangan pakai ini — jatuh ke qtyHitung di bawah.
            qtyPO = (lastAngka2 <= 1000 && qtyHitung > 1000) ? lastAngka2.round() : (adaQtyHitung ? qtyHitung.round() : lastAngka2.round());
            if (qtyPO > 1000 && hargaB > 0) { qtyPO = qtyHitung.round(); }
          } else if (adaQtyHitung) {
            qtyPO = qtyHitung.round();
          } else {
            qtyPO = int.tryParse(_stripBacktick(layar)) ?? 1;
          }
        }
        final qtyAman = qtyPO <= 0 ? 1 : qtyPO;
        memori += double.tryParse(_stripBacktick(layar)) ?? 0;
        if (barangDipilih != null) {
          final harga = int.tryParse("${barangDipilih!["harga1"]}") ?? 0;
          final jumlah = qtyAman * harga; // SUBTOTAL PER ITEM = qty x harga satuan. Bukan qty = subtotal.
          final it = parseInputCepat("$qtyAman x ${barangDipilih!["nama"]} $harga");
          if (it != null) { ref.read(poProvider.notifier).tambahItem(it); }
          steps.add({"item": "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}", "rumus": "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}", "harga": harga, "qty": qtyAman, "jumlah": jumlah});
        }
        layar = "0"; entryBaru = true; adaQtyHitung = false;
      }
      else if (t == "M-") { memori -= double.tryParse(_stripBacktick(layar)) ?? 0; layar = "0"; entryBaru = true; }
      else if (t == "MRC") { layar = formatHasil(memori); memori = 0; entryBaru = true; }
      else if (t == "MR") { layar = formatHasil(memori); entryBaru = true; }
      else if (t == "MC") { memori = 0; layar = "0"; entryBaru = true; }
      else if (t == "MU") {
        // Casio MU (Mark-Up): Harga modal 100, MU 20 -> Harga jual = 100 / (1 - 20%) = 125
        // Di sini: layar = modal, MU = +10% BEP cepat. Pakai rumus MU beneran dengan 10%:
        final modal = double.tryParse(_stripBacktick(layar)) ?? 0;
        final jual = modal / (1 - 0.10);
        ekspresi = "MU 10% dari ${formatHasil(modal)}";
        layar = formatHasil(jual); entryBaru = true;
      }
      else if (t == "▶" || t == "⌫") {
        if (adaError) { layar = "0"; adaError = false; entryBaru = true; }
        else if (!entryBaru) { if (layar.length > 1) { layar = _groupBacktick(_stripBacktick(layar).substring(0, _stripBacktick(layar).length - 1)); if (layar.isEmpty || layar == "-") layar = "0"; } else { layar = "0"; } }
      }
      else if (["+", "-", "x", "÷", "/"].contains(t)) { _inputOperator(t); }
      else if (t == "=") { if (modeAdd2 && opPending.isEmpty) { layar = formatHasil(_terapkanAdd2(_angkaLayar())); } _inputSamaDengan(); }
      else if (t == "+/-") {
        if (adaError) return;
        if (layar.startsWith("-")) { layar = layar.substring(1); } else if (layar != "0") { layar = "-$layar"; }
      }
      else if (t == "%") { _inputPersen(); }
      else if (t == "GT") { layar = formatHasil(grandTotal); entryBaru = true; }
      else { _inputAngka(t); }
    });
  }
  void _dialogEditBarangLS(Map<String, dynamic> b, int idxAsli) {
    if (idxAsli < 0) { return; }
    final kodeC = TextEditingController(text: b["kode"].toString());
    final namaC = TextEditingController(text: b["nama"].toString());
    final katC = TextEditingController(text: b["kategori"].toString());
    final hargaC = TextEditingController(text: b["harga1"].toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Edit Barang (LS)"),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: kodeC, decoration: dec("Kode")),
        const SizedBox(height: 8),
        TextField(controller: namaC, decoration: dec("Nama")),
        const SizedBox(height: 8),
        TextField(controller: katC, decoration: dec("Kategori")),
        const SizedBox(height: 8),
        TextField(controller: hargaC, keyboardType: TextInputType.number, decoration: dec("Harga 1 (Harga per satuan dasar)")),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL")),
        ElevatedButton(onPressed: () {
          setState(() {
            daftarBarang[idxAsli] = {...daftarBarang[idxAsli], "kode": kodeC.text.trim(), "nama": namaC.text.trim(), "kategori": katC.text.trim(), "harga1": hargaC.text.trim()};
            if (barangDipilih != null && barangDipilih!["kode"].toString() == b["kode"].toString()) {
              barangDipilih = {"kode": kodeC.text.trim(), "nama": namaC.text.trim(), "kategori": katC.text.trim(), "harga1": hargaC.text.trim()};
            }
          });
          Navigator.pop(ctx);
        }, child: const Text("SIMPAN")),
      ],
    ));
  }

  void bukaListLS() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            final q = queryLS.toLowerCase();
            final filtered = daftarBarang.where((b) {
              if (q.isEmpty) { return true; }
              return b["nama"].toString().toLowerCase().contains(q) || b["kode"].toString().toLowerCase().contains(q) || b["kategori"].toString().toLowerCase().contains(q);
            }).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 12, right: 12, top: 12),
              child: SizedBox(height: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("LS - List Barang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Row(children: [TextButton(onPressed: () { Navigator.pop(ctx); bukaFormTambahBarang(); }, child: const Text("+ Tambah Barang")), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))])]),
                TextField(decoration: dec("Cari kode / nama / kategori..."), onChanged: (v) { setSheet(() { queryLS = v; }); setState(() { queryLS = v; }); }),
                const SizedBox(height: 8),
                Expanded(child: filtered.isEmpty ? const Center(child: Text("Belum ada barang. Tap + Tambah Barang.")) : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                  final b = filtered[i];
                  final aktif = barangDipilih != null && barangDipilih!["kode"] == b["kode"];
                  final satuanBarang = (b["satuanList"] as List?) ?? [];
                  final idxAsli = daftarBarang.indexWhere((e) => e["kode"].toString() == b["kode"].toString());
                  return InkWell(
                    onTap: () { setState(() { barangDipilih = {"kode": b["kode"].toString(), "nama": b["nama"].toString(), "kategori": b["kategori"].toString(), "harga1": b["harga1"].toString()}; }); Navigator.pop(ctx); },
                    child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: aktif ? Colors.green.shade100 : Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [CircleAvatar(radius: 16, child: Text(b["nama"].toString().isEmpty ? "?" : b["nama"].toString()[0].toLowerCase(), style: const TextStyle(fontSize: 14))), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("${b["nama"]}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), Text("${b["kode"]} • ${b["kategori"]} • ${b["satuan"] ?? "sak"}", style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)])), const SizedBox(width: 6), Text(formatRupiah(int.tryParse(b["harga1"].toString()) ?? 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), icon: const Icon(Icons.edit, size: 18, color: Colors.blue), tooltip: "Edit barang", onPressed: () { _dialogEditBarangLS(b, idxAsli); }),
                          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), icon: const Icon(Icons.delete, size: 18, color: Colors.red), tooltip: "Hapus barang", onPressed: () { setState(() { if (idxAsli >= 0) { daftarBarang.removeAt(idxAsli); } if (barangDipilih != null && barangDipilih!["kode"].toString() == b["kode"].toString()) { barangDipilih = null; } }); setSheet(() {}); }),
                        ]),
                        if (satuanBarang.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 4, children: satuanBarang.map<Widget>((x) { final m = Map<String, dynamic>.from(x as Map); final nom = double.tryParse(m["nominal"].toString()) ?? 0; final labelSatuan = (m["satuanBaru"]?.toString().isNotEmpty == true) ? m["satuanBaru"].toString() : m["satuan"].toString(); return ActionChip(label: Text("$labelSatuan - ${formatRupiah(nom.toInt())}", style: const TextStyle(fontSize: 10)), onPressed: () { setState(() { barangDipilih = {"kode": b["kode"].toString(), "nama": b["nama"].toString(), "kategori": b["kategori"].toString(), "harga1": nom.toInt().toString()}; layar = nom.toStringAsFixed(0); entryBaru = true; }); Navigator.pop(ctx); }); }).toList())],
                      ]),
                    ),
                  );
                })),
              ])),
            );
          },
        );
      },
    );
  }

  void bukaFormTambahBarang() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSheet) {
          return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 12, right: 12, top: 12),
            child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Tambah Barang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: TextField(controller: kodeCtrl, decoration: dec("Code *"))), const SizedBox(width: 8), Expanded(child: TextField(controller: namaCtrl, decoration: dec("Name *")))]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Category • dropdown + tambah/delete", style: TextStyle(fontSize: 11)), const SizedBox(height: 4), DropdownButtonFormField<String>(initialValue: kategoriPilih, decoration: dec("Kategori"), items: listKategori.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(), onChanged: (v) { if (v != null) { setSheet(() { kategoriPilih = v; }); } }), Row(children: [Expanded(child: TextField(controller: kategoriBaruCtrl, decoration: dec("Kategori baru"))), IconButton(icon: const Icon(Icons.add), onPressed: () { if (kategoriBaruCtrl.text.isNotEmpty) { setSheet(() { listKategori.add(kategoriBaruCtrl.text); kategoriPilih = kategoriBaruCtrl.text; kategoriBaruCtrl.clear(); }); } }), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setSheet(() { if (listKategori.length > 1) { listKategori.remove(kategoriPilih); kategoriPilih = listKategori.first; } }); })])])),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: unitCtrl, decoration: dec("Unit (Biru - auto sama)"), onChanged: (v) { final dasar = satuanList.firstWhere((x) => x.dasar == true, orElse: () => satuanList.first); dasar.namaCtrl.text = v; setSheet(() => refreshSemuaNominal()); })),
              ]),
              const SizedBox(height: 12),
              const Text("Harga 1 • Acuan 100%", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 4),
              TextField(controller: harga1Ctrl, keyboardType: TextInputType.number, decoration: dec("0"), onChanged: (v) => setSheet(() => refreshSemuaNominal())),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFFFF8C5), borderRadius: BorderRadius.circular(8)), child: const Text("Harga 1 ini yang jadi acuan prosentase 100%. Harga 2 dan 3 tidak perlu ditampilkan, input manual edit harga 1 menjadi harga 2 dan 3 sudah ada di PO.", style: TextStyle(fontSize: 11))),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Varian", style: TextStyle(fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => setSheet(() => varianCtrls.add(TextEditingController())), child: const Text("+Tambah Varian", style: TextStyle(fontSize: 11)))]),
              ...varianCtrls.asMap().entries.map((e) { return Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Expanded(child: TextField(controller: e.value, decoration: dec("Hitam"), onChanged: (v) => tambahKeDaftarSatuan(v))), IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setSheet(() { if (varianCtrls.length > 1) { varianCtrls.removeAt(e.key); } })) ])); }),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Satuan", style: TextStyle(fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => setSheet(() { satuanList.add(SatuanItem(satuan: unitCtrl.text, dasar: false, qty: "1", isi: "1", op: "÷", nominal: "0", satuanBaru: "")); }), child: const Text("+Tambah Satuan", style: TextStyle(fontSize: 11)))]),
              const Text("Qty + satuan BIRU, x/÷, isi + unit HIJAU = nominal. Baris bawah (merah) = INFO dari Harga 1, bukan dari field Rp.", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 6),
              ...satuanList.asMap().entries.map((e) {
                final it = e.value;
                return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Colors.white),
                  child: Column(children: [
                    Row(children: [
                      _AutoField(controller: it.qtyCtrl, hint: "1", angka: true, min: 44, max: 90, onChanged: (v) => setSheet(() { it.nominalManual = false; refreshNominal(it); })),
                      const SizedBox(width: 4),
                      _AutoField(controller: it.namaCtrl, hint: "satuan", min: 52, max: 140, onChanged: (v) { if (it.dasar) { unitCtrl.text = v; } setSheet(() => refreshNominal(it)); }),
                      const SizedBox(width: 4),
                      SizedBox(width: 36, height: 36, child: InkWell(onTap: () => setSheet(() { it.op = it.op == "x" ? "÷" : "x"; it.nominalManual = false; refreshNominal(it); }), borderRadius: BorderRadius.circular(18), child: Container(decoration: BoxDecoration(color: it.op == "÷" ? Colors.teal.shade100 : Colors.orange.shade100, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400)), child: Center(child: Text(it.op, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))))),
                      const SizedBox(width: 4),
                      _AutoField(controller: it.isiCtrl, hint: "isi", angka: true, min: 44, max: 90, onChanged: (v) => setSheet(() { it.nominalManual = false; refreshNominal(it); })),
                      const SizedBox(width: 4),
                      _AutoField(controller: it.satuanBaruCtrl, hint: "unit", min: 52, max: 140, onChanged: (v) { tambahKeDaftarSatuan(v); setSheet(() => refreshNominal(it)); }),
                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30), tooltip: it.dasar ? "Dasar" : "Jadikan dasar", icon: Icon(it.dasar ? Icons.check_circle : Icons.radio_button_unchecked, color: it.dasar ? Colors.green : Colors.grey, size: 22), onPressed: () => setSheet(() { for (var x in satuanList) { x.dasar = false; } it.dasar = true; syncUnitDariDasar(); refreshSemuaNominal(); })),
                      IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 26, minHeight: 26), onPressed: () => setSheet(() { if (satuanList.length > 1) { satuanList.removeAt(e.key); } })),
                    ]),
                    const SizedBox(height: 6),
                    // Field Rp = NOMINAL (boleh edit). Edit ini TIDAK mengubah baris INFO di bawahnya.
                    TextField(controller: it.nominalCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13), decoration: dec("nominal - harga jual per unit hijau (boleh edit)", prefix: "Rp "), onTap: () => it.nominalManual = true, onChanged: (v) { it.nominalManual = true; setSheet(() {}); }),
                    const SizedBox(height: 4),
                    // INFO MERAH - hanya Text, tidak bisa diedit, dihitung dari Harga 1
                    Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(6)), child: Text("INFO: ${teksRumusSatuan(it)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB71C1C)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () { final varian = varianCtrls.map((c) => c.text).join(", "); for (var c in varianCtrls) { tambahKeDaftarSatuan(c.text); } for (var x in satuanList) { tambahKeDaftarSatuan(x.satuanBaruCtrl.text); } setState(() { daftarBarang.add({"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''), "satuan": unitCtrl.text, "varian": varian, "satuanList": satuanList.map((x) => x.toMap()).toList()}); barangDipilih = {"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')}; }); Navigator.pop(ctx); }, child: const Text("Simpan Barang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 20),
            ])));
        });
      },
    );
  }
  // ===== BENTUK FISIK CASIO DJ-120 =====
  // Body krem, display hijau LCD 2 baris, tombol 3D: atas datar, bawah bayangan.
  // Tombol angka putih, operator abu, AC/ON biru, M+ hijau, = biru, BEP pink.
  Widget _chipFungsi(String label, Color bg) { return Padding(padding: const EdgeInsets.only(right: 6), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: const Size(0, 30)), onPressed: () => pencet(label), child: Text(label == "ROUND" ? "ROUND: $modeRound" : label == "ADD2" ? (modeAdd2 ? "ADD2: ON" : "ADD2: OFF") : label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))); }
  Widget tombol(String label, {Color? bg, Color? fg, bool besar = false}) {
    final isDown = tombolDitekan == label && tekanTombol;
    final baseColor = bg ?? Colors.white;
    return Expanded(child: Padding(padding: const EdgeInsets.all(4.0),
      child: GestureDetector(
        onTapDown: (_) => setState(() { tombolDitekan = label; tekanTombol = true; }),
        onTapUp: (_) { setState(() { tekanTombol = false; }); pencet(label); },
        onTapCancel: () => setState(() { tekanTombol = false; }),
        child: AnimatedContainer(duration: const Duration(milliseconds: 80), height: double.infinity,
          transform: Matrix4.translationValues(0, isDown ? 2.5 : 0, 0),
          decoration: BoxDecoration(color: isDown ? baseColor.withValues(alpha: 0.85) : baseColor, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black26, width: 0.8),
            boxShadow: isDown ? [] : [const BoxShadow(color: Color(0xFFB8A888), offset: Offset(0, 4), blurRadius: 0), const BoxShadow(color: Colors.white70, offset: Offset(0, -1), blurRadius: 0)],
          ),
          child: Center(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: besar ? 17 : 15, fontWeight: FontWeight.w800, color: fg ?? Colors.black, letterSpacing: 0.3))),
        ),
      ),
    ));
  }
  @override Widget build(BuildContext context) {
    final po = ref.watch(poProvider);
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    // SUBTOTAL FIX: hitung dari item PO yang sudah benar (qty x harga), bukan dari layar.
    // Kalau provider salah hitung, hitung ulang di sini sebagai pengaman:
    final subtotalAman = po.items.fold<double>(0, (a, it) => a + (it.qty * it.hargaSatuan));
    final totalAman = subtotalAman;
    final headerKalkulator = Container(color: const Color(0xFF1A1A1A), padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("BASKORO WINGCHUN", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), GestureDetector(onTap: dialogBabe, child: const Text("BABE.INFO - dialog kalkulasi", style: TextStyle(color: Colors.white70, fontSize: 9, decoration: TextDecoration.underline)))]),
        const SizedBox(height: 6),
        // Panel solar Casio + label DJ-120
        Row(children: [Expanded(child: Container(height: 14, decoration: BoxDecoration(color: const Color(0xFF3A2A1A), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black54)), child: Row(children: List.generate(5, (i) => Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2), color: const Color(0xFF5A3D22))))))), const SizedBox(width: 8), const Text("DJ-120  •  12 DIGIT", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFDDE8D0), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)),
          child: Column(children: [
            // Baris 1 display Casio: ekspresi (misal "5 x 80`000") - kecil, kanan
            SizedBox(width: double.infinity, child: Text(ekspresi.isEmpty ? " " : ekspresi, style: const TextStyle(fontSize: 12, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
            // Baris 2: Acuan (kiri, kecil) + Layar utama (kanan, besar)
            Row(children: [Expanded(child: Text(teksAcuan(), style: const TextStyle(fontSize: 12, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), Flexible(child: Text(layar, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: adaError ? Colors.red : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right))]),
            const SizedBox(height: 2),
            Row(children: [Expanded(child: Text(barangDipilih == null ? "Pilih barang via LS" : "${barangDipilih!["nama"]} • ${barangDipilih!["kategori"]}", style: const TextStyle(fontSize: 9, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), Text(teksSaran(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: warnaSaran()))]),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 2, child: InkWell(onTap: () => setState(() { modeHitung = modeHitung == "PEMBULATAN" ? "ORIGINAL" : "PEMBULATAN"; }), child: Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)), child: Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: const Text("5/4", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))), const SizedBox(width: 4), Expanded(child: Text(modeHitung, style: const TextStyle(color: Colors.white, fontSize: 9), overflow: TextOverflow.ellipsis))])))),
          const SizedBox(width: 4),
          Expanded(child: SizedBox(height: 32, child: SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text("0", style: TextStyle(fontSize: 9))), ButtonSegment(value: 2, label: Text("2", style: TextStyle(fontSize: 9))), ButtonSegment(value: 3, label: Text("3", style: TextStyle(fontSize: 9)))], selected: {desimal}, onSelectionChanged: (s) => setState(() { desimal = s.first; })))),
          const SizedBox(width: 4),
          Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: () {}, style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 10)), child: const Text("Kirim WA")))),
          const SizedBox(width: 4),
          Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 9), backgroundColor: Colors.white), child: const Text("Nota")))),
        ]),
      ]),
    );
    return Scaffold(backgroundColor: const Color(0xFFE8E0C8),
      body: SafeArea(child: Column(children: [
        headerKalkulator,
        if (poTerbuka)
          Container(height: poTinggi, child: Container(color: const Color(0xFF2E2E2E), padding: const EdgeInsets.all(12),
            child: Column(children: [
              // PUTIH: Handle tarik — tap panah = kecil/besar, drag = geser tinggi. Layar kalkulator di atas TIDAK ketutup.
              GestureDetector(
                onTap: () => setState(() { poTinggi = poTinggi > 250 ? 180 : 380; }),
                onVerticalDragUpdate: (d) => setState(() { poTinggi = (poTinggi + d.delta.dy).clamp(160.0, 480.0); }),
                child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 2), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 22), const Text("Geser / tap untuk kecil-besar — kalkulator tetap kelihatan", style: TextStyle(color: Colors.white70, fontSize: 10))])),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(nomorPOSeries, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const Text("PO - Daftar Item", style: TextStyle(color: Colors.white70, fontSize: 11))]), IconButton(icon: const Icon(Icons.close, color: Colors.white), tooltip: "Tutup PO, balik ke keypad", onPressed: () => setState(() { poTerbuka = false; }))]),
              const SizedBox(height: 6),
              Expanded(child: po.items.isEmpty ? const Center(child: Text("Belum ada item - pencet LS pilih barang, lalu ketik qty, lalu M+", style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)) : ListView.builder(itemCount: po.items.length, itemBuilder: (_, i) {
                // FIX PO ROW: 2 baris, qty TIDAK pernah = subtotal. Baris 2 = rumus lengkap.
                final it = po.items[i];
                final jumlah = it.qty * it.hargaSatuan;
                return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("${i + 1}. ${it.namaBarang}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      // HITAM: Subtotal per item = qty op harga op bilangan op bilangan. Di sini op = x, bilangan = harga.
                      // Rumus ditampilkan lengkap, jumlah TIDAK pernah qty = hasil x harga lagi.
                      Text("${it.qty}  x  ${formatRupiah(it.hargaSatuan)}  =  ${formatRupiah(jumlah.toInt())}", style: const TextStyle(fontSize: 12)),
                      Text("Subtotal item = ${formatRupiah(jumlah.toInt())}", style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    ])),
                    IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => ref.read(poProvider.notifier).hapusItem(i)),
                  ]),
                );
              })),
              // FIX FOOTER: Column 2 baris, tidak numpuk. Subtotal = Σ(qty x harga). Total = Subtotal.
              Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Subtotal: ${formatRupiah(subtotalAman.toInt())}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text("Total = Jumlah Subtotal: ${formatRupiah(totalAman.toInt())}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
              ),
            ]),
          ))
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), color: Colors.grey.shade100, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _chipFungsi("TAX+", Colors.teal), _chipFungsi("TAX-", Colors.teal), _chipFungsi("SET TAX", Colors.teal.shade100),
            _chipFungsi("COST", Colors.indigo), _chipFungsi("SELL", Colors.indigo), _chipFungsi("MARGIN", Colors.indigo), _chipFungsi("CSM CLR", Colors.grey.shade300),
            _chipFungsi("ROUND", Colors.amber.shade100), _chipFungsi("ADD2", Colors.amber.shade100), _chipFungsi("GT", Colors.black),
          ]))),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
            child: Column(children: [
              Expanded(child: Row(children: [tombol("AC", bg: Colors.blue.shade400, fg: Colors.white), tombol("MRC", bg: Colors.grey.shade400), tombol("M-", bg: Colors.grey.shade400), tombol("M+", bg: Colors.green, fg: Colors.white, besar: true), tombol("LS", bg: Colors.orange.shade100, besar: true), tombol("CEK", bg: Colors.black, fg: Colors.white), tombol("BEP", bg: Colors.pink, fg: Colors.white)])),
              Expanded(child: Row(children: [tombol("OFF", bg: Colors.blue.shade400, fg: Colors.white), tombol("7"), tombol("8"), tombol("9"), tombol("▶", bg: Colors.grey.shade300), tombol("MU", bg: Colors.grey.shade300), tombol("MC", bg: Colors.grey.shade300)])),
              Expanded(child: Row(children: [tombol("%", bg: Colors.grey.shade300), tombol("4"), tombol("5"), tombol("6"), tombol("-", bg: Colors.grey.shade300), tombol("÷", bg: Colors.grey.shade300), tombol("MR", bg: Colors.grey.shade300)])),
              Expanded(child: Row(children: [tombol("+/-", bg: Colors.grey.shade300), tombol("1"), tombol("2"), tombol("3"), tombol("+", bg: Colors.grey.shade300), tombol("x", bg: Colors.grey.shade300), tombol("PO", bg: Colors.teal, fg: Colors.white)])),
              Expanded(child: Row(children: [tombol("ON/C", bg: Colors.blue.shade400, fg: Colors.white), tombol("0"), tombol("00"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true), tombol("M+", bg: Colors.green, fg: Colors.white), tombol("⌫", bg: Colors.grey.shade300)])),
            ]),
          )),
      ])),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/formatter.dart';
import 'po_provider.dart';
import '../../core/po_database.dart';
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
  // ===== DB (sqflite): PO + log step + cache pelanggan awet, bukan cuma memori =====
  late final PoDatabase _db;
  bool _dbSiap = false;
  @override
  void initState() {
    super.initState();
    _db = PoDatabase();
    _muatDariDrift();
  }
  @override
  void dispose() {
    pelangganCtrl.dispose();
    _db.close();
    super.dispose();
  }
  Future<void> _muatDariDrift() async {
    try {
      final pos = await _db.muatSemuaPo();
      final log = await _db.muatLogStep();
      final pel = await _db.muatPelanggan();
      final alias = await _db.muatAliasCopas();
      if (!mounted) return;
      setState(() {
        final idsAda = daftarPO.map((e) => e["id"]).toSet();
        for (final p in pos) {
          if (!idsAda.contains(p["id"])) daftarPO.add(p);
        }
        final idsRiw = riwayatPO.map((e) => e["id"]).toSet();
        for (final r in log) {
          if (!idsRiw.contains(r["id"])) riwayatPO.add(r);
        }
        cachePelanggan = pel;
        aliasCopas = alias;
        var maks = 0;
        for (final p in daftarPO) {
          final n = int.tryParse("${p["nomor"]}".replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          if (n > maks) maks = n;
        }
        if (maks > 0) nomorPO = maks + 1;
        _dbSiap = true;
      });
    } catch (_) {
      // DB belum siap / pertama kali jalan: pakai memori dulu.
    }
  }
  // Tulis PO yang sedang dibuka (revisi / baru) ke DB. Dipanggil habis simpan di CEK.
  void _tulisPOAktifKeDrift() {
    if (poRevisiIndex == null || poRevisiIndex! < 0 || poRevisiIndex! >= daftarPO.length) return;
    final p = daftarPO[poRevisiIndex!];
    final items = (p["items"] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final total = (p["total"] as num?)?.toDouble() ?? 0;
    final pelanggan = "${p["pelanggan"] ?? ""}";
    final id = p["id"];
    if (id is int) {
      _db.updatePo(id: id, tanggal: "${p["tanggal"]}", pelanggan: pelanggan, total: total, items: items);
    } else {
      _db.simpanPoBaru(nomor: "${p["nomor"]}", tanggal: "${p["tanggal"]}", pelanggan: pelanggan, total: total, items: items).then((idBaru) {
        if (mounted) setState(() { p["id"] = idBaru; });
      });
    }
  }
  void _hapusPO(int i) {
    if (i < 0 || i >= daftarPO.length) return;
    final id = daftarPO[i]["id"];
    if (id is int) _db.hapusPo(id);
    setState(() {
      final sedangRevisi = poRevisiIndex == i;
      daftarPO.removeAt(i);
      if (sedangRevisi) {
        poRevisiIndex = null;
        steps.clear();
      } else if (poRevisiIndex != null && poRevisiIndex! > i) {
        poRevisiIndex = poRevisiIndex! - 1;
      }
    });
  }

  // ===== MESIN CASIO - STATE ASLI, BUKAN LAYAR SAJA =====
  // layar = angka yang sedang diketik / hasil terakhir (entry)
  // akumulator = angka pertama yang disimpan saat pencet operator (Casio: operand 1)
  // opPending = operator yang menunggu operand 2
  // ekspresi = baris atas display, misal "5 x 80`000"
  // entryBaru = true berarti ketikan berikutnya ganti layar, bukan nempel
  // qtyHitung = angka SEBELUM operator (untuk M+ / PO). BUKAN hasil =.
  String layar = "0";
  // operanSiap = layar BOLEH dipakai sbg operan kiri. false kalau layar cuma 0 sisa M+/ON/C/MC.
  bool operanSiap = false;
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
  int nomorPO = 1;
  String get nomorPOSeries => "PO B\u2022WC-${nomorPO.toString().padLeft(3, '0')}B\u2022I";
  double poTinggi = 300;
  // ===== CEK = PO + PO tersimpan + Riwayat = log step =====
  String queryPO = "";
  String queryRiwayat = "";
  final List<Map<String, dynamic>> daftarPO = [];
  final List<Map<String, dynamic>> riwayatPO = [];
  int? poRevisiIndex;
  // ===== Pelanggan (cache nama untuk autocomplete) =====
  final pelangganCtrl = TextEditingController();
  List<String> cachePelanggan = [];
  Map<String, String> aliasCopas = {}; // nama copasan -> kode barang LS (dipelajari dari pilih manual)
  bool tampilSaranPelanggan = false;
  List<String> _saranPelanggan(String prefix) {
    final q = prefix.trim().toLowerCase();
    if (q.isEmpty) return cachePelanggan.take(5).toList();
    return cachePelanggan.where((n) => n.toLowerCase().contains(q)).take(5).toList();
  }
  void _simpanPelangganCache(String nama) {
    final v = nama.trim();
    if (v.isEmpty) return;
    cachePelanggan.removeWhere((n) => n.toLowerCase() == v.toLowerCase());
    cachePelanggan.insert(0, v);
    _db.simpanPelanggan(v);
  }
  // Nama dinormalkan untuk pencocokan: huruf kecil, tanpa spasi/tanda baca.
  // "Bekel Putih" dan "bekelputih" jadi sama: "bekelputih".
  String _normalNama(String nama) => nama.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  String _tanggalSimpanPO() {
    final skrg = DateTime.now();
    return "${skrg.day.toString().padLeft(2, '0')}/${skrg.month.toString().padLeft(2, '0')}/${skrg.year} ${skrg.hour.toString().padLeft(2, '0')}:${skrg.minute.toString().padLeft(2, '0')}";
  }
  String _tanggalLogStep() {
    final skrg = DateTime.now();
    return "${skrg.hour.toString().padLeft(2, '0')}:${skrg.minute.toString().padLeft(2, '0')} ${skrg.day.toString().padLeft(2, '0')}/${skrg.month.toString().padLeft(2, '0')}";
  }
  // Field nama pelanggan + saran autocomplete. Dipakai di CEK, sheet Cari PO, dan panel PO.
  Widget _fieldPelanggan(void Function(void Function()) setSheet, {bool diPanel = false}) {
    final saran = _saranPelanggan(pelangganCtrl.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: pelangganCtrl, style: TextStyle(color: diPanel ? Colors.white : Colors.black, fontSize: 13), decoration: dec("👤 Nama pelanggan — ketik, pilih saran...").copyWith(hintStyle: TextStyle(color: diPanel ? Colors.white54 : null)),
        onChanged: (v) { setSheet(() { tampilSaranPelanggan = true; }); },
        onTap: () { setSheet(() { tampilSaranPelanggan = true; }); }),
      if (tampilSaranPelanggan && saran.isNotEmpty)
        Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: Wrap(spacing: 6, runSpacing: 6, children: saran.map((n) => ActionChip(label: Text(n, style: const TextStyle(fontSize: 12)), onPressed: () { setSheet(() { pelangganCtrl.text = n; tampilSaranPelanggan = false; }); })).toList())),
    ]);
  }

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
    if (v.isNaN || v.isInfinite) {
      return "E";
    }
    String mentah;
    if (modeHitung == "ORIGINAL") {
      mentah = v.toStringAsFixed(desimal);
    } else if (modeRound == "CUT") {
      final p = desimal == 0 ? 1.0 : _pow10(desimal);
      final potong = (v * p).truncate() / p;
      mentah = desimal == 0 ? potong.round().toString() : potong.toStringAsFixed(desimal);
    } else if (modeRound == "F") {
      mentah = _buangNolBelakang(v.toStringAsFixed(6));
    } else if (desimal == 0) {
      mentah = v.round().toString();
    } else {
      mentah = v.toStringAsFixed(desimal);
    }
    return _groupBacktick(mentah);
  }
  double _pow10(int n) {
    double r = 1;
    for (int i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
  String _buangNolBelakang(String s) {
    if (!s.contains('.')) {
      return s;
    }
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s.isEmpty ? "0" : s;
  }
  // Operasi dasar Casio: a op b. Bagi 0 -> error, bukan 0 diam-diam.
  double? hitungDasar(double a, String o, double b) {
    if (o == "+") {
      return a + b;
    }
    if (o == "-") {
      return a - b;
    }
    if (o == "x") {
      return a * b;
    }
    if (o == "÷" || o == "/") {
      if (b == 0) {
        return null;
      }
      return a / b;
    }
    return b;
  }
  // ===== RUMUS SATUAN - DARI HARGA 1, BUKAN DARI NOMINAL =====
  // SATUAN: bilangan kiri BEBAS (20 lusin ÷ 12 duz = 83`333 itu BENAR).
  // Yang auto-ngikut unit dasar (biru) hanya UNIT kirinya — lewat syncSatuanKiri().
  // KANAN: isi + satuan baru (hijau) yang akan masuk list satuan.
  void syncSatuanKiri() {
    for (var x in satuanList) {
      x.namaCtrl.text = unitCtrl.text;
    }
  }
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
    // Unit dasar (biru) dipegang unitCtrl. Semua baris kiri ikut unitCtrl.
    syncSatuanKiri();
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
    // INFO dibulatkan (.round) SAMA seperti field Rp nominal — kemarin INFO pakai .toInt (potong)
    // jadi INFO 4`166 padahal field Rp 4167.
    if (s.dasar) return "$qty $satuanBiru = ${formatRupiah(infoHasil.round())}  (info)";
    return "$qty $satuanBiru ${s.op} $isi $unitHijau = ${formatRupiah(infoHasil.round())}  (info)";
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
    // CEK = PO. Riwayat = log step, dibuka lewat tombol RIW / ikon riwayat di tiap step.
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) {
        final q = queryPO.toLowerCase();
        final hasilCariPO = daftarPO.where((p) {
          if (q.isEmpty) return true;
          final items = (p["items"] as List);
          final namaItems = items.map((e) => "${(e as Map)["item"]}").join(" ").toLowerCase();
          return "${p["nomor"]}".toLowerCase().contains(q) || "${p["pelanggan"] ?? ""}".toLowerCase().contains(q) || namaItems.contains(q) || "${p["tanggal"]}".toLowerCase().contains(q);
        }).toList();
        return Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
          child: SizedBox(height: 580, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("CEK - PO", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: Text(nomorPOSeries, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
              ]),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 8),
            _fieldPelanggan(setSheet),
            const SizedBox(height: 4),
            Text("Tanggal simpan: ${_tanggalSimpanPO()}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(decoration: dec("🔎 Cari PO tersimpan — nomor / pelanggan / nama barang / tanggal..."), onChanged: (v) { setSheet(() { queryPO = v; }); setState(() { queryPO = v; }); }),
            const SizedBox(height: 6),
            if (daftarPO.isNotEmpty)
              SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
                const Padding(padding: EdgeInsets.only(right: 6, top: 10), child: Text("PO tersimpan:", style: TextStyle(fontSize: 11, color: Colors.grey))),
                ...hasilCariPO.map((p) {
                  final idx = daftarPO.indexOf(p);
                  return Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text("${p["nomor"]}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), onPressed: () { Navigator.pop(ctx); _detailPO(idx); }));
                }),
              ])),
            Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: Text("TRACKING PO: TOTAL = ${formatHasil(totalCek)}  |  GT = ${formatHasil(grandTotal)}  |  TAX = ${formatHasil(tarifPajak)}%  |  STEP = ${steps.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
            const SizedBox(height: 8),
            if (steps.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text("Belum ada step. Pencet = atau M+ dulu, lalu edit di sini.")),
            Expanded(child: ListView.builder(itemCount: steps.length, itemBuilder: (_, i) {
              final st = steps[i];
              final hargaC = TextEditingController(text: "${(st["harga"] as num?)?.toDouble() ?? 0}");
              final qtyC = TextEditingController(text: "${(st["qty"] as num?)?.toDouble() ?? 0}");
              final jumlahC = TextEditingController(text: "${(st["jumlah"] as num?)?.toDouble() ?? 0}");
              return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(onTap: () => _bukaPilihBarangUntukStep(i, setSheet), child: Row(children: [
                    const Icon(Icons.edit, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Expanded(child: Text("${i + 1}. ${st["item"]}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    const Text("tap ganti barang", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ])),
                  const SizedBox(height: 2),
                  Text("${st["rumus"] ?? ""}", style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: TextField(controller: hargaC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Harga", isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 6),
                    Expanded(child: TextField(controller: qtyC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty", isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 6),
                    Expanded(child: TextField(controller: jumlahC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Jumlah", isDense: true, border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Text("Subtotal = ${formatRupiah(((st["jumlah"] as num?)?.toDouble() ?? 0).toInt())}", style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.check_circle, color: Colors.green, size: 26), tooltip: "Simpan step ini", onPressed: () {
                      final h = double.tryParse(hargaC.text) ?? 0;
                      final q = double.tryParse(qtyC.text) ?? 0;
                      final j = double.tryParse(jumlahC.text) ?? 0;
                      setSheet(() { _simpanStepCEK(i, h, q, j); });
                      setState(() {});
                    }),
                    IconButton(icon: const Icon(Icons.history, color: Colors.blue, size: 24), tooltip: "Riwayat — Log Step", onPressed: () { _bukaRiwayat(); }),
                  ]),
                ]));
            })),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.save, size: 18), label: Text(poRevisiIndex != null ? "Simpan — Update ${daftarPO[poRevisiIndex!]["nomor"]}" : "Simpan PO — $nomorPOSeries"), onPressed: () { setSheet(() { _simpanPOdariCEK(); }); setState(() {}); })),
              const SizedBox(width: 8),
              TextButton(onPressed: () { setSheet(() { steps.clear(); poRevisiIndex = null; nomorPO++; layar = "0"; ekspresi = ""; }); setState(() {}); }, child: const Text("PO Baru")),
            ]),
          ])));
      }),
    );
  }
  // ===== CPS — Copas Teks jadi Step =====
  // Tempel teks WA/chat -> tiap baris jadi 1 step CEK (masih bisa diedit di CPS, di CEK, sebelum Simpan PO).
  // Nama dicocokkan ke list LS: 1) alias yang pernah dipilih manual, 2) nama mengandung (bukan harus sama persis).
  void _bukaCPS() {
    final tempelC = TextEditingController();
    List<Map<String, dynamic>> baris = [];

    // Rapikan angka: titik ribuan dibuang ("50.000" -> "50000"), koma desimal aman ("2,5").
    String _rapikanAngka(String teks) {
      final buf = StringBuffer();
      for (var i = 0; i < teks.length; i++) {
        final c = teks[i];
        if (c == '.' && i > 0 && i + 4 <= teks.length) {
          final sebelum = teks[i - 1];
          final tiga = teks.substring(i + 1, i + 4);
          final sesudah = i + 4 < teks.length ? teks[i + 4] : '';
          final tigaDigit = RegExp(r'^[0-9]{3}$').hasMatch(tiga);
          final sebelumDigit = RegExp(r'^[0-9]$').hasMatch(sebelum);
          final sesudahBukanDigit = sesudah.isEmpty || !RegExp(r'^[0-9]$').hasMatch(sesudah);
          if (sebelumDigit && tigaDigit && sesudahBukanDigit) continue; // titik ribuan, buang
        }
        buf.write(c);
      }
      return buf.toString();
    }

    // Cari barang di list LS: 1) alias yang pernah dipilih manual, 2) nama mengandung (bukan harus sama persis).
    Map<String, dynamic>? _cocokMaster(String nama) {
      final kunci = _normalNama(nama);
      if (kunci.isEmpty) return null;
      final kodeAlias = aliasCopas[kunci];
      if (kodeAlias != null) {
        for (final b in daftarBarang) {
          if ("${b["kode"]}" == kodeAlias) return b;
        }
      }
      for (final b in daftarBarang) {
        final nb = _normalNama("${b["nama"]}");
        if (nb.isEmpty) continue;
        if (kunci.contains(nb) || nb.contains(kunci)) return b;
      }
      return null;
    }

    // 1 baris teks -> {nama, qty, harga, cocok, controller...}.
    Map<String, dynamic> _parseSatu(String mentah) {
      final teks = _rapikanAngka(mentah.replaceAll('`', '').replaceAll(RegExp(r'[Rr][Pp]\s*'), ''));
      final nums = RegExp(r'[0-9]+(?:[.,][0-9]+)?')
          .allMatches(teks)
          .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0)
          .toList();
      var nama = teks
          .replaceAll(RegExp(r'[0-9]+(?:[.,][0-9]+)?'), ' ')
          .replaceAll(RegExp(r'[xX×*/]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (nama.isEmpty) nama = "Barang";
      final cocok = _cocokMaster(nama);
      double qty;
      double harga;
      if (nums.length >= 2) {
        qty = nums[0];
        harga = nums[1];
      } else if (nums.length == 1 && nums[0] > 1000) {
        qty = 1; // 1 angka besar = harga, bukan qty ("bekel 50000")
        harga = nums[0];
      } else {
        qty = nums.isEmpty ? 1 : nums[0];
        harga = 0;
      }
      if (harga == 0 && cocok != null) harga = double.tryParse("${cocok["harga1"]}") ?? 0;
      final r = {"nama": nama, "qty": qty, "harga": harga, "cocok": cocok};
      r["namaC"] = TextEditingController(text: nama);
      r["qtyC"] = TextEditingController(text: qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2));
      r["hargaC"] = TextEditingController(text: harga.toStringAsFixed(harga % 1 == 0 ? 0 : 2));
      return r;
    }

    // Pilih barang dari list LS untuk 1 baris (ganti yang cocok). Pilihan ini diingat sebagai alias.
    void _pilihMaster(Map<String, dynamic> r, void Function(void Function()) setSheet) {
      showModalBottomSheet(
        context: context,
        builder: (ctx2) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(12), child: Text("Pilih barang dari list LS", style: TextStyle(fontWeight: FontWeight.bold))),
            SizedBox(height: 320, child: ListView.builder(itemCount: daftarBarang.length, itemBuilder: (_, j) {
              final b = daftarBarang[j];
              return ListTile(
                title: Text("${b["nama"]}"),
                subtitle: Text("${b["kode"]} • ${formatRupiah(int.tryParse("${b["harga1"]}") ?? 0)}"),
                onTap: () {
                  Navigator.pop(ctx2);
                  setSheet(() {
                    // Ingat pasangan ini: lain kali nama copasan yang sama langsung cocok otomatis.
                    _db.simpanAliasCopas(namaCopas: "${r["nama"]}", kodeBarang: "${b["kode"]}");
                    aliasCopas[_normalNama("${r["nama"]}")] = "${b["kode"]}";
                    r["cocok"] = b;
                    r["nama"] = "${b["nama"]}";
                    (r["namaC"] as TextEditingController).text = "${b["nama"]}";
                    final h = double.tryParse("${b["harga1"]}") ?? 0;
                    r["harga"] = h;
                    (r["hargaC"] as TextEditingController).text = h.toStringAsFixed(0);
                  });
                },
              );
            })),
          ]),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) {
        return Padding(
          padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
          child: SizedBox(height: 580, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("CPS — Copas Teks jadi Step", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const Text("1 baris = 1 barang. Angka pertama = qty, angka kedua = harga. Nama dicocokkan ke list LS.", style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(controller: tempelC, maxLines: 4, decoration: dec("Tempel di sini...\nContoh:\nbekel 20\nsemen 5 x 50000\npasir 2")),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.paste, size: 18),
                label: const Text("Tempel Clipboard"),
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  final t = d?.text ?? "";
                  if (t.isNotEmpty) setSheet(() { tempelC.text = t; });
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text("Urai jadi Baris"),
                onPressed: () {
                  setSheet(() {
                    baris = tempelC.text.split('\n').where((l) => l.trim().isNotEmpty).map((l) => _parseSatu(l)).toList();
                  });
                },
              )),
            ]),
            const SizedBox(height: 8),
            Expanded(child: baris.isEmpty
                ? const Center(child: Text("Belum ada baris. Tempel teks lalu pencet Urai jadi Baris.", textAlign: TextAlign.center))
                : ListView.builder(itemCount: baris.length, itemBuilder: (_, i) {
                    final r = baris[i];
                    final cocok = r["cocok"] as Map<String, dynamic>?;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: TextField(controller: r["namaC"] as TextEditingController, decoration: const InputDecoration(labelText: "Nama barang", isDense: true, border: OutlineInputBorder()), onChanged: (v) { r["nama"] = v; })),
                          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), tooltip: "Hapus baris ini", onPressed: () => setSheet(() { baris.removeAt(i); })),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: TextField(controller: r["qtyC"] as TextEditingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty", isDense: true, border: OutlineInputBorder()), onChanged: (v) { r["qty"] = double.tryParse(v) ?? 0; setSheet(() {}); })),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: r["hargaC"] as TextEditingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Harga / nominal", isDense: true, border: OutlineInputBorder()), onChanged: (v) { r["harga"] = double.tryParse(v) ?? 0; setSheet(() {}); })),
                        ]),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          if (cocok != null)
                            ActionChip(label: Text("Cocok: ${cocok["nama"]} — ${formatRupiah(int.tryParse("${cocok["harga1"]}") ?? 0)}", style: const TextStyle(fontSize: 11)), onPressed: () => _pilihMaster(r, setSheet))
                          else
                            ActionChip(label: const Text("Barang baru — tap pilih dari list LS", style: TextStyle(fontSize: 11)), onPressed: () => _pilihMaster(r, setSheet)),
                        ]),
                        const SizedBox(height: 4),
                        Text("Subtotal = ${formatRupiah((((r["qty"] as num?)?.toDouble() ?? 0) * ((r["harga"] as num?)?.toDouble() ?? 0)).toInt())}", style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      ]),
                    );
                  })),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: Text("Masukkan ${baris.length} Baris ke CEK"),
              onPressed: baris.isEmpty ? null : () {
                final jumlahBaris = baris.length;
                for (final r in baris) {
                  final nama = "${r["nama"]}".trim().isEmpty ? "Barang" : "${r["nama"]}".trim();
                  final qty = (r["qty"] as num?)?.toDouble() ?? 0;
                  final harga = (r["harga"] as num?)?.toDouble() ?? 0;
                  final jumlah = qty * harga;
                  _tambahStep({"item": nama, "rumus": "$nama : ${formatHasil(qty)} x ${formatRupiah(harga.toInt())} = ${formatRupiah(jumlah.toInt())}", "harga": harga, "qty": qty, "jumlah": jumlah});
                }
                Navigator.pop(ctx);
                setState(() {
                  layar = formatHasil(totalCek);
                  ekspresi = "CPS: $jumlahBaris step masuk CEK";
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$jumlahBaris baris masuk CEK — edit di CEK sebelum Simpan PO.")));
                bukaCek();
              },
            )),
          ])));
      }),
    );
  }

  void _inputAngka(String t) {
    if (adaError) { layar = "0"; ekspresi = ""; akumulator = 0; opPending = ""; op = ""; adaError = false; entryBaru = true; }
    layar = _stripBacktick(layar); // layar mungkin sudah berisi ` dari formatHasil sebelumnya
    if (entryBaru) { layar = (t == ".") ? "0." : t; entryBaru = false; adaQtyHitung = false; }
    else {
      if (t == "." && layar.contains(".")) return;
      if (layar.replaceAll("-", "").replaceAll(".", "").length >= 12) return; // Casio 12 digit, hitung digit saja, bukan `
      if (layar == "0" && t != ".") { layar = t; }
      else if (layar == "-0" && t != ".") { layar = "-$t"; }
      else { layar += t; }
    }
    layar = _groupBacktick(layar); // langsung tampil 1`000 saat ketik, bukan nunggu =
    operanSiap = true;
  }
  void _inputOperator(String t) {
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    // ATURAN 1 — operator berulang (7 + - x): HANYA ganti operator, layar tetap, akumulator tidak dihitung ulang.
    if (opPending.isNotEmpty && entryBaru) {
      opPending = t; op = t;
      ekspresi = "${formatHasil(akumulator)} $t";
      entryBaru = true; operanSiap = false;
      return;
    }
    // ATURAN 2 — operator tertunda + angka baru diketik: hitung dulu (Casio chain).
    if (opPending.isNotEmpty && !entryBaru) {
      final h = hitungDasar(akumulator, opPending, cur);
      if (h == null) { layar = "E"; adaError = true; return; }
      akumulator = h; angka1 = h; layar = formatHasil(h);
      operanSiap = true;
    }
    // ATURAN 3 — belum ada operator: operan kiri dari layar HANYA kalau operanSiap. Kalau layar cuma 0 sisa M+/ON/C, akumulator dibiarkan.
    else if (opPending.isEmpty) {
      if (operanSiap) {
        akumulator = cur; angka1 = cur;
        qtyHitung = cur; adaQtyHitung = true;
      }
    }
    opPending = t; op = t;
    ekspresi = "${formatHasil(akumulator)} $t";
    entryBaru = true; operanSiap = false;
  }
  void _inputSamaDengan() {
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    double a, b; String o;
    if (opPending.isNotEmpty) {
      a = akumulator;
      b = entryBaru ? akumulator : cur; // 7 + = -> 14 (Casio). Jangan pakai layar yg bisa 0 sisa M+/ON/C.
      o = opPending;
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
    _tambahStep({"item": ekspresi, "rumus": ekspresi, "harga": a, "qty": b, "jumlah": h});
    grandTotal += h;
    akumulator = h; angka1 = h; layar = formatHasil(h);
    opPending = ""; op = "";
    entryBaru = true; operanSiap = true;
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
    _tambahStep({"item": ekspresi, "rumus": ekspresi, "harga": akumulator, "qty": cur, "jumlah": h});
    layar = formatHasil(h); akumulator = h; angka1 = h; opPending = ""; op = ""; entryBaru = true; operanSiap = true;
  }
  // ===== TAX / CSM / ADD2 / ROUND — BARU, LACI TERPISAH =====
  double _angkaLayar() => _parseLayar();
  void _pencetTaxPlus() { final v = _angkaLayar(); final pajak = v * tarifPajak / 100; layar = formatHasil(v + pajak); ekspresi = "${formatHasil(v)} TAX+ $tarifPajak% = ${formatHasil(v + pajak)}"; _tambahStep({"item": ekspresi, "rumus": ekspresi, "harga": v, "qty": tarifPajak, "jumlah": v + pajak}); entryBaru = true; opPending = ""; op = ""; operanSiap = true; }
  void _pencetTaxMin() { final v = _angkaLayar(); final bersih = v / (1 + tarifPajak / 100); layar = formatHasil(bersih); ekspresi = "${formatHasil(v)} TAX- $tarifPajak% = ${formatHasil(bersih)}"; _tambahStep({"item": ekspresi, "rumus": ekspresi, "harga": v, "qty": tarifPajak, "jumlah": bersih}); entryBaru = true; opPending = ""; op = ""; operanSiap = true; }
  void _setTax() { final v = _angkaLayar(); if (v >= 0 && v <= 100) { tarifPajak = v; ekspresi = "SET TAX = ${formatHasil(v)}%"; layar = formatHasil(v); entryBaru = true; opPending = ""; op = ""; operanSiap = true; } }
  void _pencetCost() { laciCost = _angkaLayar(); ekspresi = "COST = ${formatHasil(laciCost)}"; entryBaru = true; _hitungCSM(); }
  void _pencetSell() { laciSell = _angkaLayar(); ekspresi = "SELL = ${formatHasil(laciSell)}"; entryBaru = true; _hitungCSM(); }
  void _pencetMargin() { final v = _angkaLayar(); if (v > 0 && v < 100) { laciMargin = v; ekspresi = "MARGIN = ${formatHasil(v)}%"; entryBaru = true; _hitungCSM(); } }
  void _hitungCSM() {
    if (laciCost > 0 && laciMargin > 0 && laciMargin < 100 && laciSell == 0) { laciSell = laciCost / (1 - laciMargin / 100); layar = formatHasil(laciSell); ekspresi = "SELL = COST / (1 - MARGIN) = ${formatHasil(laciSell)}"; }
    else if (laciSell > 0 && laciMargin > 0 && laciMargin < 100 && laciCost == 0) { laciCost = laciSell * (1 - laciMargin / 100); layar = formatHasil(laciCost); ekspresi = "COST = SELL x (1 - MARGIN) = ${formatHasil(laciCost)}"; }
    else if (laciCost > 0 && laciSell > 0 && laciSell != laciCost) { laciMargin = (laciSell - laciCost) / laciSell * 100; layar = formatHasil(laciMargin); ekspresi = "MARGIN = (SELL - COST) / SELL = ${formatHasil(laciMargin)}%"; }
    if (laciCost > 0 || laciSell > 0 || laciMargin > 0) _tambahStep({"item": ekspresi, "rumus": ekspresi, "harga": laciCost, "qty": laciMargin, "jumlah": laciSell});
    opPending = ""; op = ""; operanSiap = true;
  }
  void _resetCSM() { laciCost = 0; laciSell = 0; laciMargin = 0; ekspresi = "COST / SELL / MARGIN direset"; }
  void _gantiRound() { modeRound = modeRound == "5/4" ? "CUT" : modeRound == "CUT" ? "F" : "5/4"; ekspresi = "ROUND = $modeRound"; layar = formatHasil(_angkaLayar()); }
  void _gantiAdd2() { modeAdd2 = !modeAdd2; ekspresi = modeAdd2 ? "ADD2 ON: ketik 123 -> 1.23" : "ADD2 OFF"; }
  double _terapkanAdd2(double v) => modeAdd2 ? v / 100 : v;
  double get totalCek { double t = 0; for (final s in steps) { t += (s["jumlah"] as num?)?.toDouble() ?? 0; } return t; }
  // ===== STEP + RIWAYAT (log step, BUKAN PO) =====
  // Riwayat = log tiap step (1 step = 1 subtotal). Kumpulan step = PO.
  // Riwayat TIDAK nunggu PO: tiap step baru langsung tercatat di sini.
  void _tambahStep(Map<String, dynamic> step) {
    steps.add(step);
    _catatStepKeRiwayat(step);
  }
  void _catatStepKeRiwayat(Map<String, dynamic> step) {
    final entry = {
      "item": "${step["item"]}",
      "rumus": "${step["rumus"] ?? step["item"]}",
      "harga": (step["harga"] as num?)?.toDouble() ?? 0,
      "qty": (step["qty"] as num?)?.toDouble() ?? 0,
      "jumlah": (step["jumlah"] as num?)?.toDouble() ?? 0,
      "tanggal": _tanggalLogStep(),
    };
    riwayatPO.insert(0, entry);
    _db.tambahLogStep(item: "${entry["item"]}", rumus: "${entry["rumus"]}", harga: entry["harga"] as double, qty: entry["qty"] as double, jumlah: entry["jumlah"] as double).then((id) {
      if (mounted) setState(() { entry["id"] = id; });
    });
  }
  void _hapusSatuRiwayat(Map<String, dynamic> r) {
    final id = r["id"];
    if (id is int) _db.hapusLogStep(id);
    riwayatPO.remove(r);
  }
  // ===== CEK = PO: step bisa diedit penuh (nama barang, harga, qty, jumlah). =====
  void _simpanStepCEK(int i, double harga, double qty, double jumlah) {
    if (i < 0 || i >= steps.length) return;
    final hargaLama = (steps[i]["harga"] as num?)?.toDouble() ?? 0;
    final qtyLama = (steps[i]["qty"] as num?)?.toDouble() ?? 0;
    final jumlahBaru = (harga != hargaLama || qty != qtyLama) ? harga * qty : jumlah;
    steps[i]["harga"] = harga;
    steps[i]["qty"] = qty;
    steps[i]["jumlah"] = jumlahBaru;
    final nama = "${steps[i]["item"]}";
    if (nama.contains(" = ")) {
      steps[i]["rumus"] = "$nama -> ${formatHasil(jumlahBaru)}";
    } else {
      steps[i]["rumus"] = "$nama : ${formatHasil(qty)} x ${formatRupiah(harga.toInt())} = ${formatRupiah(jumlahBaru.toInt())}";
    }
    layar = formatHasil(totalCek);
    ekspresi = "CEK PO $nomorPOSeries = ${formatHasil(totalCek)}";
  }
  void _bukaPilihBarangUntukStep(int i, void Function(void Function()) setSheet) {
    if (daftarBarang.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Belum ada barang — tambah dulu via LS.")));
      return;
    }
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(12), child: Text("Tap barang untuk ganti nama step ini", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      SizedBox(height: 320, child: ListView.builder(itemCount: daftarBarang.length, itemBuilder: (_, j) {
        final b = daftarBarang[j];
        return ListTile(
          title: Text("${b["nama"]}"),
          subtitle: Text("${b["kode"]} • ${formatRupiah(int.tryParse("${b["harga1"]}") ?? 0)}"),
          onTap: () {
            final hargaBaru = double.tryParse("${b["harga1"]}") ?? 0;
            final qtyLama = (steps[i]["qty"] as num?)?.toDouble() ?? 1;
            setState(() {
              steps[i]["item"] = "${b["nama"]}";
              steps[i]["harga"] = hargaBaru;
              steps[i]["jumlah"] = hargaBaru * qtyLama;
              steps[i]["rumus"] = "${b["nama"]} : ${formatHasil(qtyLama)} x ${formatRupiah(hargaBaru.toInt())} = ${formatRupiah((hargaBaru * qtyLama).toInt())}";
              layar = formatHasil(totalCek);
              ekspresi = "CEK PO $nomorPOSeries = ${formatHasil(totalCek)}";
            });
            Navigator.pop(ctx);
            setSheet(() {});
          },
        );
      })),
    ])));
  }
  void _simpanPOdariCEK() {
    if (steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("CEK masih kosong — hitung dulu / M+ dulu.")));
      return;
    }
    final salinan = steps.map((e) => Map<String, dynamic>.from(e)).toList();
    final total = totalCek;
    final tgl = _tanggalSimpanPO();
    final pelanggan = pelangganCtrl.text.trim();
    if (pelanggan.isNotEmpty) _simpanPelangganCache(pelanggan);
    if (poRevisiIndex != null && poRevisiIndex! >= 0 && poRevisiIndex! < daftarPO.length) {
      daftarPO[poRevisiIndex!] = {...daftarPO[poRevisiIndex!], "items": salinan, "total": total, "tanggal": tgl, "pelanggan": pelanggan};
    } else {
      final nomor = nomorPOSeries;
      daftarPO.add({"nomor": nomor, "tanggal": tgl, "pelanggan": pelanggan, "items": salinan, "total": total});
      poRevisiIndex = daftarPO.length - 1;
    }
    _tulisPOAktifKeDrift();
    layar = formatHasil(total);
    ekspresi = "PO ${daftarPO[poRevisiIndex!]["nomor"]} tersimpan = ${formatHasil(total)}";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PO ${daftarPO[poRevisiIndex!]["nomor"]} tersimpan / ter-update dari CEK.")));
  }
  void _muatPOkeCEK(int i) {
    if (i < 0 || i >= daftarPO.length) return;
    final p = daftarPO[i];
    steps.clear();
    for (final e in (p["items"] as List)) {
      steps.add(Map<String, dynamic>.from(e as Map)); // muat ulang PO lama: JANGAN dicatat lagi ke Riwayat
    }
    poRevisiIndex = i;
    pelangganCtrl.text = "${p["pelanggan"] ?? ""}";
    nomorPO = int.tryParse("${p["nomor"]}".replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
    layar = formatHasil(totalCek);
    ekspresi = "PO ${p["nomor"]} dimuat untuk revisi";
  }
  void _detailPO(int i) {
    if (i < 0 || i >= daftarPO.length) return;
    final p = daftarPO[i];
    final items = (p["items"] as List);
    final pelanggan = "${p["pelanggan"] ?? ""}";
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("${p["nomor"]}"),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (pelanggan.isNotEmpty) Text("Pelanggan: $pelanggan", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        Text("Tanggal: ${p["tanggal"]}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        ...items.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return Padding(padding: const EdgeInsets.only(bottom: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("${m["item"]}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text("${formatHasil((m["qty"] as num?)?.toDouble() ?? 0)} x ${formatRupiah(((m["harga"] as num?)?.toDouble() ?? 0).toInt())} = ${formatRupiah(((m["jumlah"] as num?)?.toDouble() ?? 0).toInt())}", style: const TextStyle(fontSize: 12)),
          ]));
        }),
        const Divider(),
        Text("TOTAL = ${formatRupiah(((p["total"] as num?)?.toDouble() ?? 0).toInt())}", style: const TextStyle(fontWeight: FontWeight.bold)),
      ])),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); _hapusPO(i); }, child: const Text("HAPUS PO", style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("TUTUP")),
        ElevatedButton(onPressed: () {
          Navigator.pop(ctx);
          setState(() { _muatPOkeCEK(i); });
          bukaCek();
        }, child: const Text("REVISI PO INI")),
      ],
    ));
  }
  void _bukaRiwayat() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) {
        final q = queryRiwayat.toLowerCase();
        final hasil = riwayatPO.where((r) {
          if (q.isEmpty) return true;
          return "${r["item"]}".toLowerCase().contains(q) || "${r["rumus"]}".toLowerCase().contains(q) || "${r["tanggal"]}".toLowerCase().contains(q);
        }).toList();
        return Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
          child: SizedBox(height: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Riwayat — Log Step", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(children: [
                TextButton.icon(icon: const Icon(Icons.delete_sweep, size: 18), label: const Text("Hapus Semua"), onPressed: () { _db.hapusSemuaLogStep(); setSheet(() { riwayatPO.clear(); }); setState(() {}); }),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
            ]),
            const Text("1 step = 1 subtotal. Tiap hitung / M+ langsung tercatat di sini — tidak nunggu PO.", style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 6),
            TextField(decoration: dec("🔍 Cari log step — nama barang / rumus / tanggal..."), onChanged: (v) { setSheet(() { queryRiwayat = v; }); setState(() { queryRiwayat = v; }); }),
            const SizedBox(height: 8),
            Expanded(child: hasil.isEmpty ? const Center(child: Text("Belum ada log step. Hitung / pencet = / M+ dulu — tiap step otomatis tercatat di sini.", textAlign: TextAlign.center)) : ListView.builder(itemCount: hasil.length, itemBuilder: (_, j) {
              final r = hasil[j];
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${r["item"]}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text("${r["rumus"]}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text("${r["tanggal"]} • Subtotal ${formatRupiah(((r["jumlah"] as num?)?.toDouble() ?? 0).toInt())}", style: const TextStyle(fontSize: 11)),
                  ])),
                  IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), tooltip: "Hapus 1 step ini", onPressed: () { setSheet(() { _hapusSatuRiwayat(r); }); setState(() {}); }),
                ]));
            })),
          ])));
      }),
    );
  }
  void _bukaCariPO() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) {
        final q = queryPO.toLowerCase();
        final hasil = daftarPO.where((p) {
          if (q.isEmpty) return true;
          final items = (p["items"] as List);
          final namaItems = items.map((e) => "${(e as Map)["item"]}").join(" ").toLowerCase();
          return "${p["nomor"]}".toLowerCase().contains(q) || "${p["pelanggan"] ?? ""}".toLowerCase().contains(q) || namaItems.contains(q) || "${p["tanggal"]}".toLowerCase().contains(q);
        }).toList();
        return Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
          child: SizedBox(height: 560, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("PO — Cari PO Tersimpan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 6),
            // ===== SIMPAN PO DI SINI: nomor + pelanggan + tanggal kelihatan, 1 tombol =====
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(nomorPOSeries, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Expanded(child: Text("Tanggal simpan: ${_tanggalSimpanPO()}", style: const TextStyle(color: Colors.white70, fontSize: 11))),
                ]),
                const SizedBox(height: 8),
                _fieldPelanggan(setSheet),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.save, size: 18), label: Text(poRevisiIndex != null ? "Simpan — Update ${daftarPO[poRevisiIndex!]["nomor"]}" : "Simpan PO — $nomorPOSeries"), onPressed: () { setSheet(() { _simpanPOdariCEK(); }); setState(() {}); })),
              ])),
            const SizedBox(height: 8),
            TextField(decoration: dec("🔎 Cari PO — nomor / pelanggan / nama barang / tanggal..."), onChanged: (v) { setSheet(() { queryPO = v; }); setState(() { queryPO = v; }); }),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text("PO aktif (M+): ${ref.watch(poProvider).items.length} item", style: const TextStyle(fontSize: 12, color: Colors.grey))),
              TextButton(onPressed: () { Navigator.pop(ctx); setState(() { poTerbuka = true; }); }, child: const Text("Buka Panel PO")),
            ]),
            const Divider(),
            Expanded(child: hasil.isEmpty ? Center(child: Text(_dbSiap ? "Belum ada PO tersimpan.\nHitung di CEK lalu Simpan PO di atas." : "Memuat PO tersimpan...", textAlign: TextAlign.center)) : ListView.builder(itemCount: hasil.length, itemBuilder: (_, j) {
              final p = hasil[j];
              final idx = daftarPO.indexOf(p);
              final items = (p["items"] as List);
              final pelanggan = "${p["pelanggan"] ?? ""}";
              return InkWell(onTap: () { Navigator.pop(ctx); _detailPO(idx); },
                child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${p["nomor"]}${pelanggan.isEmpty ? "" : " — $pelanggan"}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text("${p["tanggal"]} • ${items.length} step • Total ${formatRupiah(((p["total"] as num?)?.toDouble() ?? 0).toInt())}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(items.map((e) => "${(e as Map)["item"]}").join(" | "), style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])));
            })),
          ])));
      }),
    );
  }

  void pencet(String t) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC") {
        // Casio AC: hapus SEMUA - layar, akumulator, operator, ekspresi, error
        layar = "0"; ekspresi = ""; akumulator = 0; angka1 = 0; opPending = ""; op = ""; entryBaru = true; adaError = false; lastOp = ""; lastAngka2 = 0; adaQtyHitung = false; qtyHitung = 1; operanSiap = false;
      }
      else if (t == "ON/C") {
        // Casio ON/C: hapus entry saja, akumulator + operator tetap
        layar = "0"; entryBaru = true; adaError = false; operanSiap = false;
      }
      else if (t == "OFF") { layar = "0"; ekspresi = ""; akumulator = 0; angka1 = 0; opPending = ""; op = ""; entryBaru = true; adaError = false; operanSiap = false; }
      else if (t == "PO") { _bukaCariPO(); }
      else if (t == "CPS") { _bukaCPS(); }
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
      else if (t == "GT") { layar = formatHasil(grandTotal); ekspresi = "GT = ${formatHasil(grandTotal)}"; entryBaru = true; operanSiap = true; }
      else if (t == "BEP") {
        if (hargaAcuan > 0) { layar = formatHasil(hargaAcuan * 1.1); ekspresi = "BEP = Acuan x 110%"; }
        else { layar = formatHasil((double.tryParse(_stripBacktick(layar)) ?? 0) + 120); }
        entryBaru = true; operanSiap = true;
      }
      else if (t == "M+") {
        // FIX BIRU - QTY BUKAN LAYAR / HASIL:
        // Kalau habis hitung 5 x 80000 = 400000, qty = 5 (qtyHitung), bukan 400000 (layar).
        // Kalau belum hitung apa-apa, qty = angka di layar.
        int qtyPO;
        {
          final hasilLayar = _parseLayar();
          final hargaB = barangDipilih != null ? (int.tryParse("${barangDipilih!["harga1"]}") ?? 0) : 0;
          if (hargaB > 0 && hasilLayar > 0 && hasilLayar % hargaB == 0 && (hasilLayar / hargaB) >= 1 && (hasilLayar / hargaB) <= 100000) {
            qtyPO = (hasilLayar / hargaB).round();
          } else if (lastOp == "x" && lastAngka2 > 0 && lastAngka2 <= 100000 && lastAngka2 != hasilLayar) {
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
          _tambahStep({"item": "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}", "rumus": "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}", "harga": harga, "qty": qtyAman, "jumlah": jumlah});
        }
        layar = "0"; entryBaru = true; adaQtyHitung = false; operanSiap = false;
      }
      else if (t == "M-") { memori -= double.tryParse(_stripBacktick(layar)) ?? 0; layar = "0"; entryBaru = true; operanSiap = false; }
      else if (t == "MRC") { layar = formatHasil(memori); memori = 0; entryBaru = true; operanSiap = true; }
      else if (t == "MR") { layar = formatHasil(memori); entryBaru = true; operanSiap = true; }
      else if (t == "MC") { memori = 0; layar = "0"; entryBaru = true; operanSiap = false; }
      else if (t == "MU") {
        // Casio MU (Mark-Up): Harga modal 100, MU 20 -> Harga jual = 100 / (1 - 20%) = 125
        // Di sini: layar = modal, MU = +10% BEP cepat. Pakai rumus MU beneran dengan 10%:
        final modal = double.tryParse(_stripBacktick(layar)) ?? 0;
        final jual = modal / (1 - 0.10);
        ekspresi = "MU 10% dari ${formatHasil(modal)}";
        layar = formatHasil(jual); entryBaru = true; opPending = ""; op = ""; operanSiap = true;
      }
      else if (t == "RIW") { _bukaRiwayat(); }
      else if (t == "⌫") {
        if (adaError) { layar = "0"; adaError = false; entryBaru = true; operanSiap = false; }
        else if (!entryBaru) { if (layar.length > 1) { layar = _groupBacktick(_stripBacktick(layar).substring(0, _stripBacktick(layar).length - 1)); if (layar.isEmpty || layar == "-") layar = "0"; } else { layar = "0"; } }
      }
      else if (["+", "-", "x", "÷", "/"].contains(t)) { _inputOperator(t); }
      else if (t == "=") { if (modeAdd2 && opPending.isEmpty) { layar = formatHasil(_terapkanAdd2(_angkaLayar())); } _inputSamaDengan(); }
      else if (t == "+/-") {
        if (adaError) return;
        // Habis operator (7 +) layar masih 7. +/- di sini = mulai entry negatif (-0), BUKAN mengubah 7 jadi -7 (itu bikin 7 + (-7) = 0).
        if (entryBaru && !operanSiap) { layar = "-0"; entryBaru = false; operanSiap = true; }
        else if (layar.startsWith("-")) { layar = layar.substring(1); } else if (layar != "0") { layar = "-$layar"; }
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
        TextField(controller: hargaC, keyboardType: TextInputType.number, decoration: dec("Harga 1")),
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
                        if (satuanBarang.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 4, children: satuanBarang.map<Widget>((x) { final m = Map<String, dynamic>.from(x as Map); final nom = double.tryParse(m["nominal"].toString()) ?? 0; final labelSatuan = (m["satuanBaru"]?.toString().isNotEmpty == true) ? m["satuanBaru"].toString() : m["satuan"].toString(); return ActionChip(label: Text("$labelSatuan - ${formatRupiah(nom.toInt())}", style: const TextStyle(fontSize: 10)), onPressed: () { setState(() { barangDipilih = {"kode": b["kode"].toString(), "nama": b["nama"].toString(), "kategori": b["kategori"].toString(), "harga1": nom.toInt().toString()}; layar = nom.toStringAsFixed(0); entryBaru = true; operanSiap = true; }); Navigator.pop(ctx); }); }).toList())],
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
                Expanded(child: TextField(controller: unitCtrl, decoration: dec("Unit (Biru - auto sama)"), onChanged: (v) { syncSatuanKiri(); setSheet(() => refreshSemuaNominal()); })),
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
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Satuan", style: TextStyle(fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => setSheet(() { satuanList.add(SatuanItem(satuan: unitCtrl.text, dasar: false, qty: "1", isi: "1", op: "÷", nominal: "0", satuanBaru: "")); syncSatuanKiri(); }), child: const Text("+Tambah Satuan", style: TextStyle(fontSize: 11)))]),
              const Text("KIRI: bilangan bebas + satuan BIRU ikut Harga 1 (auto ngikut saat unit diedit). KANAN: isi + unit HIJAU = satuan baru, masuk list. Baris bawah (merah) = INFO dari Harga 1, bukan dari field Rp.", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 6),
              ...satuanList.asMap().entries.map((e) {
                final it = e.value;
                return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Colors.white),
                  child: Column(children: [
                    Row(children: [
                      _AutoField(controller: it.qtyCtrl, hint: "1", angka: true, min: 44, max: 90, onChanged: (v) => setSheet(() { it.nominalManual = false; refreshNominal(it); })),
                      const SizedBox(width: 4),
                      Container(constraints: const BoxConstraints(minWidth: 52, maxWidth: 140), height: 40, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade300), borderRadius: BorderRadius.circular(6)), child: Text(unitCtrl.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue), overflow: TextOverflow.ellipsis)),
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
          SizedBox(height: poTinggi, child: Container(color: const Color(0xFF2E2E2E), padding: const EdgeInsets.all(12),
            child: Column(children: [
              GestureDetector(
                onTap: () => setState(() { poTinggi = poTinggi > 250 ? 180 : 380; }),
                onVerticalDragUpdate: (d) => setState(() { poTinggi = (poTinggi + d.delta.dy).clamp(160.0, 480.0); }),
                child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 2), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 22), Text("Geser / tap untuk kecil-besar — kalkulator tetap kelihatan", style: TextStyle(color: Colors.white70, fontSize: 10))])),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(nomorPOSeries, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const Text("PO - Daftar Item", style: TextStyle(color: Colors.white70, fontSize: 11))]), IconButton(icon: const Icon(Icons.close, color: Colors.white), tooltip: "Tutup PO, balik ke keypad", onPressed: () => setState(() { poTerbuka = false; }))]),
              const SizedBox(height: 6),
              _fieldPelanggan(setState, diPanel: true),
              const SizedBox(height: 4),
              Text("Tanggal simpan: ${_tanggalSimpanPO()}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.save, size: 18), label: Text(poRevisiIndex != null ? "Simpan — Update ${daftarPO[poRevisiIndex!]["nomor"]}" : "Simpan PO — $nomorPOSeries"), onPressed: () { _simpanPOdariCEK(); })),
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
          )),
          SizedBox(width: double.infinity, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), color: Colors.grey.shade100, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _chipFungsi("TAX+", Colors.teal), _chipFungsi("TAX-", Colors.teal), _chipFungsi("SET TAX", Colors.teal.shade100),
            _chipFungsi("COST", Colors.indigo), _chipFungsi("SELL", Colors.indigo), _chipFungsi("MARGIN", Colors.indigo), _chipFungsi("CSM CLR", Colors.grey.shade300),
            _chipFungsi("ROUND", Colors.amber.shade100), _chipFungsi("ADD2", Colors.amber.shade100), _chipFungsi("GT", Colors.black),
          ])))),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
            child: Column(children: [
              Expanded(child: Row(children: [tombol("AC", bg: Colors.blue.shade400, fg: Colors.white), tombol("MRC", bg: Colors.grey.shade400), tombol("M-", bg: Colors.grey.shade400), tombol("M+", bg: Colors.green, fg: Colors.white, besar: true), tombol("LS", bg: Colors.orange.shade100, besar: true), tombol("CEK", bg: Colors.black, fg: Colors.white), tombol("CPS", bg: Colors.amber, fg: Colors.black), tombol("BEP", bg: Colors.pink, fg: Colors.white)])),
              Expanded(child: Row(children: [tombol("OFF", bg: Colors.blue.shade400, fg: Colors.white), tombol("7"), tombol("8"), tombol("9"), tombol("RIW", bg: Colors.grey.shade300), tombol("MU", bg: Colors.grey.shade300), tombol("MC", bg: Colors.grey.shade300)])),
              Expanded(child: Row(children: [tombol("%", bg: Colors.grey.shade300), tombol("4"), tombol("5"), tombol("6"), tombol("-", bg: Colors.grey.shade300), tombol("÷", bg: Colors.grey.shade300), tombol("MR", bg: Colors.grey.shade300)])),
              Expanded(child: Row(children: [tombol("+/-", bg: Colors.grey.shade300), tombol("1"), tombol("2"), tombol("3"), tombol("+", bg: Colors.grey.shade300), tombol("x", bg: Colors.grey.shade300), tombol("PO", bg: Colors.teal, fg: Colors.white)])),
              Expanded(child: Row(children: [tombol("ON/C", bg: Colors.blue.shade400, fg: Colors.white), tombol("0"), tombol("00"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true), tombol("M+", bg: Colors.green, fg: Colors.white), tombol("⌫", bg: Colors.grey.shade300)])),
            ]),
          )),
      ])),
    );
  }
}

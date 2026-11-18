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

class HomeDaftarPO extends ConsumerStatefulWidget {
  const HomeDaftarPO({super.key});
  @override
  ConsumerState<HomeDaftarPO> createState() => _S();
}

class _S extends ConsumerState<HomeDaftarPO> {
  String layar = "0";
  String op = "";
  double angka1 = 0;
  double memori = 0;
  bool tekanTombol = false;
  String tombolDitekan = "";
  Map<String, String>? barangDipilih;
  final List<Map<String, dynamic>> daftarBarang = [];
  String queryLS = "";
  final kodeCtrl = TextEditingController();
  final namaCtrl = TextEditingController();
  String kategoriPilih = "Semen";
  final List<String> listKategori = ["Semen", "Besi", "Cat", "Keramik", "Pipa"];
  final kategoriBaruCtrl = TextEditingController();
  final unitCtrl = TextEditingController(text: "pcs");
  final harga1Ctrl = TextEditingController(text: "0");
  final List<TextEditingController> varianCtrls = [TextEditingController(text: "Hitam")];
  // Daftar satuan: apapun yang diketik di field kuning / biru masuk sini.
  final Set<String> daftarSatuan = {"sak", "kg", "kilo", "m", "3m", "pcs"};
  void tambahKeDaftarSatuan(String nama) {
    final v = nama.trim().toLowerCase();
    if (v.isEmpty) return;
    daftarSatuan.add(v);
  }
  // SATU gaya field untuk semua input, supaya tidak ada yang kepotong:
  // hint (bukan label), font 13, padding lega, tinggi konsisten.
  InputDecoration dec(String hint, {String? prefix}) {
    return InputDecoration(hintText: hint, prefixText: prefix, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11), border: const OutlineInputBorder());
  }
  List<SatuanItem> satuanList = [
    SatuanItem(satuan: "sak", dasar: true, qty: "1", isi: "1", op: "x", nominal: "50000"),
    SatuanItem(satuan: "sak", dasar: false, qty: "1", isi: "50", op: "÷", nominal: "1000"),
  ];
  String modeHitung = "PEMBULATAN";
  int desimal = 0;
  final List<Map<String, dynamic>> steps = [];
  double get hargaAcuan {
    if (barangDipilih != null) return double.tryParse("${barangDipilih!["harga1"]}") ?? 0;
    return 0;
  }
  double get manual => double.tryParse(layar) ?? 0;
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
  String formatHasil(double v) {
    if (modeHitung == "ORIGINAL") return v.toStringAsFixed(desimal);
    if (desimal == 0) return v.round().toString();
    return v.toStringAsFixed(desimal);
  }
  double hitungNominal(SatuanItem s) {
    final qty = double.tryParse(s.qtyCtrl.text) ?? 1;
    final isi = double.tryParse(s.isiCtrl.text) ?? 1;
    final hargaForm = double.tryParse(harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final harga = hargaForm > 0 ? hargaForm : hargaAcuan;
    if (s.dasar) return harga;
    if (s.op == "÷") {
      if (isi == 0) return 0;
      return qty * (harga / isi);
    }
    return harga * isi;
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
  String teksRumusSatuan(SatuanItem s) {
    final dasarNama = satuanList.firstWhere((x) => x.dasar == true, orElse: () => satuanList.first).namaCtrl.text;
    final qty = s.qtyCtrl.text.isEmpty ? "1" : s.qtyCtrl.text;
    final isi = s.isiCtrl.text.isEmpty ? "1" : s.isiCtrl.text;
    final nom = s.nominalCtrl.text.isEmpty ? "0" : s.nominalCtrl.text;
    final nomBersih = int.tryParse(nom.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (s.dasar) return "$qty ${s.namaCtrl.text} = ${formatRupiah(nomBersih)}";
    return "$qty ${s.namaCtrl.text} ${s.op} $isi $dasarNama = ${formatRupiah(nomBersih)}";
  }

  void dialogBabe() {
    final namaBarang = barangDipilih == null ? "Belum pilih barang (pencet LS)" : "${barangDipilih!["nama"]}";
    final kodeBarang = barangDipilih == null ? "-" : "${barangDipilih!["kode"]}";
    final kategoriBarang = barangDipilih == null ? "-" : "${barangDipilih!["kategori"]}";
    final acuan = hargaAcuan;
    final nilaiManual = manual;
    final nilaiPersen = persen;
    final warna = warnaSaran();
    final namaWarna = warna == Colors.black ? "HITAM - belum ada acuan / belum input" : warna == const Color(0xFFB71C1C) ? "MERAH TUA - rugi besar (< -20%)" : warna == Colors.red ? "MERAH - rugi (0% s/d -20%)" : warna == const Color(0xFFB58900) ? "KUNING - waspada (0% s/d 5%)" : warna == Colors.blue ? "BIRU - untung kecil (5% s/d 15%)" : "HIJAU - untung (di atas 15%)";
    final bep = acuan > 0 ? acuan * 1.1 : 0;
    final totalStep = steps.fold<double>(0, (a, s) => a + ((s["jumlah"] as num?)?.toDouble() ?? 0));
    showDialog(context: context, builder: (ctx) {
      return AlertDialog(title: const Text("BABE.INFO - Dialog Uni"),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text("YANG SEDANG DILAKUKAN SEKARANG", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Text("Barang: $namaBarang", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text("Kode: $kodeBarang \u2022 Kategori: $kategoriBarang", style: const TextStyle(fontSize: 11)),
          Text("Unit Biru (dasar): ${unitCtrl.text.isEmpty ? "-" : unitCtrl.text}", style: const TextStyle(fontSize: 11)),
          const Divider(),
          Text("Layar kalkulator: $layar", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text("Harga Acuan (100%): ${acuan == 0 ? "---" : formatRupiah(acuan.toInt())}", style: const TextStyle(fontSize: 11)),
          Text("Manual: ${nilaiManual == 0 ? "---" : formatRupiah(nilaiManual.toInt())}", style: const TextStyle(fontSize: 11)),
          Text("Persen: ${acuan == 0 || nilaiManual == 0 ? "---" : "${nilaiPersen.toStringAsFixed(1)}%"}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: warna)),
          Text("Warna: $namaWarna", style: TextStyle(fontSize: 11, color: warna)),
          Text("BEP (Acuan x 110%): ${bep == 0 ? "---" : formatRupiah(bep.toInt())}", style: const TextStyle(fontSize: 11)),
          const Divider(),
          Text("Mode: $modeHitung \u2022 Desimal: $desimal \u2022 Memori: ${formatRupiah(memori.toInt())}", style: const TextStyle(fontSize: 11)),
          const Divider(),
          const Text("SATUAN KUNING - YANG SEDANG DIINPUT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          if (satuanList.isEmpty) const Text("Belum ada satuan.", style: TextStyle(fontSize: 11)),
          ...satuanList.map((s) {
            final manualTag = s.nominalManual ? " \u2022 MANUAL (dikunci)" : " \u2022 AUTO";
            return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text("${teksRumusSatuan(s)}$manualTag", style: const TextStyle(fontSize: 11)));
          }),
          const Divider(),
          const Text("CEK - STEP YANG SUDAH DILAKUKAN", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          if (steps.isEmpty) const Text("Belum ada step. Pencet = atau M+ dulu.", style: TextStyle(fontSize: 11)),
          ...steps.asMap().entries.map((e) {
            final s = e.value;
            return Padding(padding: const EdgeInsets.only(bottom: 2), child: Text("${e.key + 1}. ${s["item"]} | ${formatRupiah((s["harga"] as num).toInt())} x ${s["qty"]} = ${formatRupiah((s["jumlah"] as num).toInt())}", style: const TextStyle(fontSize: 11)));
          }),
          if (steps.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text("Total step: ${formatRupiah(totalStep.toInt())}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          const Divider(),
          const Text("CARA PAKAI", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text("\u2022 Harga 1 = harga per Unit Biru (dasar).\n\u2022 1 sak \u00f7 50 kg = 50.000 \u00f7 50 = 1.000 / kg\n\u2022 1 m x 3 = 25.000 x 3 = 75.000 / 3m\n\u2022 Tap (x) untuk ganti jadi (\u00f7).\n\u2022 Tap nominal untuk edit manual, tidak balik lagi.\n\u2022 BEP = Acuan x 110%.\n\u2022 CEK = lihat step, edit & hapus sebaris.", style: TextStyle(fontSize: 11)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup"))]);
    });
  }
  void refreshSemuaNominal() { for (var s in satuanList) { refreshNominal(s); } }
  // CEK - RAPI: tanpa labelText (yang bikin kepotong), pakai hint + flex.
  // Header "Item | Harga ..." dihapus. Jumlah jadi Text, bukan field.
  void bukaCek() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSheet) {
          return Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
            child: SizedBox(height: 440, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CEK - Proses Kalkulasi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const SizedBox(height: 8),
              if (steps.isEmpty) const Text("Belum ada step. Pencet = atau M+ dulu."),
              Expanded(child: ListView.builder(itemCount: steps.length, itemBuilder: (_, i) {
                final s = steps[i];
                return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(flex: 3, child: TextField(controller: TextEditingController(text: "${s["item"]}"), style: const TextStyle(fontSize: 12), decoration: dec("Item"), onChanged: (v) => s["item"] = v)),
                    const SizedBox(width: 4),
                    Expanded(flex: 2, child: TextField(controller: TextEditingController(text: "${s["harga"]}"), keyboardType: TextInputType.number, style: const TextStyle(fontSize: 12), decoration: dec("Harga"), onChanged: (v) { setSheet(() { s["harga"] = double.tryParse(v) ?? 0; s["jumlah"] = (s["harga"] as double) * (s["qty"] as num); }); })),
                    const SizedBox(width: 4),
                    Expanded(flex: 1, child: TextField(controller: TextEditingController(text: "${s["qty"]}"), keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12), decoration: dec("Qty"), onChanged: (v) { setSheet(() { s["qty"] = double.tryParse(v) ?? 0; s["jumlah"] = (s["harga"] as double) * (s["qty"] as num); }); })),
                    const SizedBox(width: 4),
                    Expanded(flex: 2, child: Text(formatRupiah((s["jumlah"] as num).toInt()), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () { setSheet(() => steps.removeAt(i)); setState(() {}); }),
                  ]));
              })),
            ])));
        });
      });
  }

  void pencet(String t) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC" || t == "ON/C") { layar = "0"; op = ""; angka1 = 0; }
      else if (t == "LS") { bukaListLS(); }
      else if (t == "CEK") { bukaCek(); }
      else if (t == "OFF") { layar = "0"; }
      else if (t == "BEP") { if (hargaAcuan > 0) { layar = formatHasil(hargaAcuan * 1.1); } else { layar = formatHasil((double.tryParse(layar) ?? 0) + 120); } }
      else if (t == "M+") {
        memori += double.tryParse(layar) ?? 0;
        if (barangDipilih != null) {
          final qty = int.tryParse(layar) ?? 1;
          final harga = int.tryParse("${barangDipilih!["harga1"]}") ?? 0;
          final it = parseInputCepat("$qty x ${barangDipilih!["nama"]} $harga");
          if (it != null) { ref.read(poProvider.notifier).tambahItem(it); }
          steps.add({"item": barangDipilih!["nama"], "harga": harga, "qty": qty, "jumlah": qty * harga});
        }
        layar = "0";
      }
      else if (t == "M-") { memori -= double.tryParse(layar) ?? 0; layar = "0"; }
      else if (t == "MRC") { layar = formatHasil(memori); memori = 0; }
      else if (t == "MR") { layar = formatHasil(memori); }
      else if (t == "MC") { memori = 0; layar = "0"; }
      else if (t == "MU") { final v = double.tryParse(layar) ?? 0; layar = formatHasil(v * 1.1); }
      else if (t == "\u25b6" || t == "\u232b") { if (layar.length > 1) { layar = layar.substring(0, layar.length - 1); } else { layar = "0"; } }
      else if (["+", "-", "x", "\u00f7", "/"].contains(t)) { angka1 = double.tryParse(layar) ?? 0; op = t; layar = "0"; }
      else if (t == "=") {
        final a2 = double.tryParse(layar) ?? 0; double h = 0;
        if (op == "+") h = angka1 + a2;
        if (op == "-") h = angka1 - a2;
        if (op == "x") h = angka1 * a2;
        if (op == "/" || op == "\u00f7") { if (a2 == 0) { h = 0; } else { h = angka1 / a2; } }
        layar = formatHasil(h);
        steps.add({"item": barangDipilih?["nama"] ?? "Hitung", "harga": angka1, "qty": a2, "jumlah": h});
        op = "";
      }
      else if (t == "+/-") { if (layar.startsWith("-")) { layar = layar.substring(1); } else if (layar != "0") { layar = "-$layar"; } }
      else if (t == "%") { layar = formatHasil((double.tryParse(layar) ?? 0) / 100); }
      else { if (layar == "0") { layar = t; } else { layar += t; } }
    });
  }
  // LS - RAMPING: 1 kartu = 1 baris header + Wrap chip kecil, tanpa ListTile tinggi.
  void bukaListLS() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSheet) {
          final q = queryLS.toLowerCase();
          final filtered = daftarBarang.where((b) {
            if (q.isEmpty) return true;
            return b["nama"].toString().toLowerCase().contains(q) || b["kode"].toString().toLowerCase().contains(q) || b["kategori"].toString().toLowerCase().contains(q);
          }).toList();
          final suggestions = filtered.take(5).toList();
          return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 12, right: 12, top: 12),
            child: SizedBox(height: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("LS - List Barang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Row(children: [TextButton(onPressed: () { Navigator.pop(ctx); bukaFormTambahBarang(); }, child: const Text("+ Tambah Barang")), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              ]),
              TextField(decoration: dec("Cari kode / nama / kategori..."), onChanged: (v) { setSheet(() { queryLS = v; }); setState(() { queryLS = v; }); }),
              const SizedBox(height: 8),
              if (suggestions.isNotEmpty) ...[
                const Text("Auto Suggestion:", style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: suggestions.map((b) => ActionChip(label: Text(b["nama"].toString(), style: const TextStyle(fontSize: 11)), onPressed: () { setState(() { barangDipilih = {"kode": b["kode"].toString(), "nama": b["nama"].toString(), "kategori": b["kategori"].toString(), "harga1": b["harga1"].toString()}; }); Navigator.pop(ctx); })).toList()),
                const SizedBox(height: 8), const Divider(),
              ],
              Expanded(child: filtered.isEmpty ? const Center(child: Text("Belum ada barang. Tap + Tambah Barang."))
                : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                  final b = filtered[i];
                  final aktif = barangDipilih != null && barangDipilih!["kode"] == b["kode"];
                  final satuanBarang = (b["satuanList"] as List?) ?? [];
                  return InkWell(onTap: () { setState(() { barangDipilih = {"kode": b["kode"].toString(), "nama": b["nama"].toString(), "kategori": b["kategori"].toString(), "harga1": b["harga1"].toString()}; }); Navigator.pop(ctx); },
                    child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: aktif ? Colors.green.shade100 : Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(radius: 16, child: Text(b["nama"].toString().isEmpty ? "?" : b["nama"].toString()[0].toLowerCase(), style: const TextStyle(fontSize: 14))),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("${b["nama"]}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text("${b["kode"]} \u2022 ${b["kategori"]} \u2022 ${b["satuan"] ?? "pcs"}", style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                          const SizedBox(width: 6),
                          Text(formatRupiah(int.tryParse(b["harga1"].toString()) ?? 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ]),
                        if (satuanBarang.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 4, runSpacing: 4, children: satuanBarang.map<Widget>((s) {
                            final m = Map<String, dynamic>.from(s as Map);
                            final dasarSatuan = satuanBarang.firstWhere((x) => (x as Map)["dasar"] == true, orElse: () => {"satuan": "pcs"})["satuan"];
                            final nom = double.tryParse(m["nominal"].toString()) ?? 0;
                            final qty = (m["qty"] ?? "1").toString(); final isi = (m["isi"] ?? "1").toString();
                            final label = m["dasar"] == true ? "$qty ${m["satuan"]}" : "$qty ${m["satuan"]} = $qty x $isi $dasarSatuan";
                            return ActionChip(label: Text("$label - ${formatRupiah(nom.toInt())}", style: const TextStyle(fontSize: 10)), onPressed: () {
                              setState(() { barangDipilih = {"kode": b["kode"].toString(), "nama": b["nama"].toString(), "kategori": b["kategori"].toString(), "harga1": nom.toInt().toString(), "satuan": m["satuan"].toString(), "satuanIsi": isi, "satuanOp": m["op"].toString()}; layar = nom.toStringAsFixed(0); });
                              Navigator.pop(ctx);
                            });
                          }).toList()),
                        ],
                      ])));
                })),
            ])));
        });
      });
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
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Category \u2022 dropdown + tambah/delete", style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(initialValue: kategoriPilih, decoration: dec("Kategori"), items: listKategori.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(), onChanged: (v) { if (v != null) setSheet(() { kategoriPilih = v; }); }),
                  Row(children: [Expanded(child: TextField(controller: kategoriBaruCtrl, decoration: dec("Kategori baru"))), IconButton(icon: const Icon(Icons.add), onPressed: () { if (kategoriBaruCtrl.text.isNotEmpty) setSheet(() { listKategori.add(kategoriBaruCtrl.text); kategoriPilih = kategoriBaruCtrl.text; kategoriBaruCtrl.clear(); }); }), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setSheet(() { if (listKategori.length > 1) { listKategori.remove(kategoriPilih); kategoriPilih = listKategori.first; } }); })]),
                ])),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: unitCtrl, decoration: dec("Unit"), onChanged: (v) { tambahKeDaftarSatuan(v); for (var x in satuanList) { if (x.satuanBaruCtrl.text.isEmpty) x.satuanBaruCtrl.text = v; } setSheet(() => refreshSemuaNominal()); })),
              ]),
              const SizedBox(height: 12),
              const Text("Harga 1 \u2022 Acuan 100%", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 4),
              TextField(controller: harga1Ctrl, keyboardType: TextInputType.number, decoration: dec("0"), onChanged: (v) => setSheet(() => refreshSemuaNominal())),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFFFF8C5), borderRadius: BorderRadius.circular(8)), child: const Text("Harga 1 ini yang jadi acuan prosentase 100%. Harga 2 dan 3 tidak perlu ditampilkan, input manual edit harga 1 menjadi harga 2 dan 3 sudah ada di PO.", style: TextStyle(fontSize: 11))),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Varian", style: TextStyle(fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => setSheet(() => varianCtrls.add(TextEditingController())), child: const Text("+Tambah Varian", style: TextStyle(fontSize: 11)))]),
              ...varianCtrls.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Expanded(child: TextField(controller: e.value, decoration: dec("Hitam"))), IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setSheet(() { if (varianCtrls.length > 1) varianCtrls.removeAt(e.key); }))]))),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Satuan", style: TextStyle(fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => setSheet(() { final baru = SatuanItem(satuan: unitCtrl.text, dasar: false, qty: "1", isi: "1", op: "x", nominal: harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''), satuanBaru: unitCtrl.text); satuanList.add(baru); }), child: const Text("+Tambah Satuan", style: TextStyle(fontSize: 11)))]),
              const Text("Qty + satuan, x/\u00f7, isi + unit = nominal.", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 6),
              ...satuanList.asMap().entries.map((e) {
                final s = e.value;
                final dasarNama = satuanList.firstWhere((x) => x.dasar == true, orElse: () => satuanList.first).namaCtrl.text;
                if (s.satuanBaruCtrl.text.isEmpty) s.satuanBaruCtrl.text = dasarNama;
                return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Colors.white),
                  child: Column(children: [
                    Row(children: [
                      SizedBox(width: 48, child: TextField(controller: s.qtyCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13), decoration: dec("1"), onChanged: (v) => setSheet(() { s.nominalManual = false; refreshNominal(s); }))),
                      const SizedBox(width: 4),
                      // KUNING - field edit, apapun yang diketik masuk daftar satuan
                      Expanded(flex: 2, child: TextField(controller: s.namaCtrl, style: const TextStyle(fontSize: 13), decoration: dec("satuan"), onChanged: (v) { tambahKeDaftarSatuan(v); if (s.dasar) syncUnitDariDasar(); setSheet(() => refreshNominal(s)); })),
                      const SizedBox(width: 4),
                      SizedBox(width: 36, height: 36, child: InkWell(onTap: () => setSheet(() { s.op = s.op == "x" ? "\u00f7" : "x"; s.nominalManual = false; refreshNominal(s); }), borderRadius: BorderRadius.circular(18), child: Container(decoration: BoxDecoration(color: s.op == "\u00f7" ? Colors.teal.shade100 : Colors.orange.shade100, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400)), child: Center(child: Text(s.op, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))))),
                      const SizedBox(width: 4),
                      SizedBox(width: 52, child: TextField(controller: s.isiCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13), decoration: dec("isi"), onChanged: (v) => setSheet(() { s.nominalManual = false; refreshNominal(s); }))),
                      const SizedBox(width: 4),
                      // BIRU - field edit juga, mengikuti unit, tidak vertikal lagi
                      Expanded(flex: 2, child: TextField(controller: s.satuanBaruCtrl, style: const TextStyle(fontSize: 13), decoration: dec("unit"), onChanged: (v) { tambahKeDaftarSatuan(v); setSheet(() => refreshNominal(s)); })),
                      // DASAR - chip kecil, bukan Radio + teks "dasar" yang bikin meluber
                      const SizedBox(width: 4),
                      ChoiceChip(label: const Text("Dasar", style: TextStyle(fontSize: 10)), selected: s.dasar, onSelected: (_) => setSheet(() { for (var x in satuanList) { x.dasar = false; } s.dasar = true; syncUnitDariDasar(); refreshSemuaNominal(); })),
                      IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 26, minHeight: 26), onPressed: () => setSheet(() { if (satuanList.length > 1) satuanList.removeAt(e.key); })),
                    ]),
                    const SizedBox(height: 6),
                    TextField(controller: s.nominalCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13), decoration: dec("nominal", prefix: "Rp "), onTap: () => s.nominalManual = true, onChanged: (v) => s.nominalManual = true),
                    const SizedBox(height: 4),
                    // Rumus tetap ada (logika tidak dikurangi), tapi 1 baris, tidak kepotong
                    SizedBox(width: double.infinity, child: Text(teksRumusSatuan(s), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]));
              }),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () {
                final varian = varianCtrls.map((c) => c.text).join(", ");
                setState(() { daftarBarang.add({"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''), "satuan": unitCtrl.text, "varian": varian, "satuanList": satuanList.map((x) => x.toMap()).toList()}); barangDipilih = {"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')}; });
                Navigator.pop(ctx);
              }, child: const Text("Simpan Barang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 20),
            ])));
        });
      });
  }

  Widget tombol(String label, {Color? bg, Color? fg, bool besar = false}) {
    final isDown = tombolDitekan == label && tekanTombol;
    final baseColor = bg ?? Colors.white;
    final shadowColor = baseColor == Colors.white ? Colors.grey.shade400 : Colors.black26;
    return Expanded(child: Padding(padding: const EdgeInsets.all(2.5), child: GestureDetector(
      onTapDown: (_) => setState(() { tombolDitekan = label; tekanTombol = true; }),
      onTapUp: (_) { setState(() { tekanTombol = false; }); pencet(label); },
      onTapCancel: () => setState(() { tekanTombol = false; }),
      child: AnimatedContainer(duration: const Duration(milliseconds: 80), height: besar ? 56 : 46, transform: Matrix4.translationValues(0, isDown ? 2 : 0, 0),
        decoration: BoxDecoration(color: isDown ? baseColor.withValues(alpha: 0.85) : baseColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12),
          boxShadow: isDown ? [] : [BoxShadow(color: shadowColor, offset: const Offset(0, 3), blurRadius: 0), BoxShadow(color: Colors.white.withValues(alpha: 0.6), offset: const Offset(0, -1), blurRadius: 0)]),
        child: Center(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: besar ? 16 : 14, fontWeight: FontWeight.bold, color: fg ?? Colors.black)))))));
  }
  @override
  Widget build(BuildContext context) {
    final po = ref.watch(poProvider);
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    return Scaffold(backgroundColor: const Color(0xFFE8E0C8), body: CustomScrollView(slivers: [
      SliverAppBar(pinned: true, floating: false, snap: false, automaticallyImplyLeading: false, backgroundColor: const Color(0xFF1A1A1A), expandedHeight: 196, collapsedHeight: 196, toolbarHeight: 196,
        flexibleSpace: FlexibleSpaceBar(background: Container(color: const Color(0xFF1A1A1A), child: Column(children: [
          Container(height: 28, color: Colors.black),
          Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 6), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("BASKORO WINGCHUN", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), GestureDetector(onTap: dialogBabe, child: const Text("BABE.INFO - dialog kalkulasi", style: TextStyle(color: Colors.white70, fontSize: 9, decoration: TextDecoration.underline)))]),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFDDE8D0), borderRadius: BorderRadius.circular(6)),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(teksAcuan(), style: const TextStyle(fontSize: 12, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), Flexible(child: Text(layar, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right))]),
                  const SizedBox(height: 2),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(barangDipilih == null ? "Pilih barang via LS" : "${barangDipilih!["nama"]} \u2022 ${barangDipilih!["kategori"]}", style: const TextStyle(fontSize: 9, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), Text(teksSaran(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: warnaSaran()))]),
                ])),
            ]))),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Row(children: [
            Expanded(flex: 2, child: InkWell(onTap: () => setState(() { modeHitung = modeHitung == "PEMBULATAN" ? "ORIGINAL" : "PEMBULATAN"; }), child: Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)), child: Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: const Text("5/4", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))), const SizedBox(width: 4), Expanded(child: Text(modeHitung, style: const TextStyle(color: Colors.white, fontSize: 9), overflow: TextOverflow.ellipsis))])))),
            const SizedBox(width: 4),
            Expanded(flex: 1, child: SizedBox(height: 32, child: SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text("0", style: TextStyle(fontSize: 9))), ButtonSegment(value: 2, label: Text("2", style: TextStyle(fontSize: 9))), ButtonSegment(value: 3, label: Text("3", style: TextStyle(fontSize: 9)))], selected: {desimal}, onSelectionChanged: (s) => setState(() { desimal = s.first; })))),
            const SizedBox(width: 4),
            Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: () {}, style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 10)), child: const Text("Kirim WA")))),
            const SizedBox(width: 4),
            Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 9), backgroundColor: Colors.white), child: const Text("Nota")))),
          ])),
        ])))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFE8E0C8), borderRadius: BorderRadius.circular(10)), child: Column(children: [
          Row(children: [tombol("AC", bg: Colors.blue.shade400, fg: Colors.white), tombol("MRC", bg: Colors.grey.shade400), tombol("M-", bg: Colors.grey.shade400), tombol("M+", bg: Colors.green, fg: Colors.white, besar: true), tombol("LS", bg: Colors.orange.shade100, besar: true), tombol("CEK", bg: Colors.black, fg: Colors.white), tombol("BEP", bg: Colors.pink, fg: Colors.white)]),
          Row(children: [tombol("OFF", bg: Colors.blue.shade400, fg: Colors.white), tombol("7"), tombol("8"), tombol("9"), tombol("\u25b6", bg: Colors.grey.shade300), tombol("MU", bg: Colors.grey.shade300), tombol("MC", bg: Colors.grey.shade300)]),
          Row(children: [tombol("%", bg: Colors.grey.shade300), tombol("4"), tombol("5"), tombol("6"), tombol("-", bg: Colors.grey.shade300), tombol("\u00f7", bg: Colors.grey.shade300), tombol("MR", bg: Colors.grey.shade300)]),
          Row(children: [tombol("+/-", bg: Colors.grey.shade300), tombol("1"), tombol("2"), tombol("3"), tombol("+", bg: Colors.grey.shade300), tombol("x", bg: Colors.grey.shade300), tombol("M-", bg: Colors.grey.shade300)]),
          Row(children: [tombol("ON/C", bg: Colors.blue.shade400, fg: Colors.white), tombol("0"), tombol("00"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true), tombol("M+", bg: Colors.green, fg: Colors.white), tombol("\u232b", bg: Colors.grey.shade300)]),
        ])),
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF2E2E2E), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          if (po.items.isEmpty) const Text("Belum ada item - pencet LS pilih barang, lalu M+", style: TextStyle(color: Colors.white70, fontSize: 11)),
          if (po.items.isNotEmpty) ...po.items.asMap().entries.map((e) => Container(margin: const EdgeInsets.only(bottom: 3), padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text("${e.key + 1}. ${e.value.namaBarang} - ${e.value.qty}x ${formatRupiah(e.value.hargaSatuan)}", style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)), IconButton(icon: const Icon(Icons.delete, size: 14), onPressed: () => ref.read(poProvider.notifier).hapusItem(e.key), padding: EdgeInsets.zero, constraints: const BoxConstraints())]))),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text("Subtotal: ${formatRupiah(hasil.subtotal)}", style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)), Text("Total: ${formatRupiah(hasil.totalAkhir)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))]),
        ])),
        const SizedBox(height: 8),
      ]))),
    ]));
  }
}

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


// FIELD AUTO-LEBAR: lebar ikut isi ketikan.
// Min 44 (angka), max 150 (teks panjang). Dipakai di CEK + Satuan.
class _AutoField extends StatefulWidget {
  const _AutoField({required this.controller, this.hint = "", this.angka = false, this.onChanged, this.min = 44, this.max = 150, this.prefix});
  final TextEditingController controller; final String hint; final bool angka; final ValueChanged<String>? onChanged; final double min; final double max; final String? prefix;
  @override State<_AutoField> createState() => _AutoFieldS();
}
class _AutoFieldS extends State<_AutoField> {
  double w = 56;
  @override void initState() { super.initState(); _ukur(); widget.controller.addListener(_ukur); }
  @override void dispose() { widget.controller.removeListener(_ukur); super.dispose(); }
  void _ukur() {
    final tp = TextPainter(text: TextSpan(text: widget.controller.text.isEmpty ? widget.hint : widget.controller.text, style: const TextStyle(fontSize: 13)), textDirection: TextDirection.ltr)..layout();
    final nw = (tp.width + 26 + (widget.prefix != null ? 28 : 0)).clamp(widget.min, widget.max);
    if ((nw - w).abs() > 1) setState(() => w = nw);
  }
  @override Widget build(BuildContext context) {
    return SizedBox(width: w, child: TextField(controller: widget.controller, keyboardType: widget.angka ? TextInputType.number : TextInputType.text, textAlign: widget.angka ? TextAlign.center : TextAlign.left, style: const TextStyle(fontSize: 13), decoration: InputDecoration(hintText: widget.hint, prefixText: widget.prefix, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11), border: const OutlineInputBorder()), onChanged: (v) { _ukur(); widget.onChanged?.call(v); }));
  }
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
  bool poTerbuka = false; // PO maximize: false = kalkulator full layar, true = panel PO full layar + tombol X
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
    final acuan = hargaAcuan; final nilaiManual = manual; final warna = warnaSaran();
    final namaWarna = warna == Colors.black ? "HITAM - belum ada acuan" : warna == const Color(0xFFB71C1C) ? "MERAH TUA - rugi besar" : warna == Colors.red ? "MERAH - rugi" : warna == const Color(0xFFB58900) ? "KUNING - waspada" : warna == Colors.blue ? "BIRU - untung kecil" : "HIJAU - untung";
    final bep = acuan > 0 ? acuan * 1.1 : 0;
    final totalStep = steps.fold<double>(0, (a, x) => a + ((x["jumlah"] as num?)?.toDouble() ?? 0));
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("BABE.INFO - Dialog Uni"),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text("Barang: $namaBarang", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        Text("Unit Biru: ${unitCtrl.text}", style: const TextStyle(fontSize: 11)),
        const Divider(),
        Text("Layar: $layar | Acuan: ${acuan == 0 ? "---" : formatRupiah(acuan.toInt())} | Persen: ${acuan == 0 || nilaiManual == 0 ? "---" : "${persen.toStringAsFixed(1)}%"}", style: TextStyle(fontSize: 11, color: warna)),
        Text("Warna: $namaWarna | BEP: ${bep == 0 ? "---" : formatRupiah(bep.toInt())} | Memori: ${formatRupiah(memori.toInt())}", style: const TextStyle(fontSize: 11)),
        const Divider(), const Text("SATUAN", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        ...satuanList.map((x) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text("${teksRumusSatuan(x)}${x.nominalManual ? " \u2022 MANUAL" : " \u2022 AUTO"}", style: const TextStyle(fontSize: 11)))),
        const Divider(), const Text("CEK - STEP", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        if (steps.isEmpty) const Text("Belum ada step.", style: TextStyle(fontSize: 11)),
        ...steps.asMap().entries.map((e) => Text("${e.key + 1}. ${e.value["item"]} | ${formatRupiah((e.value["harga"] as num).toInt())} x ${e.value["qty"]} = ${formatRupiah((e.value["jumlah"] as num).toInt())}", style: const TextStyle(fontSize: 11))),
        if (steps.isNotEmpty) Text("Total step: ${formatRupiah(totalStep.toInt())}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const Divider(), const Text("\u2022 Harga 1 = harga per Unit Biru.\n\u2022 1 sak \u00f7 50 kg = 1.000 / kg\n\u2022 1 m x 3 = 75.000 / 3m\n\u2022 BEP = Acuan x 110%.", style: TextStyle(fontSize: 11)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup"))]));
  }
  void refreshSemuaNominal() { for (var s in satuanList) refreshNominal(s); }
  void bukaCek() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) => Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 12),
        child: SizedBox(height: 440, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CEK - Proses Kalkulasi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
          const SizedBox(height: 8),
          if (steps.isEmpty) const Text("Belum ada step. Pencet = atau M+ dulu."),
          Expanded(child: ListView.builder(itemCount: steps.length, itemBuilder: (_, i) {
            final s = steps[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Expanded(child: TextField(controller: TextEditingController(text: "${s["item"]}"), style: const TextStyle(fontSize: 12), decoration: dec("Item"), onChanged: (v) => s["item"] = v)),
                const SizedBox(width: 4),
                _AutoField(controller: TextEditingController(text: "${s["harga"]}"), hint: "Harga", angka: true, min: 56, max: 120, onChanged: (v) => setSheet(() { s["harga"] = double.tryParse(v) ?? 0; s["jumlah"] = (s["harga"] as double) * (s["qty"] as num); })),
                const SizedBox(width: 4),
                _AutoField(controller: TextEditingController(text: "${s["qty"]}"), hint: "Qty", angka: true, min: 44, max: 90, onChanged: (v) => setSheet(() { s["qty"] = double.tryParse(v) ?? 0; s["jumlah"] = (s["harga"] as double) * (s["qty"] as num); })),
                const SizedBox(width: 4),
                Expanded(child: Text(formatRupiah((s["jumlah"] as num).toInt()), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () { setSheet(() => steps.removeAt(i)); setState(() {}); }),
              ]));
          })),
        ])))));
  }

  void pencet(String t) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC" || t == "ON/C") { layar = "0"; op = ""; angka1 = 0; }
      else if (t == "PO") { poTerbuka = true; }
      else if (t == "LS") { bukaListLS(); }
      else if (t == "CEK") { bukaCek(); }
      else if (t == "OFF") { layar = "0"; }
      else if (t == "BEP") {
        if (hargaAcuan > 0) { layar = formatHasil(hargaAcuan * 1.1); }
        else { layar = formatHasil((double.tryParse(layar) ?? 0) + 120); }
      }
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
      else if (t == "MU") { layar = formatHasil((double.tryParse(layar) ?? 0) * 1.1); }
      else if (t == "\u25b6" || t == "\u232b") {
        if (layar.length > 1) { layar = layar.substring(0, layar.length - 1); } else { layar = "0"; }
      }
      else if (["+", "-", "x", "\u00f7", "/"].contains(t)) { angka1 = double.tryParse(layar) ?? 0; op = t; layar = "0"; }
      else if (t == "=") {
        final a2 = double.tryParse(layar) ?? 0;
        double h = 0;
        if (op == "+") { h = angka1 + a2; }
        if (op == "-") { h = angka1 - a2; }
        if (op == "x") { h = angka1 * a2; }
        if (op == "/" || op == "\u00f7") { h = a2 == 0 ? 0 : angka1 / a2; }
        layar = formatHasil(h);
        steps.add({"item": barangDipilih?["nama"] ?? "Hitung", "harga": angka1, "qty": a2, "jumlah": h});
        op = "";
      }
      else if (t == "+/-") {
        if (layar.startsWith("-")) { layar = layar.substring(1); }
        else if (layar != "0") { layar = "-$layar"; }
      }
      else if (t == "%") { layar = formatHasil((double.tryParse(layar) ?? 0) / 100); }
      else {
        if (layar == "0") { layar = t; } else { layar += t; }
      }
    });
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
              return b["nama"].toString().toLowerCase().contains(q) ||
                  b["kode"].toString().toLowerCase().contains(q) ||
                  b["kategori"].toString().toLowerCase().contains(q);
            }).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 12, right: 12, top: 12),
              child: SizedBox(
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("LS - List Barang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () { Navigator.pop(ctx); bukaFormTambahBarang(); },
                              child: const Text("+ Tambah Barang"),
                            ),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                          ],
                        ),
                      ],
                    ),
                    TextField(
                      decoration: dec("Cari kode / nama / kategori..."),
                      onChanged: (v) {
                        setSheet(() { queryLS = v; });
                        setState(() { queryLS = v; });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text("Belum ada barang. Tap + Tambah Barang."))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final b = filtered[i];
                                final aktif = barangDipilih != null && barangDipilih!["kode"] == b["kode"];
                                final satuanBarang = (b["satuanList"] as List?) ?? [];
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      barangDipilih = {
                                        "kode": b["kode"].toString(),
                                        "nama": b["nama"].toString(),
                                        "kategori": b["kategori"].toString(),
                                        "harga1": b["harga1"].toString(),
                                      };
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: aktif ? Colors.green.shade100 : Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              child: Text(
                                                b["nama"].toString().isEmpty ? "?" : b["nama"].toString()[0].toLowerCase(),
                                                style: const TextStyle(fontSize: 14),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text("${b["nama"]}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                  Text("${b["kode"]} \u2022 ${b["kategori"]} \u2022 ${b["satuan"] ?? "pcs"}", style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(formatRupiah(int.tryParse(b["harga1"].toString()) ?? 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        if (satuanBarang.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: satuanBarang.map<Widget>((x) {
                                              final m = Map<String, dynamic>.from(x as Map);
                                              final nom = double.tryParse(m["nominal"].toString()) ?? 0;
                                              return ActionChip(
                                                label: Text("${m["satuan"]} - ${formatRupiah(nom.toInt())}", style: const TextStyle(fontSize: 10)),
                                                onPressed: () {
                                                  setState(() {
                                                    barangDipilih = {
                                                      "kode": b["kode"].toString(),
                                                      "nama": b["nama"].toString(),
                                                      "kategori": b["kategori"].toString(),
                                                      "harga1": nom.toInt().toString(),
                                                    };
                                                    layar = nom.toStringAsFixed(0);
                                                  });
                                                  Navigator.pop(ctx);
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void bukaFormTambahBarang() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 12, right: 12, top: 12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Tambah Barang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: kodeCtrl, decoration: dec("Code *"))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: namaCtrl, decoration: dec("Name *"))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Category \u2022 dropdown + tambah/delete", style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: kategoriPilih,
                                decoration: dec("Kategori"),
                                items: listKategori.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (v) { if (v != null) { setSheet(() { kategoriPilih = v; }); } },
                              ),
                              Row(
                                children: [
                                  Expanded(child: TextField(controller: kategoriBaruCtrl, decoration: dec("Kategori baru"))),
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () {
                                      if (kategoriBaruCtrl.text.isNotEmpty) {
                                        setSheet(() { listKategori.add(kategoriBaruCtrl.text); kategoriPilih = kategoriBaruCtrl.text; kategoriBaruCtrl.clear(); });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setSheet(() {
                                        if (listKategori.length > 1) { listKategori.remove(kategoriPilih); kategoriPilih = listKategori.first; }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: unitCtrl,
                            decoration: dec("Unit"),
                            onChanged: (v) {
                              tambahKeDaftarSatuan(v);
                              for (var x in satuanList) { x.satuanBaruCtrl.text = v; }
                              setSheet(() => refreshSemuaNominal());
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text("Harga 1 \u2022 Acuan 100%", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 4),
                    TextField(controller: harga1Ctrl, keyboardType: TextInputType.number, decoration: dec("0"), onChanged: (v) => setSheet(() => refreshSemuaNominal())),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFFFF8C5), borderRadius: BorderRadius.circular(8)),
                      child: const Text("Harga 1 ini yang jadi acuan prosentase 100%. Harga 2 dan 3 tidak perlu ditampilkan, input manual edit harga 1 menjadi harga 2 dan 3 sudah ada di PO.", style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Varian", style: TextStyle(fontWeight: FontWeight.bold)),
                        ElevatedButton(onPressed: () => setSheet(() => varianCtrls.add(TextEditingController())), child: const Text("+Tambah Varian", style: TextStyle(fontSize: 11))),
                      ],
                    ),
                    ...varianCtrls.asMap().entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(child: TextField(controller: e.value, decoration: dec("Hitam"), onChanged: (v) => tambahKeDaftarSatuan(v))),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setSheet(() { if (varianCtrls.length > 1) { varianCtrls.removeAt(e.key); } })),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Satuan", style: TextStyle(fontWeight: FontWeight.bold)),
                        ElevatedButton(
                          onPressed: () => setSheet(() {
                            satuanList.add(SatuanItem(satuan: unitCtrl.text, dasar: false, qty: "1", isi: "1", op: "x", nominal: harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''), satuanBaru: unitCtrl.text));
                            tambahKeDaftarSatuan(unitCtrl.text);
                          }),
                          child: const Text("+Tambah Satuan", style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    const Text("Qty + satuan, x/\u00f7, isi + unit = nominal.", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 6),
                    ...satuanList.asMap().entries.map((e) {
                      final s = e.value;
                      final dasarNama = satuanList.firstWhere((x) => x.dasar == true, orElse: () => satuanList.first).namaCtrl.text;
                      if (s.satuanBaruCtrl.text.isEmpty) { s.satuanBaruCtrl.text = dasarNama; }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Colors.white),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _AutoField(controller: s.qtyCtrl, hint: "1", angka: true, min: 44, max: 90, onChanged: (v) => setSheet(() { s.nominalManual = false; refreshNominal(s); })),
                                const SizedBox(width: 4),
                                _AutoField(
                                  controller: s.namaCtrl,
                                  hint: "satuan",
                                  min: 52,
                                  max: 140,
                                  onChanged: (v) {
                                    tambahKeDaftarSatuan(v);
                                    if (s.dasar) {
                                      unitCtrl.text = v;
                                      for (var x in satuanList) { if (x != s) { x.satuanBaruCtrl.text = v; } }
                                    }
                                    setSheet(() => refreshNominal(s));
                                  },
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: InkWell(
                                    onTap: () => setSheet(() { s.op = s.op == "x" ? "\u00f7" : "x"; s.nominalManual = false; refreshNominal(s); }),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      decoration: BoxDecoration(color: s.op == "\u00f7" ? Colors.teal.shade100 : Colors.orange.shade100, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400)),
                                      child: Center(child: Text(s.op, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _AutoField(controller: s.isiCtrl, hint: "isi", angka: true, min: 44, max: 90, onChanged: (v) => setSheet(() { s.nominalManual = false; refreshNominal(s); })),
                                const SizedBox(width: 4),
                                _AutoField(
                                  controller: s.satuanBaruCtrl,
                                  hint: "unit",
                                  min: 52,
                                  max: 140,
                                  onChanged: (v) {
                                    tambahKeDaftarSatuan(v);
                                    if (s.dasar) { unitCtrl.text = v; }
                                    setSheet(() => refreshNominal(s));
                                  },
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  tooltip: s.dasar ? "Dasar" : "Jadikan dasar",
                                  icon: Icon(s.dasar ? Icons.check_circle : Icons.radio_button_unchecked, color: s.dasar ? Colors.green : Colors.grey, size: 22),
                                  onPressed: () => setSheet(() {
                                    for (var x in satuanList) { x.dasar = false; }
                                    s.dasar = true;
                                    syncUnitDariDasar();
                                    for (var x in satuanList) { x.satuanBaruCtrl.text = unitCtrl.text; }
                                    refreshSemuaNominal();
                                  }),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  onPressed: () => setSheet(() { if (satuanList.length > 1) { satuanList.removeAt(e.key); } }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(controller: s.nominalCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13), decoration: dec("nominal", prefix: "Rp "), onTap: () => s.nominalManual = true, onChanged: (v) => s.nominalManual = true),
                            const SizedBox(height: 4),
                            SizedBox(width: double.infinity, child: Text(teksRumusSatuan(s), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                        onPressed: () {
                          final varian = varianCtrls.map((c) => c.text).join(", ");
                          for (var c in varianCtrls) { tambahKeDaftarSatuan(c.text); }
                          for (var x in satuanList) { tambahKeDaftarSatuan(x.namaCtrl.text); tambahKeDaftarSatuan(x.satuanBaruCtrl.text); }
                          setState(() {
                            daftarBarang.add({
                              "kode": kodeCtrl.text,
                              "nama": namaCtrl.text,
                              "kategori": kategoriPilih,
                              "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
                              "satuan": unitCtrl.text,
                              "varian": varian,
                              "satuanList": satuanList.map((x) => x.toMap()).toList(),
                            });
                            barangDipilih = {
                              "kode": kodeCtrl.text,
                              "nama": namaCtrl.text,
                              "kategori": kategoriPilih,
                              "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
                            };
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text("Simpan Barang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  Widget tombol(String label, {Color? bg, Color? fg, bool besar = false}) {
    final isDown = tombolDitekan == label && tekanTombol;
    final baseColor = bg ?? Colors.white;
    final shadowColor = baseColor == Colors.white ? Colors.grey.shade400 : Colors.black26;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: GestureDetector(
          onTapDown: (_) => setState(() { tombolDitekan = label; tekanTombol = true; }),
          onTapUp: (_) { setState(() { tekanTombol = false; }); pencet(label); },
          onTapCancel: () => setState(() { tekanTombol = false; }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: double.infinity,
            transform: Matrix4.translationValues(0, isDown ? 2 : 0, 0),
            decoration: BoxDecoration(
              color: isDown ? baseColor.withValues(alpha: 0.85) : baseColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
              boxShadow: isDown ? [] : [BoxShadow(color: shadowColor, offset: const Offset(0, 3), blurRadius: 0), BoxShadow(color: Colors.white.withValues(alpha: 0.6), offset: const Offset(0, -1), blurRadius: 0)],
            ),
            child: Center(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: besar ? 16 : 14, fontWeight: FontWeight.bold, color: fg ?? Colors.black))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final po = ref.watch(poProvider);
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    final headerKalkulator = Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("BASKORO WINGCHUN", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              GestureDetector(onTap: dialogBabe, child: const Text("BABE.INFO - dialog kalkulasi", style: TextStyle(color: Colors.white70, fontSize: 9, decoration: TextDecoration.underline))),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFDDE8D0), borderRadius: BorderRadius.circular(6)),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(teksAcuan(), style: const TextStyle(fontSize: 12, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(layar, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: Text(barangDipilih == null ? "Pilih barang via LS" : "${barangDipilih!["nama"]} \u2022 ${barangDipilih!["kategori"]}", style: const TextStyle(fontSize: 9, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text(teksSaran(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: warnaSaran())),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () => setState(() { modeHitung = modeHitung == "PEMBULATAN" ? "ORIGINAL" : "PEMBULATAN"; }),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: const Text("5/4", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 4),
                        Expanded(child: Text(modeHitung, style: const TextStyle(color: Colors.white, fontSize: 9), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text("0", style: TextStyle(fontSize: 9))),
                      ButtonSegment(value: 2, label: Text("2", style: TextStyle(fontSize: 9))),
                      ButtonSegment(value: 3, label: Text("3", style: TextStyle(fontSize: 9))),
                    ],
                    selected: {desimal},
                    onSelectionChanged: (s) => setState(() { desimal = s.first; }),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: () {}, style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 10)), child: const Text("Kirim WA")))),
              const SizedBox(width: 4),
              Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 9), backgroundColor: Colors.white), child: const Text("Nota")))),
            ],
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFFE8E0C8),
      body: SafeArea(
        child: Column(
          children: [
            headerKalkulator,
            if (poTerbuka)
              Expanded(
                child: Container(
                  color: const Color(0xFF2E2E2E),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("PO - Daftar Item", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white), tooltip: "Tutup PO, balik ke keypad", onPressed: () => setState(() { poTerbuka = false; })),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: po.items.isEmpty
                            ? const Center(child: Text("Belum ada item - pencet LS pilih barang, lalu M+", style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center))
                            : ListView.builder(
                                itemCount: po.items.length,
                                itemBuilder: (_, i) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text("${i + 1}. ${po.items[i].namaBarang} - ${po.items[i].qty}x ${formatRupiah(po.items[i].hargaSatuan)}", style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                        IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => ref.read(poProvider.notifier).hapusItem(i)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Subtotal: ${formatRupiah(hasil.subtotal)}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                            Text("Total: ${formatRupiah(hasil.totalAkhir)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Expanded(child: Row(children: [tombol("AC", bg: Colors.blue.shade400, fg: Colors.white), tombol("MRC", bg: Colors.grey.shade400), tombol("M-", bg: Colors.grey.shade400), tombol("M+", bg: Colors.green, fg: Colors.white, besar: true), tombol("LS", bg: Colors.orange.shade100, besar: true), tombol("CEK", bg: Colors.black, fg: Colors.white), tombol("BEP", bg: Colors.pink, fg: Colors.white)])),
                      Expanded(child: Row(children: [tombol("OFF", bg: Colors.blue.shade400, fg: Colors.white), tombol("7"), tombol("8"), tombol("9"), tombol("\u25b6", bg: Colors.grey.shade300), tombol("MU", bg: Colors.grey.shade300), tombol("MC", bg: Colors.grey.shade300)])),
                      Expanded(child: Row(children: [tombol("%", bg: Colors.grey.shade300), tombol("4"), tombol("5"), tombol("6"), tombol("-", bg: Colors.grey.shade300), tombol("\u00f7", bg: Colors.grey.shade300), tombol("MR", bg: Colors.grey.shade300)])),
                      Expanded(child: Row(children: [tombol("+/-", bg: Colors.grey.shade300), tombol("1"), tombol("2"), tombol("3"), tombol("+", bg: Colors.grey.shade300), tombol("x", bg: Colors.grey.shade300), tombol("PO", bg: Colors.teal, fg: Colors.white)])),
                      Expanded(child: Row(children: [tombol("ON/C", bg: Colors.blue.shade400, fg: Colors.white), tombol("0"), tombol("00"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true), tombol("M+", bg: Colors.green, fg: Colors.white), tombol("\u232b", bg: Colors.grey.shade300)])),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

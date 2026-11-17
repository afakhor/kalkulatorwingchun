import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/formatter.dart';
import 'po_provider.dart';
import 'parse_cepat.dart';

class HomeDaftarPO extends ConsumerStatefulWidget {
  const HomeDaftarPO({super.key});
  @override
  ConsumerState<HomeDaftarPO> createState() => _S();
}

class _S extends ConsumerState<HomeDaftarPO> {
  // LAYAR
  String layar = "0";
  String layarKetik = "";
  String op = "";
  double angka1 = 0;

  // MASTER BARANG - font dikecilin, compact
  final kodeCtrl = TextEditingController();
  final kategoriCtrl = TextEditingController();
  final namaCtrl = TextEditingController();
  final variasiCtrl = TextEditingController();
  final satuanCtrl = TextEditingController(text: "pcs");
  final hargaCtrl = TextEditingController();
  final ongkirCtrl = TextEditingController(text: "0");
  final diskonCtrl = TextEditingController(text: "0");

  // LIST HASIL INPUT - lingkaran kuning
  final List<Map<String, String>> daftarBarang = [];
  int selectedBarang = -1;

  // PEMBULATAN - pindah ke atas sesuai panah putih
  String pembulatan = "PEMBULATAN / ORIGINAL";

  // HITUNG ACUAN & SARAN
  double get hargaAcuan {
    if (selectedBarang >= 0 && selectedBarang < daftarBarang.length) {
      return double.tryParse(daftarBarang[selectedBarang]["harga"] ?? "0") ?? 0;
    }
    return double.tryParse(hargaCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  double get biayaOperasional {
    final o = double.tryParse(ongkirCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final d = double.tryParse(diskonCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return o - d;
  }

  double get manual {
    return double.tryParse(layar) ?? 0;
  }

  double get persen {
    if (hargaAcuan == 0) {
      return 0;
    }
    final modal = hargaAcuan + biayaOperasional;
    if (modal == 0) {
      return 0;
    }
    return (manual - modal) / modal * 100;
  }

  Color warnaSaran() {
    if (hargaAcuan == 0) {
      return Colors.black;
    }
    if (manual == 0) {
      return Colors.black;
    }
    if (persen < -20) {
      return const Color(0xFFB71C1C);
    }
    if (persen < 0) {
      return Colors.red;
    }
    if (persen < 5) {
      return const Color(0xFFB58900);
    }
    if (persen < 15) {
      return Colors.blue;
    }
    return Colors.green;
  }

  String teksAcuan() {
    if (hargaAcuan == 0) {
      return "---";
    }
    return formatRupiah(hargaAcuan.toInt());
  }

  String teksSaran() {
    if (hargaAcuan == 0) {
      return "---";
    }
    if (manual == 0) {
      return "---";
    }
    return "${persen.toStringAsFixed(1)}%";
  }

  void pencet(String t) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC" || t == "ON/C") {
        layar = "0";
        op = "";
        angka1 = 0;
        layarKetik = "";
      } else if (t == "OFF") {
        layar = "0";
      } else if (["+", "-", "x", "÷", "/"].contains(t)) {
        angka1 = double.tryParse(layar) ?? 0;
        op = t;
        layar = "0";
      } else if (t == "=") {
        final a2 = double.tryParse(layar) ?? 0;
        double h = 0;
        if (op == "+") {
          h = angka1 + a2;
        }
        if (op == "-") {
          h = angka1 - a2;
        }
        if (op == "x") {
          h = angka1 * a2;
        }
        if (op == "/" || op == "÷") {
          if (a2 == 0) {
            h = 0;
          } else {
            h = angka1 / a2;
          }
        }
        layar = h.toStringAsFixed(0);
        op = "";
      } else if (t == "M+") {
        final item = parseInputCepat(layarKetik.isEmpty ? "${layar}x ${namaCtrl.text} ${hargaCtrl.text}" : layarKetik);
        if (item != null) {
          ref.read(poProvider.notifier).tambahItem(item);
        } else {
          if (namaCtrl.text.isNotEmpty) {
            final qty = int.tryParse(layar) ?? 1;
            final harga = int.tryParse(hargaCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            final it = parseInputCepat("$qty x ${namaCtrl.text} $harga");
            if (it != null) {
              ref.read(poProvider.notifier).tambahItem(it);
            }
          }
        }
        layar = "0";
      } else if (t == "120") {
        layar = ((double.tryParse(layar) ?? 0) + 120).toStringAsFixed(0);
      } else if (t == "+/-") {
        if (layar.startsWith("-")) {
          layar = layar.substring(1);
        } else {
          if (layar != "0") {
            layar = "-$layar";
          }
        }
      } else if (t == "%") {
        final v = (double.tryParse(layar) ?? 0) / 100;
        layar = v.toStringAsFixed(0);
      } else {
        if (layar == "0") {
          layar = t;
        } else {
          layar += t;
        }
        if (t.length <= 2) {
          layarKetik += t;
        }
      }
    });
  }

  void simpanBarang() {
    if (namaCtrl.text.isEmpty) {
      return;
    }
    setState(() {
      daftarBarang.add({
        "kode": kodeCtrl.text,
        "kategori": kategoriCtrl.text,
        "nama": namaCtrl.text,
        "variasi": variasiCtrl.text,
        "satuan": satuanCtrl.text,
        "harga": hargaCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
      });
      kodeCtrl.clear();
      kategoriCtrl.clear();
      namaCtrl.clear();
      variasiCtrl.clear();
      hargaCtrl.clear();
    });
  }

  void klikBarang(int i) {
    setState(() {
      if (selectedBarang == i) {
        selectedBarang = -1;
      } else {
        selectedBarang = i;
        final b = daftarBarang[i];
        namaCtrl.text = b["nama"] ?? "";
        hargaCtrl.text = b["harga"] ?? "";
        variasiCtrl.text = b["variasi"] ?? "";
        satuanCtrl.text = b["satuan"] ?? "";
      }
    });
  }

  Widget tombol(String label, {Color? bg, Color? fg, bool besar = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: SizedBox(
          height: besar ? 58 : 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: bg ?? Colors.white,
              foregroundColor: fg ?? Colors.black,
              padding: EdgeInsets.zero,
              textStyle: TextStyle(fontSize: besar ? 18 : 15, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => pencet(label),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget inputKecil(TextEditingController c, String label, {TextInputType? type, Function(String)? onChanged}) {
    return Expanded(
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: c,
          keyboardType: type ?? TextInputType.text,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 10),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final po = ref.watch(poProvider);
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    return Scaffold(
      backgroundColor: const Color(0xFFE8E0C8),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // ===== HIJAU - DIPENDEKKAN, BENTUK KAYAK FOTO PERTAMA =====
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text("2 POWER", style: TextStyle(color: Colors.white70, fontSize: 9)),
                        Text("ELECTRONIC CALCULATOR", style: TextStyle(color: Colors.white70, fontSize: 9)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFDDE8D0), borderRadius: BorderRadius.circular(6)),
                      child: Column(
                        children: [
                          // Baris 1: --- (acuan) kiri, 0 (manual) kanan
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(teksAcuan(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              Text(layar, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
                            ],
                          ),
                          // Baris 2: --- saran, berubah warna
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("SARAN:", style: TextStyle(fontSize: 9, color: Colors.black54)),
                              Text(teksSaran(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: warnaSaran())),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // ===== PUTIH - PINDAH SESUAI PANAH, LANGSUNG DI BAWAH LAYAR =====
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: const Text("5/4", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 6),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: pembulatan,
                                isDense: true,
                                style: const TextStyle(color: Colors.white, fontSize: 9),
                                dropdownColor: Colors.black,
                                items: [pembulatan, "PEMBULATAN", "ORIGINAL"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 9)))).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      pembulatan = v;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black)),
                    child: Row(children: ["A", "0", "2", "3", "F"].map((e) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(e, style: const TextStyle(fontSize: 9)))).toList()),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ===== BIRU - DIKECILIN, NGGAK GANGGU BENTUK KALKULATOR =====
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF5EFE0), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("— MASTER BARANG", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                    const SizedBox(height: 4),
                    Row(children: [inputKecil(kodeCtrl, "Kode"), const SizedBox(width: 4), inputKecil(kategoriCtrl, "Kategori")]),
                    const SizedBox(height: 4),
                    Row(children: [inputKecil(namaCtrl, "Nama Barang")]),
                    const SizedBox(height: 4),
                    Row(children: [inputKecil(variasiCtrl, "Variasi"), const SizedBox(width: 4), inputKecil(satuanCtrl, "Satuan"), const SizedBox(width: 4), inputKecil(hargaCtrl, "Harga", type: TextInputType.number, onChanged: (_) => setState(() {}))]),
                    const SizedBox(height: 4),
                    Row(children: [inputKecil(ongkirCtrl, "Ongkir / Operasional", type: TextInputType.number, onChanged: (_) => setState(() {})), const SizedBox(width: 4), inputKecil(diskonCtrl, "Diskon", type: TextInputType.number, onChanged: (_) => setState(() {}))]),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 28,
                      child: ElevatedButton(onPressed: simpanBarang, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text("Simpan ke List", style: TextStyle(fontSize: 11))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // ===== KUNING - LIST HASIL INPUT BARANG, KLIK JADI ACUAN =====
              if (daftarBarang.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("LIST BAHAN - KLIK UNTUK JADI ACUAN", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                      const SizedBox(height: 4),
                      ...daftarBarang.asMap().entries.map((e) {
                        final aktif = selectedBarang == e.key;
                        return InkWell(
                          onTap: () => klikBarang(e.key),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(color: aktif ? Colors.green.shade100 : Colors.grey.shade100, borderRadius: BorderRadius.circular(4), border: Border.all(color: aktif ? Colors.green : Colors.grey.shade300)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text("${e.value["nama"]} ${e.value["variasi"]} (${e.value["satuan"]})", style: const TextStyle(fontSize: 11))),
                                Text(e.value["harga"]!.isEmpty ? "---" : formatRupiah(int.tryParse(e.value["harga"]!) ?? 0), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: aktif ? Colors.green : Colors.black)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // ===== KEYBOARD - BENTUK KAYAK FOTO PERTAMA, PENDEK =====
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFE8E0C8), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Row(children: [tombol("AC", bg: Colors.blue.shade300, fg: Colors.white), tombol("MRC", bg: Colors.grey.shade400), tombol("M-", bg: Colors.grey.shade400), tombol("M+", bg: Colors.green, fg: Colors.white, besar: true)]),
                    Row(children: [tombol("OFF", bg: Colors.blue.shade300, fg: Colors.white), tombol("7"), tombol("8"), tombol("9"), tombol("◀", bg: Colors.grey.shade300)]),
                    Row(children: [tombol("%", bg: Colors.grey.shade300), tombol("4"), tombol("5"), tombol("6"), tombol("-", bg: Colors.grey.shade300)]),
                    Row(children: [tombol("+/-", bg: Colors.grey.shade300), tombol("1"), tombol("2"), tombol("3"), tombol("+", bg: Colors.grey.shade300)]),
                    Row(children: [tombol("ON/C", bg: Colors.blue.shade300, fg: Colors.white), tombol("0"), tombol("00"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true)]),
                    Row(children: [tombol("120", bg: Colors.orange, fg: Colors.white), tombol("000", bg: Colors.grey.shade300), tombol("MU", bg: Colors.grey.shade300), tombol("MC", bg: Colors.grey.shade300)]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // BARIS PO
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF2E2E2E), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("BARIS PO - MEMORI + TAMBAH PO", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    if (po.items.isEmpty) const Text("Belum ada item - pencet M+ untuk tambah", style: TextStyle(color: Colors.white70, fontSize: 11)),
                    if (po.items.isNotEmpty)
                      ...po.items.asMap().entries.map((e) => Container(
                            margin: const EdgeInsets.only(bottom: 3),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text("${e.key + 1}. ${e.value.namaBarang} - ${e.value.qty}x ${formatRupiah(e.value.hargaSatuan)}", style: const TextStyle(fontSize: 11))),
                                IconButton(icon: const Icon(Icons.delete, size: 14), onPressed: () => ref.read(poProvider.notifier).hapusItem(e.key), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                              ],
                            ),
                          )),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Subtotal: ${formatRupiah(hasil.subtotal)}", style: const TextStyle(color: Colors.white, fontSize: 11)), Text("Total: ${formatRupiah(hasil.totalAkhir)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: FilledButton(onPressed: () {}, child: const Text("Kirim WA"))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () {}, child: const Text("Screenshot Nota")))]),
            ],
          ),
        ),
      ),
    );
  }
}
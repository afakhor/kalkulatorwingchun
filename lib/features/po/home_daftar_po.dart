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
  String layar = "0";
  String layarKetik = "";
  String op = "";
  double angka1 = 0;

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
  final ongkirCtrl = TextEditingController(text: "0");
  final diskonCtrl = TextEditingController(text: "0");
  final List<TextEditingController> varianCtrls = [TextEditingController(text: "Hitam")];
  List<Map<String, dynamic>> satuanList = [
    {"satuan": "pcs", "dasar": true, "isi": "1"},
    {"satuan": "dus", "dasar": false, "isi": "10"},
  ];

  double get hargaAcuan {
    if (barangDipilih != null) {
      return double.tryParse("${barangDipilih!["harga1"]}") ?? 0;
    }
    return 0;
  }

  double get biayaOperasional {
    final o = double.tryParse(ongkirCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final d = double.tryParse(diskonCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return o - d;
  }

  double get manual => double.tryParse(layar) ?? 0;

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
      } else if (t == "LS") {
        bukaListLS();
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
        if (barangDipilih != null) {
          final qty = int.tryParse(layar) ?? 1;
          final harga = int.tryParse("${barangDipilih!["harga1"]}") ?? 0;
          final it = parseInputCepat("$qty x ${barangDipilih!["nama"]} $harga");
          if (it != null) {
            ref.read(poProvider.notifier).tambahItem(it);
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

  void bukaListLS() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            final q = queryLS.toLowerCase();
            final filtered = daftarBarang.where((b) {
              final nama = "${b["nama"]}".toLowerCase();
              final kode = "${b["kode"]}".toLowerCase();
              final kat = "${b["kategori"]}".toLowerCase();
              if (q.isEmpty) {
                return true;
              }
              return nama.contains(q) || kode.contains(q) || kat.contains(q);
            }).toList();
            final suggestions = filtered.take(5).toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SizedBox(
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "LS - List Barang",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                bukaFormTambahBarang();
                              },
                              child: const Text("+ Tambah Barang"),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ],
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: "Cari kode / nama / kategori...",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setSheet(() {
                          queryLS = v;
                        });
                        setState(() {
                          queryLS = v;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    if (suggestions.isNotEmpty) ...[
                      const Text(
                        "Auto Suggestion:",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: suggestions
                            .map(
                              (b) => ActionChip(
                                label: Text(
                                  "${b["nama"]}",
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  setState(() {
                                    barangDipilih = {
                                      "kode": "${b["kode"]}",
                                      "nama": "${b["nama"]}",
                                      "kategori": "${b["kategori"]}",
                                      "harga1": "${b["harga1"]}",
                                    };
                                  });
                                  Navigator.pop(ctx);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Colors.blue, thickness: 2),
                    ],
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text("Belum ada barang. Tap + Tambah Barang."),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final b = filtered[i];
                                final aktif = barangDipilih != null &&
                                    barangDipilih!["kode"] == b["kode"];
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      "${b["nama"]}".isEmpty ? "?" : "${b["nama"]}"[0],
                                    ),
                                  ),
                                  title: Text("${b["nama"]}"),
                                  subtitle: Text(
                                    "${b["kode"]} • ${b["kategori"]} • ${b["satuan"] ?? "pcs"}",
                                  ),
                                  trailing: Text(
                                    formatRupiah(int.tryParse("${b["harga1"]}") ?? 0),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  tileColor: aktif ? Colors.green.shade100 : null,
                                  onTap: () {
                                    setState(() {
                                      barangDipilih = {
                                        "kode": "${b["kode"]}",
                                        "nama": "${b["nama"]}",
                                        "kategori": "${b["kategori"]}",
                                        "harga1": "${b["harga1"]}",
                                      };
                                    });
                                    Navigator.pop(ctx);
                                  },
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Tambah Barang",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: kodeCtrl,
                            decoration: const InputDecoration(
                              labelText: "Code *",
                              hintText: "EL011",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: namaCtrl,
                            decoration: const InputDecoration(
                              labelText: "Name *",
                              hintText: "Nama barang",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Category • dropdown + tambah/delete",
                                style: TextStyle(fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              // FIX 1: value -> initialValue
                              DropdownButtonFormField<String>(
                                initialValue: kategoriPilih,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                                items: listKategori
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setSheet(() {
                                      kategoriPilih = v;
                                    });
                                  }
                                },
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: kategoriBaruCtrl,
                                      decoration: const InputDecoration(
                                        hintText: "Kategori baru",
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () {
                                      if (kategoriBaruCtrl.text.isNotEmpty) {
                                        setSheet(() {
                                          listKategori.add(kategoriBaruCtrl.text);
                                          kategoriPilih = kategoriBaruCtrl.text;
                                          kategoriBaruCtrl.clear();
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setSheet(() {
                                        if (listKategori.length > 1) {
                                          listKategori.remove(kategoriPilih);
                                          kategoriPilih = listKategori.first;
                                        }
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
                            decoration: const InputDecoration(
                              labelText: "Unit",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Harga 1 • Acuan 100%",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: harga1Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: "0",
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8C5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Harga 1 ini yang jadi acuan prosentase 100% sedang harga 2 dan 3 tidak perlu ditampilkan, input manual edit harga 1 menjadi harga 2 dan 3 benar sudah ada di PO",
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Varian", style: TextStyle(fontWeight: FontWeight.bold)),
                        ElevatedButton(
                          onPressed: () {
                            setSheet(() {
                              varianCtrls.add(TextEditingController());
                            });
                          },
                          child: const Text("+Tambah Varian", style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    ...varianCtrls.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: e.value,
                                    decoration: const InputDecoration(
                                      hintText: "Hitam",
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  onPressed: () {
                                    setSheet(() {
                                      if (varianCtrls.length > 1) {
                                        varianCtrls.removeAt(e.key);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 12),
                        Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Satuan", style: TextStyle(fontWeight: FontWeight.bold)),
                        ElevatedButton(
                          onPressed: () {
                            setSheet(() {
                              satuanList.add({"satuan": "", "dasar": false, "isi": "1"});
                            });
                          },
                          child: const Text("+Tambah Satuan", style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    ...satuanList.asMap().entries.map((e) {
                      final s = e.value;
                      final dasar = s["dasar"] == true;
                      final isi = "${s["isi"]}";
                      final dasarSatuan = satuanList.firstWhere(
                        (x) => x["dasar"] == true,
                        orElse: () => {"satuan": "pcs"},
                      )["satuan"];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            // SATUAN - INPUT MANUAL, BUKAN DROPDOWN LAGI
                            SizedBox(
                              width: 72,
                              child: TextField(
                                controller: TextEditingController(text: "${s["satuan"]}"),
                                decoration: const InputDecoration(
                                  hintText: "pcs",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  satuanList[e.key]["satuan"] = v;
                                },
                              ),
                            ),
                            // RADIO DASAR - tetap RadioGroup
                            RadioGroup<bool>(
                              groupValue: dasar,
                              onChanged: (bool? v) {
                                if (v == true) {
                                  setSheet(() {
                                    for (var x in satuanList) {
                                      x["dasar"] = false;
                                    }
                                    satuanList[e.key]["dasar"] = true;
                                  });
                                }
                              },
                              child: Radio<bool>(value: true),
                            ),
                            const Text("dasar", style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: TextEditingController(text: isi),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  satuanList[e.key]["isi"] = v;
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                dasar
                                    ? "1 ${s["satuan"]} = 1 $dasarSatuan"
                                    : "1 ${s["satuan"]} = $isi $dasarSatuan",
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 16),
                              onPressed: () {
                                setSheet(() {
                                  if (satuanList.length > 1) {
                                    satuanList.removeAt(e.key);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ongkirCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Ongkir / Operasional",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: diskonCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Diskon",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                        onPressed: () {
                          final varian = varianCtrls.map((c) => c.text).join(", ");
                          setState(() {
                            daftarBarang.add({
                              "kode": kodeCtrl.text,
                              "nama": namaCtrl.text,
                              "kategori": kategoriPilih,
                              "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
                              "satuan": unitCtrl.text,
                              "varian": varian,
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
                        child: const Text(
                          "Simpan Barang",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
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
              textStyle: TextStyle(
                fontSize: besar ? 18 : 15,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
      backgroundColor: const Color(0xFFE8E0C8),
      body: Column(
        children: [
          Container(height: 28, color: Colors.black),
          Container(height: 3, color: Colors.red),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("2 POWER", style: TextStyle(color: Colors.white70, fontSize: 9)),
                      Text("ELECTRONIC CALCULATOR", style: TextStyle(color: Colors.white70, fontSize: 9)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDE8D0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(teksAcuan(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            Text(layar, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("SARAN:", style: TextStyle(fontSize: 9, color: Colors.black54)),
                            Text(teksSaran(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              barangDipilih == null
                                  ? "Pilih barang via LS"
                                  : "${barangDipilih!["nama"]} • ${barangDipilih!["kategori"]}",
                              style: const TextStyle(fontSize: 9, color: Colors.black54),
                            ),
                            Text(teksSaran(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: warnaSaran())),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 3, color: Colors.blue),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              children: [
                                Text("  5/4  PEMBULATAN / ORIGINAL", style: TextStyle(color: Colors.white, fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black),
                          ),
                          child: const Row(children: [Text("A  0  2  3  F", style: TextStyle(fontSize: 9))]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (barangDipilih != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "Acuan: ${barangDipilih!["nama"]} • ${formatRupiah(int.tryParse("${barangDipilih!["harga1"]}") ?? 0)}",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => barangDipilih = null),
                              child: const Text("Hapus Acuan", style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8E0C8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(children: [tombol("AC", bg: Colors.blue.shade300, fg: Colors.white), tombol("MRC", bg: Colors.grey.shade400), tombol("M-", bg: Colors.grey.shade400), tombol("M+", bg: Colors.green, fg: Colors.white, besar: true)]),
                          Row(children: [tombol("OFF", bg: Colors.blue.shade300, fg: Colors.white), tombol("7"), tombol("8"), tombol("9"), tombol("LS", bg: Colors.orange.shade100, fg: Colors.black, besar: true)]),
                          Row(children: [tombol("%", bg: Colors.grey.shade300), tombol("4"), tombol("5"), tombol("6"), tombol("-", bg: Colors.grey.shade300)]),
                          Row(children: [tombol("+/-", bg: Colors.grey.shade300), tombol("1"), tombol("2"), tombol("3"), tombol("+", bg: Colors.grey.shade300)]),
                          Row(children: [tombol("ON/C", bg: Colors.blue.shade300, fg: Colors.white), tombol("0"), tombol("00"), tombol("."), tombol("=", bg: Colors.blue, fg: Colors.white, besar: true)]),
                          Row(children: [tombol("120", bg: Colors.orange, fg: Colors.white), tombol("000", bg: Colors.grey.shade300), tombol("MU", bg: Colors.grey.shade300), tombol("MC", bg: Colors.grey.shade300)]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E2E2E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("BARIS PO - MEMORI + TAMBAH PO", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          if (po.items.isEmpty)
                            const Text("Belum ada item - pencet LS pilih barang, lalu M+", style: TextStyle(color: Colors.white70, fontSize: 11)),
                          if (po.items.isNotEmpty)
                            ...po.items.asMap().entries.map(
                                  (e) => Container(
                                    margin: const EdgeInsets.only(bottom: 3),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text("${e.key + 1}. ${e.value.namaBarang} - ${e.value.qty}x ${formatRupiah(e.value.hargaSatuan)}", style: const TextStyle(fontSize: 11))),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 14),
                                          onPressed: () => ref.read(poProvider.notifier).hapusItem(e.key),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Subtotal: ${formatRupiah(hasil.subtotal)}", style: const TextStyle(color: Colors.white, fontSize: 11)),
                              Text("Total: ${formatRupiah(hasil.totalAkhir)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: FilledButton(onPressed: () {}, child: const Text("Kirim WA"))),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton(onPressed: () {}, child: const Text("Screenshot Nota"))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
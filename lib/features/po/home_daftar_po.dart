import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/formatter.dart';
import 'po_provider.dart';
import 'parse_cepat.dart';

// SATUAN
// Controller disimpan permanen
// Jangan dibuat di build
// Kalau dibuat di build
// Tiap ketik controller ke-reset
// Angka 1 dan 50 jadi tidak bisa diedit
class SatuanItem {
  SatuanItem({
    required String satuan,
    required bool dasar,
    required String qty,
    required String isi,
    required String op,
    required String nominal,
  })  : namaCtrl = TextEditingController(
          text: satuan,
        ),
        qtyCtrl = TextEditingController(
          text: qty,
        ),
        isiCtrl = TextEditingController(
          text: isi,
        ),
        nominalCtrl = TextEditingController(
          text: nominal,
        ),
        dasar = dasar,
        op = op;

  TextEditingController namaCtrl;
  TextEditingController qtyCtrl;
  TextEditingController isiCtrl;
  TextEditingController nominalCtrl;
  bool dasar;
  String op;

  Map<String, dynamic> toMap() {
    return {
      "satuan": namaCtrl.text,
      "dasar": dasar,
      "qty": qtyCtrl.text,
      "isi": isiCtrl.text,
      "op": op,
      "nominal": nominalCtrl.text.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      ),
    };
  }

  void dispose() {
    namaCtrl.dispose();
    qtyCtrl.dispose();
    isiCtrl.dispose();
    nominalCtrl.dispose();
  }
}

class HomeDaftarPO extends ConsumerStatefulWidget {
  const HomeDaftarPO({
    super.key,
  });

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

  final List<String> listKategori = [
    "Semen",
    "Besi",
    "Cat",
    "Keramik",
    "Pipa",
  ];

  final kategoriBaruCtrl = TextEditingController();

  final unitCtrl = TextEditingController(
    text: "pcs",
  );

  final harga1Ctrl = TextEditingController(
    text: "0",
  );

  final List<TextEditingController> varianCtrls = [
    TextEditingController(
      text: "Hitam",
    ),
  ];

  List<SatuanItem> satuanList = [
    SatuanItem(
      satuan: "kg",
      dasar: true,
      qty: "1",
      isi: "1",
      op: "x",
      nominal: "50000",
    ),
    SatuanItem(
      satuan: "sak",
      dasar: false,
      qty: "1",
      isi: "50",
      op: "x",
      nominal: "2500000",
    ),
  ];

  String modeHitung = "PEMBULATAN";

  int desimal = 0;

  final List<Map<String, dynamic>> steps = [];

  double get hargaAcuan {
    if (barangDipilih != null) {
      return double.tryParse(
            "${barangDipilih!["harga1"]}",
          ) ??
          0;
    }
    return 0;
  }

  double get manual {
    return double.tryParse(
          layar,
        ) ??
        0;
  }

  double get persen {
    if (hargaAcuan == 0) {
      return 0;
    }
    if (manual == 0) {
      return 0;
    }
    return (manual - hargaAcuan) / hargaAcuan * 100;
  }

  Color warnaSaran() {
    if (hargaAcuan == 0) {
      return Colors.black;
    }
    if (manual == 0) {
      return Colors.black;
    }
    if (persen < -20) {
      return const Color(
        0xFFB71C1C,
      );
    }
    if (persen < 0) {
      return Colors.red;
    }
    if (persen < 5) {
      return const Color(
        0xFFB58900,
      );
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
    return formatRupiah(
      hargaAcuan.toInt(),
    );
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

  String formatHasil(
    double v,
  ) {
    if (modeHitung == "ORIGINAL") {
      return v.toStringAsFixed(
        desimal,
      );
    }
    if (desimal == 0) {
      return v.round().toString();
    }
    return v.toStringAsFixed(
      desimal,
    );
  }

  // Nominal
  // qty x isi x harga acuan
  // 1 sak x 50 kg x Rp 50.000
  // =
  // Rp 2.500.000
  double hitungNominal(
    SatuanItem s,
  ) {
    final qty = double.tryParse(
          s.qtyCtrl.text,
        ) ??
        1;
    final isi = double.tryParse(
          s.isiCtrl.text,
        ) ??
        1;
    final hargaForm = double.tryParse(
          harga1Ctrl.text.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          ),
        ) ??
        0;
    final harga = hargaForm > 0 ? hargaForm : hargaAcuan;
    if (s.op == "÷") {
      if (isi == 0) {
        return 0;
      }
      return qty * (harga / isi);
    }
    return qty * isi * harga;
  }

  void refreshNominal(
    SatuanItem s,
  ) {
    final hasil = hitungNominal(
      s,
    );
    s.nominalCtrl.text = hasil.toStringAsFixed(0);
  }

  void refreshSemuaNominal() {
    for (var s in satuanList) {
      refreshNominal(
        s,
      );
    }
  }

  void syncUnitDariDasar() {
    final dasar = satuanList.firstWhere(
      (x) => x.dasar == true,
      orElse: () => satuanList.first,
    );
    unitCtrl.text = dasar.namaCtrl.text;
  }

  String teksRumusSatuan(
    SatuanItem s,
  ) {
    final dasarNama = satuanList
        .firstWhere(
          (x) => x.dasar == true,
          orElse: () => satuanList.first,
        )
        .namaCtrl
        .text;
    final qty = s.qtyCtrl.text.isEmpty ? "1" : s.qtyCtrl.text;
    final isi = s.isiCtrl.text.isEmpty ? "1" : s.isiCtrl.text;
    final nom = s.nominalCtrl.text.isEmpty ? "0" : s.nominalCtrl.text;
    final nomBersih = int.tryParse(
          nom.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          ),
        ) ??
        0;
    if (s.dasar) {
      return "$qty ${s.namaCtrl.text} = ${formatRupiah(nomBersih)}";
    }
    return "$qty ${s.namaCtrl.text} ${s.op} $isi $dasarNama = ${formatRupiah(nomBersih)}";
  }

  void dialogBabe() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            "BABE.INFO - Dialog Kalkulasi",
          ),
          content: const Text(
            "Harga Acuan 100% dari Harga 1.\n\n"
            "1 sak x 50 kg artinya:\n"
            "qty 1 x isi 50 x harga acuan\n"
            "1 x 50 x Rp 50.000 = Rp 2.500.000\n\n"
            "Tap (x) untuk ganti jadi (÷).\n"
            "BEP = Acuan x 110%.\n"
            "CEK = lihat step, edit & hapus sebaris.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text(
                "Tutup",
              ),
            ),
          ],
        );
      },
    );
  }

  void bukaCek() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            16,
          ),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            return Padding(
              padding: const EdgeInsets.all(
                16,
              ),
              child: SizedBox(
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "CEK - Proses Kalkulasi",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                    const Text(
                      "Item | Harga | Kuantiti | Jumlah - bisa edit, bisa hapus sebaris",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    if (steps.isEmpty)
                      const Text(
                        "Belum ada step. Pencet = atau M+ dulu.",
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: steps.length,
                        itemBuilder: (_, i) {
                          final s = steps[i];
                          return Container(
                            margin: const EdgeInsets.only(
                              bottom: 4,
                            ),
                            padding: const EdgeInsets.all(
                              6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(
                                6,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: TextEditingController(
                                      text: "${s["item"]}",
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: "Item",
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (v) {
                                      s["item"] = v;
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: 4,
                                ),
                                SizedBox(
                                  width: 70,
                                  child: TextField(
                                    controller: TextEditingController(
                                      text: "${s["harga"]}",
                                    ),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: "Harga",
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (v) {
                                      setSheet(() {
                                        s["harga"] = double.tryParse(v) ?? 0;
                                        s["jumlah"] =
                                            (s["harga"] as double) *
                                                (s["qty"] as num);
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: 4,
                                ),
                                SizedBox(
                                  width: 50,
                                  child: TextField(
                                    controller: TextEditingController(
                                      text: "${s["qty"]}",
                                    ),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: "Qty",
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (v) {
                                      setSheet(() {
                                        s["qty"] = double.tryParse(v) ?? 0;
                                        s["jumlah"] =
                                            (s["harga"] as double) *
                                                (s["qty"] as num);
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: 4,
                                ),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    formatRupiah(
                                      (s["jumlah"] as num).toInt(),
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    setSheet(() {
                                      steps.removeAt(i);
                                    });
                                    setState(() {});
                                  },
                                ),
                              ],
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

  void pencet(
    String t,
  ) {
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC" || t == "ON/C") {
        layar = "0";
        op = "";
        angka1 = 0;
      } else if (t == "LS") {
        bukaListLS();
      } else if (t == "CEK") {
        bukaCek();
      } else if (t == "OFF") {
        layar = "0";
      } else if (t == "BEP") {
        if (hargaAcuan > 0) {
          layar = formatHasil(
            hargaAcuan * 1.1,
          );
        } else {
          layar = formatHasil(
            (double.tryParse(layar) ?? 0) + 120,
          );
        }
      } else if (t == "M+") {
        memori += double.tryParse(layar) ?? 0;
        if (barangDipilih != null) {
          final qty = int.tryParse(layar) ?? 1;
          final harga = int.tryParse(
                "${barangDipilih!["harga1"]}",
              ) ??
              0;
          final it = parseInputCepat(
            "$qty x ${barangDipilih!["nama"]} $harga",
          );
          if (it != null) {
            ref.read(poProvider.notifier).tambahItem(it);
          }
          steps.add(
            {
              "item": barangDipilih!["nama"],
              "harga": harga,
              "qty": qty,
              "jumlah": qty * harga,
            },
          );
        }
        layar = "0";
      } else if (t == "M-") {
        memori -= double.tryParse(layar) ?? 0;
        layar = "0";
      } else if (t == "MRC") {
        layar = formatHasil(
          memori,
        );
        memori = 0;
      } else if (t == "MR") {
        layar = formatHasil(
          memori,
        );
      } else if (t == "MC") {
        memori = 0;
        layar = "0";
      } else if (t == "MU") {
        final v = double.tryParse(layar) ?? 0;
        layar = formatHasil(
          v * 1.1,
        );
      } else if (t == "▶" || t == "⌫") {
        if (layar.length > 1) {
          layar = layar.substring(
            0,
            layar.length - 1,
          );
        } else {
          layar = "0";
        }
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
        layar = formatHasil(h);
        steps.add(
          {
            "item": barangDipilih?["nama"] ?? "Hitung",
            "harga": angka1,
            "qty": a2,
            "jumlah": h,
          },
        );
        op = "";
      } else if (t == "+/-") {
        if (layar.startsWith("-")) {
          layar = layar.substring(1);
        } else if (layar != "0") {
          layar = "-$layar";
        }
      } else if (t == "%") {
        layar = formatHasil(
          (double.tryParse(layar) ?? 0) / 100,
        );
      } else {
        if (layar == "0") {
          layar = t;
        } else {
          layar += t;
        }
      }
    });
  }

  void bukaListLS() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            16,
          ),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            final q = queryLS.toLowerCase();
            final filtered = daftarBarang.where((b) {
              if (q.isEmpty) {
                return true;
              }
              return "${b["nama"]}".toLowerCase().contains(q) ||
                  "${b["kode"]}".toLowerCase().contains(q) ||
                  "${b["kategori"]}".toLowerCase().contains(q);
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                bukaFormTambahBarang();
                              },
                              child: const Text(
                                "+ Tambah Barang",
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.search,
                        ),
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
                    const SizedBox(
                      height: 8,
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const Text(
                        "Auto Suggestion:",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Wrap(
                        spacing: 6,
                        children: suggestions
                            .map(
                              (b) => ActionChip(
                                label: Text(
                                  "${b["nama"]}",
                                  style: const TextStyle(
                                    fontSize: 11,
                                  ),
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
                      const SizedBox(
                        height: 8,
                      ),
                      const Divider(
                        color: Colors.grey,
                        thickness: 1,
                      ),
                    ],
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                "Belum ada barang. Tap + Tambah Barang.",
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final b = filtered[i];
                                final aktif = barangDipilih != null &&
                                    barangDipilih!["kode"] == b["kode"];
                                final satuanBarang =
                                    (b["satuanList"] as List?) ?? [];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      leading: CircleAvatar(
                                        child: Text(
                                          "${b["nama"]}".isEmpty
                                              ? "?"
                                              : "${b["nama"]}"[0],
                                        ),
                                      ),
                                      title: Text(
                                        "${b["nama"]}",
                                      ),
                                      subtitle: Text(
                                        "${b["kode"]} • ${b["kategori"]} • ${b["satuan"] ?? "pcs"}",
                                      ),
                                      trailing: Text(
                                        formatRupiah(
                                          int.tryParse("${b["harga1"]}") ?? 0,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      tileColor: aktif
                                          ? Colors.green.shade100
                                          : null,
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
                                    ),
                                    if (satuanBarang.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 56,
                                          bottom: 8,
                                        ),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: satuanBarang
                                              .map<Widget>((s) {
                                                final m =
                                                    Map<String, dynamic>.from(
                                                  s as Map,
                                                );
                                                final dasarSatuan =
                                                    satuanBarang.firstWhere(
                                                  (x) =>
                                                      (x as Map)["dasar"] ==
                                                      true,
                                                  orElse: () => {
                                                    "satuan": "pcs",
                                                  },
                                                )["satuan"];
                                                final nom = double.tryParse(
                                                      "${m["nominal"]}",
                                                    ) ??
                                                    0;
                                                final qty = "${m["qty"] ?? "1"}";
                                                final isi = "${m["isi"] ?? "1"}";
                                                final label = m["dasar"] == true
                                                    ? "$qty ${m["satuan"]}"
                                                    : "$qty ${m["satuan"]} = $qty x $isi $dasarSatuan";
                                                return ActionChip(
                                                  label: Text(
                                                    "$label - ${formatRupiah(nom.toInt())}",
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      barangDipilih = {
                                                        "kode": "${b["kode"]}",
                                                        "nama": "${b["nama"]}",
                                                        "kategori":
                                                            "${b["kategori"]}",
                                                        "harga1":
                                                            "${nom.toInt()}",
                                                        "satuan":
                                                            "${m["satuan"]}",
                                                        "satuanIsi": "$isi",
                                                        "satuanOp":
                                                            "${m["op"]}",
                                                      };
                                                      layar = nom
                                                          .toStringAsFixed(0);
                                                    });
                                                    Navigator.pop(ctx);
                                                  },
                                                );
                                              })
                                              .toList(),
                                        ),
                                      ),
                                  ],
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
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            16,
          ),
        ),
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 12,
                    ),
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
                        const SizedBox(
                          width: 8,
                        ),
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
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Category • dropdown + tambah/delete",
                                style: TextStyle(
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: kategoriPilih,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                                items: listKategori
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      ),
                                    )
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
                                    icon: const Icon(
                                      Icons.add,
                                    ),
                                    onPressed: () {
                                      if (kategoriBaruCtrl.text.isNotEmpty) {
                                        setSheet(() {
                                          listKategori.add(
                                            kategoriBaruCtrl.text,
                                          );
                                          kategoriPilih = kategoriBaruCtrl.text;
                                          kategoriBaruCtrl.clear();
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
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
                        const SizedBox(
                          width: 8,
                        ),
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
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      "Harga 1 • Acuan 100%",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    TextField(
                      controller: harga1Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: "0",
                      ),
                      onChanged: (v) {
                        setSheet(() {
                          refreshSemuaNominal();
                        });
                      },
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    Container(
                      padding: const EdgeInsets.all(
                        8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFFFF8C5,
                        ),
                        borderRadius: BorderRadius.circular(
                          8,
                        ),
                      ),
                      child: const Text(
                        "Harga 1 ini yang jadi acuan prosentase 100% sedang harga 2 dan 3 tidak perlu ditampilkan, input manual edit harga 1 menjadi harga 2 dan 3 benar sudah ada di PO",
                        style: TextStyle(
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Varian",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setSheet(() {
                              varianCtrls.add(
                                TextEditingController(),
                              );
                            });
                          },
                          child: const Text(
                            "+Tambah Varian",
                            style: TextStyle(
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ...varianCtrls.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: 6,
                        ),
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
                              icon: const Icon(
                                Icons.close,
                                color: Colors.red,
                              ),
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
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Satuan",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setSheet(() {
                              satuanList.add(
                                SatuanItem(
                                  satuan: "",
                                  dasar: false,
                                  qty: "1",
                                  isi: "1",
                                  op: "x",
                                  nominal: harga1Ctrl.text.replaceAll(
                                    RegExp(r'[^0-9]'),
                                    '',
                                  ),
                                ),
                              );
                            });
                          },
                          child: const Text(
                            "+Tambah Satuan",
                            style: TextStyle(
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      "Baris 1: qty + satuan + x/÷ + isi. Baris 2: Rp nominal + rumus. 1 dan 50 bisa edit.",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    ...satuanList.asMap().entries.map((e) {
                      final s = e.value;
                      final dasarNama = satuanList
                          .firstWhere(
                            (x) => x.dasar == true,
                            orElse: () => satuanList.first,
                          )
                          .namaCtrl
                          .text;
                      return Container(
                        margin: const EdgeInsets.only(
                          bottom: 8,
                        ),
                        padding: const EdgeInsets.all(
                          8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(
                            10,
                          ),
                          color: Colors.white,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: TextField(
                                    controller: s.qtyCtrl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 10,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      setSheet(() {
                                        refreshNominal(
                                          s,
                                        );
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: 6,
                                ),
                                SizedBox(
                                  width: 62,
                                  child: TextField(
                                    controller: s.namaCtrl,
                                    decoration: const InputDecoration(
                                      hintText: "sak",
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 10,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      if (s.dasar) {
                                        syncUnitDariDasar();
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: 6,
                                ),
                                SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: InkWell(
                                    onTap: () {
                                      setSheet(() {
                                        s.op = s.op == "x" ? "÷" : "x";
                                        refreshNominal(
                                          s,
                                        );
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(
                                      19,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: s.op == "÷"
                                            ? Colors.teal.shade100
                                            : Colors.orange.shade100,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          s.op,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 6,
                                ),
                                SizedBox(
                                  width: 56,
                                  child: TextField(
                                    controller: s.isiCtrl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 10,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      setSheet(() {
                                        refreshNominal(
                                          s,
                                        );
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: 6,
                                ),
                                Expanded(
                                  child: Text(
                                    dasarNama,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                RadioGroup<bool>(
                                  groupValue: s.dasar,
                                  onChanged: (bool? v) {
                                    if (v == true) {
                                      setSheet(() {
                                        for (var x in satuanList) {
                                          x.dasar = false;
                                        }
                                        s.dasar = true;
                                        syncUnitDariDasar();
                                      });
                                    }
                                  },
                                  child: Radio<bool>(
                                    value: true,
                                  ),
                                ),
                                const Text(
                                  "dasar",
                                  style: TextStyle(
                                    fontSize: 10,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    setSheet(() {
                                      if (satuanList.length > 1) {
                                        satuanList.removeAt(e.key);
                                      }
                                    });
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: 6,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: s.nominalCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      prefixText: "Rp ",
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 10,
                                      ),
                                    ),
                                    onChanged: (v) {},
                                  ),
                                ),
                                const SizedBox(
                                  width: 8,
                                ),
                                Expanded(
                                  child: Text(
                                    teksRumusSatuan(
                                      s,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(
                      height: 16,
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                        ),
                        onPressed: () {
                          final varian = varianCtrls
                              .map(
                                (c) => c.text,
                              )
                              .join(", ");
                          setState(() {
                            daftarBarang.add(
                              {
                                "kode": kodeCtrl.text,
                                "nama": namaCtrl.text,
                                "kategori": kategoriPilih,
                                "harga1": harga1Ctrl.text.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                ),
                                "satuan": unitCtrl.text,
                                "varian": varian,
                                "satuanList": satuanList
                                    .map(
                                      (x) => x.toMap(),
                                    )
                                    .toList(),
                              },
                            );
                            barangDipilih = {
                              "kode": kodeCtrl.text,
                              "nama": namaCtrl.text,
                              "kategori": kategoriPilih,
                              "harga1": harga1Ctrl.text.replaceAll(
                                RegExp(r'[^0-9]'),
                                '',
                              ),
                            };
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          "Simpan Barang",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 20,
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

  // TOMBOL TIMBUL + EFEK TEKAN
  // Bayangan bawah 3px = timbul
  // Pas ditekan turun 2px
  // Bayangan hilang = ketekan beneran
  Widget tombol(
    String label, {
    Color? bg,
    Color? fg,
    bool besar = false,
  }) {
    final isDown = tombolDitekan == label && tekanTombol;
    final baseColor = bg ?? Colors.white;
    final shadowColor =
        baseColor == Colors.white ? Colors.grey.shade400 : Colors.black26;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(
          2.5,
        ),
        child: GestureDetector(
          onTapDown: (_) {
            setState(() {
              tombolDitekan = label;
              tekanTombol = true;
            });
          },
          onTapUp: (_) {
            setState(() {
              tekanTombol = false;
            });
            pencet(
              label,
            );
          },
          onTapCancel: () {
            setState(() {
              tekanTombol = false;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(
              milliseconds: 80,
            ),
            height: besar ? 56 : 46,
            transform: Matrix4.translationValues(
              0,
              isDown ? 2 : 0,
              0,
            ),
            decoration: BoxDecoration(
              color: isDown ? baseColor.withOpacity(0.85) : baseColor,
              borderRadius: BorderRadius.circular(
                8,
              ),
              border: Border.all(
                color: Colors.black12,
              ),
              boxShadow: isDown
                  ? []
                  : [
                      BoxShadow(
                        color: shadowColor,
                        offset: const Offset(
                          0,
                          3,
                        ),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.6),
                        offset: const Offset(
                          0,
                          -1,
                        ),
                        blurRadius: 0,
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: besar ? 16 : 14,
                  fontWeight: FontWeight.bold,
                  color: fg ?? Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final po = ref.watch(
      poProvider,
    );
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    return Scaffold(
      backgroundColor: const Color(
        0xFFE8E0C8,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: false,
            snap: false,
            automaticallyImplyLeading: false,
            backgroundColor: const Color(
              0xFF1A1A1A,
            ),
            expandedHeight: 196,
            collapsedHeight: 196,
            toolbarHeight: 196,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(
                  0xFF1A1A1A,
                ),
                child: Column(
                  children: [
                    Container(
                      height: 28,
                      color: Colors.black,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        10,
                        10,
                        10,
                        6,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(
                          10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1A1A1A,
                          ),
                          borderRadius: BorderRadius.circular(
                            10,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "BASKORO WINGCHUN",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: dialogBabe,
                                  child: const Text(
                                    "BABE.INFO - dialog kalkulasi",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: 6,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFDDE8D0,
                                ),
                                borderRadius: BorderRadius.circular(
                                  6,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        teksAcuan(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        layar,
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: 2,
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        barangDipilih == null
                                            ? "Pilih barang via LS"
                                            : "${barangDipilih!["nama"]} • ${barangDipilih!["kategori"]}",
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        teksSaran(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: warnaSaran(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        8,
                        0,
                        8,
                        8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  modeHitung = modeHitung == "PEMBULATAN"
                                      ? "ORIGINAL"
                                      : "PEMBULATAN";
                                });
                              },
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(
                                    16,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(
                                          10,
                                        ),
                                      ),
                                      child: const Text(
                                        "5/4",
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 4,
                                    ),
                                    Expanded(
                                      child: Text(
                                        modeHitung,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 4,
                          ),
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              height: 32,
                              child: SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment(
                                    value: 0,
                                    label: Text(
                                      "0",
                                      style: TextStyle(
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 2,
                                    label: Text(
                                      "2",
                                      style: TextStyle(
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 3,
                                    label: Text(
                                      "3",
                                      style: TextStyle(
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                                selected: {
                                  desimal,
                                },
                                onSelectionChanged: (s) {
                                  setState(() {
                                    desimal = s.first;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 4,
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 32,
                              child: FilledButton(
                                onPressed: () {},
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  textStyle: const TextStyle(
                                    fontSize: 10,
                                  ),
                                ),
                                child: const Text(
                                  "Kirim WA",
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 4,
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 32,
                              child: OutlinedButton(
                                onPressed: () {},
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  textStyle: const TextStyle(
                                    fontSize: 9,
                                  ),
                                  backgroundColor: Colors.white,
                                ),
                                child: const Text(
                                  "Nota",
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(
                8,
              ),
              child: Column(
                children: [
                  const SizedBox(
                    height: 8,
                  ),
                  Container(
                    padding: const EdgeInsets.all(
                      6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFE8E0C8,
                      ),
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            tombol(
                              "AC",
                              bg: Colors.blue.shade400,
                              fg: Colors.white,
                            ),
                            tombol(
                              "MRC",
                              bg: Colors.grey.shade400,
                            ),
                            tombol(
                              "M-",
                              bg: Colors.grey.shade400,
                            ),
                            tombol(
                              "M+",
                              bg: Colors.green,
                              fg: Colors.white,
                              besar: true,
                            ),
                            tombol(
                              "LS",
                              bg: Colors.orange.shade100,
                              besar: true,
                            ),
                            tombol(
                              "CEK",
                              bg: Colors.black,
                              fg: Colors.white,
                            ),
                            tombol(
                              "BEP",
                              bg: Colors.pink,
                              fg: Colors.white,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            tombol(
                              "OFF",
                              bg: Colors.blue.shade400,
                              fg: Colors.white,
                            ),
                            tombol(
                              "7",
                            ),
                            tombol(
                              "8",
                            ),
                            tombol(
                              "9",
                            ),
                            tombol(
                              "▶",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "MU",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "MC",
                              bg: Colors.grey.shade300,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            tombol(
                              "%",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "4",
                            ),
                            tombol(
                              "5",
                            ),
                            tombol(
                              "6",
                            ),
                            tombol(
                              "-",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "÷",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "MR",
                              bg: Colors.grey.shade300,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            tombol(
                              "+/-",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "1",
                            ),
                            tombol(
                              "2",
                            ),
                            tombol(
                              "3",
                            ),
                            tombol(
                              "+",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "x",
                              bg: Colors.grey.shade300,
                            ),
                            tombol(
                              "M-",
                              bg: Colors.grey.shade300,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            tombol(
                              "ON/C",
                              bg: Colors.blue.shade400,
                              fg: Colors.white,
                            ),
                            tombol(
                              "0",
                            ),
                            tombol(
                              "00",
                            ),
                            tombol(
                              ".",
                            ),
                            tombol(
                              "=",
                              bg: Colors.blue,
                              fg: Colors.white,
                              besar: true,
                            ),
                            tombol(
                              "M+",
                              bg: Colors.green,
                              fg: Colors.white,
                            ),
                            tombol(
                              "⌫",
                              bg: Colors.grey.shade300,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(
                      8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFF2E2E2E,
                      ),
                      borderRadius: BorderRadius.circular(
                        8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 4,
                        ),
                        if (po.items.isEmpty)
                          const Text(
                            "Belum ada item - pencet LS pilih barang, lalu M+",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        if (po.items.isNotEmpty)
                          ...po.items.asMap().entries.map(
                            (e) => Container(
                              margin: const EdgeInsets.only(
                                bottom: 3,
                              ),
                              padding: const EdgeInsets.all(
                                6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  4,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      "${e.key + 1}. ${e.value.namaBarang} - ${e.value.qty}x ${formatRupiah(e.value.hargaSatuan)}",
                                      style: const TextStyle(
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 14,
                                    ),
                                    onPressed: () {
                                      ref
                                          .read(poProvider.notifier)
                                          .hapusItem(e.key);
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(
                          height: 4,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Subtotal: ${formatRupiah(hasil.subtotal)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              "Total: ${formatRupiah(hasil.totalAkhir)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
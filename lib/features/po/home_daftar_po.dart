import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/formatter.dart';
import '../../core/po_database.dart';
import '../../widgets/kartu_po.dart';
import '../nota/nota_pdf.dart';
import '../nota/nota_preview.dart';
import '../po/po_models.dart';
import 'parse_cepat.dart';
import 'po_provider.dart';

class SatuanItem {
  SatuanItem({
    required String satuan,
    required this.dasar,
    required String qty,
    required String isi,
    required this.op,
    required String nominal,
    String satuanBaru = '',
  })  : namaCtrl = TextEditingController(text: satuan),
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
    return {
      "satuan": namaCtrl.text,
      "satuanBaru": satuanBaruCtrl.text,
      "dasar": dasar,
      "qty": qtyCtrl.text,
      "isi": isiCtrl.text,
      "op": op,
      "nominal": nominalCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
    };
  }

  void dispose() {
    namaCtrl.dispose();
    qtyCtrl.dispose();
    isiCtrl.dispose();
    nominalCtrl.dispose();
    satuanBaruCtrl.dispose();
  }
}

class _AutoField extends StatefulWidget {
  const _AutoField({
    required this.controller,
    this.hint = "",
    this.angka = false,
    this.onChanged,
    this.onTap,
    this.min = 44,
    this.max = 150,
  });
  final TextEditingController controller;
  final String hint;
  final bool angka;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final double min;
  final double max;
  @override
  State<_AutoField> createState() => _AutoFieldS();
}

class _AutoFieldS extends State<_AutoField> {
  double w = 56;
  @override
  void initState() {
    super.initState();
    _ukur();
    widget.controller.addListener(_ukur);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_ukur);
    super.dispose();
  }

  void _ukur() {
    final tp = TextPainter(
      text: TextSpan(
        text: widget.controller.text.isEmpty ? widget.hint : widget.controller.text,
        style: const TextStyle(fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final nw = (tp.width + 26).clamp(widget.min, widget.max);
    if ((nw - w).abs() > 1 && mounted) setState(() => w = nw);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: w,
      child: TextField(
        controller: widget.controller,
        keyboardType: widget.angka ? TextInputType.number : TextInputType.text,
        textAlign: widget.angka ? TextAlign.center : TextAlign.left,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
          border: const OutlineInputBorder(),
        ),
        onTap: widget.onTap,
        onChanged: (v) {
          _ukur();
          widget.onChanged?.call(v);
        },
      ),
    );
  }
}

class HomeDaftarPO extends ConsumerStatefulWidget {
  const HomeDaftarPO({super.key});
  @override
  ConsumerState<HomeDaftarPO> createState() => _S();
}

class _S extends ConsumerState<HomeDaftarPO> {
  final PoDatabase _db = PoDatabase();
  Map<String, String> _aliasCopas = {};
  Timer? _timerSimpanDB;

  @override
  void initState() {
    super.initState();
    _muatDariDB();
  }

  void _disposeMapCtrls(Map<String, TextEditingController> map) {
    for (final c in map.values) {
      c.dispose();
    }
    map.clear();
  }

  @override
  void dispose() {
    _timerSimpanDB?.cancel();
    _nomorWAC.dispose();
    _pelangganC.dispose();
    _cpsTempelC.dispose();
    _lsCariC.dispose();
    kodeCtrl.dispose();
    namaCtrl.dispose();
    kategoriBaruCtrl.dispose();
    unitCtrl.dispose();
    harga1Ctrl.dispose();
    _disposeMapCtrls(_poCtrls);
    _disposeMapCtrls(_stepCtrls);
    _disposeMapCtrls(_pecahCtrls);
    _disposeMapCtrls(_chainCtrls);
    for (final c in varianCtrls) {
      c.dispose();
    }
    for (final c in hargaCtrls) {
      c.dispose();
    }
    for (final g in satuanPerVarian) {
      for (final x in g) {
        x.dispose();
      }
    }
    for (final x in satuanList) {
      x.dispose();
    }
    super.dispose();
  }

    @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _jadwalSimpanDB();
  }

  void _jadwalSimpanDB() {
    _timerSimpanDB?.cancel();
    _timerSimpanDB = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _simpanSemuaKeDB();
      }
    });
  }

  Future<void> _simpanSemuaKeDB() async {
    try {
      await _db.simpanBarang(daftarBarang);
      await _db.simpanStepDraf(steps);
      final poItems = ref.read(poProvider).items;
      final poDraf = >[];
      for (var i = 0; i < poItems.length; i++) {
        final it = poItems[i];
        poDraf.add({
          'nama': it.namaBarang,
          'harga': it.hargaSatuan,
          'qty': it.qty,
          'jumlah': it.qty * it.hargaSatuan,
          'satuan': _poCtrls['$i-satuan']?.text.trim() ?? it.satuan,
          'step': _poCtrls['$i-step']?.text.trim() ?? '',
        });
      }
      await _db.simpanPoDraf(poDraf);
    } catch (_) {}
  }

  Future<void> _muatDariDB() async {
    try {
      final barang = await _db.muatBarang();
      final poList = await _db.muatSemuaPo();
      final draf = await _db.muatStepDraf();
      final poDraf = await _db.muatPoDraf();
      final alias = await _db.muatAliasCopas();
      if (!mounted) return;
      setState(() {
        daftarBarang
          ..clear()
          ..addAll(barang.map((b) => Map<String, dynamic>.from(b)));
        _aliasCopas = alias;
        steps
          ..clear()
          ..addAll(draf.map((st) => {
                'item': st['item'],
                'rumus': st['rumus'],
                'harga': st['harga'],
                'qty': st['qty'],
                'jumlah': st['jumlah'],
                'satuan': st['satuan'] ?? '',
                'tipeHarga': 'SATUAN',
                'chain': st['chain'] ?? >[],
                'opPecah': st['opPecah'] ?? 'x',
              }));
        _disposeMapCtrls(_stepCtrls);
        _poTersimpan.clear();
        var maxNomor = 0;
        for (final p in poList) {
          final nomorStr = '${p['nomor'] ?? ''}';
          final nomorInt =
              int.tryParse(RegExp(r'(\d+)').firstMatch(nomorStr)?.group(1) ?? '') ?? 0;
          if (nomorInt > maxNomor) {
            maxNomor = nomorInt;
          }
          _poTersimpan.add({
            'nomorInt': nomorInt,
            'nomor': nomorStr,
            'tanggal': p['tanggal'] ?? DateTime.now().toIso8601String(),
            'pelanggan': p['pelanggan'] ?? '',
            'items': (p['items'] as List)
                .map((e) => {
                      'nama': e['namaBarang'] ?? '',
                      'harga': e['harga'],
                      'satuan': e['satuan'] ?? '',
                      'qty': e['qty'],
                      'step': e['rumus'] ?? '',
                      'jumlah': e['jumlah'],
                      'tipeHarga': 'SATUAN',
                    })
                .toList(),
            'total': p['total'],
            'dicek': (p['dicek'] ?? 0) == 1,
            'nomorWA': p['nomorWA'] ?? '',
            'dbId': p['id'],
          });
        }
        if (maxNomor >= _poNomor) {
          _poNomor = maxNomor + 1;
        }
        if (poDraf.isNotEmpty) {
          _tulisUlangPO(poDraf
              .map((e) => {
                    'nama': e['nama'],
                    'qty': e['qty'],
                    'harga': e['harga'],
                    'satuan': e['satuan'] ?? '',
                    'step': e['step'] ?? '',
                    'jumlah': e['jumlah'],
                  })
              .toList());
          _disposeMapCtrls(_poCtrls);
          for (var i = 0; i < poDraf.length; i++) {
            final e = poDraf[i];
            _poCtrls['$i-nama'] = TextEditingController(text: '${e['nama'] ?? ''}');
            _poCtrls['$i-harga'] =
                TextEditingController(text: '${(e['harga'] as num?)?.toInt() ?? 0}');
            _poCtrls['$i-satuan'] = TextEditingController(text: '${e['satuan'] ?? ''}');
            _poCtrls['$i-qty'] = TextEditingController(text: '${e['qty'] ?? 0}');
            _poCtrls['$i-step'] = TextEditingController(text: '${e['step'] ?? ''}');
          }
        }
      });
    } catch (_) {}
  }

  String layar = "0";
  String ekspresi = "";
  double akumulator = 0;
  String opPending = "";
  String op = "";
  double angka1 = 0;
  bool entryBaru = true;
  bool adaError = false;
  String lastOp = "";
  double lastAngka2 = 0;
  double qtyHitung = 1;
  bool adaQtyHitung = false;
  double? _qtyMPlus;
  bool _habisMPlus = false;
  double memori = 0;

  double? _hargaAcuanVarian;
  String _labelSaranVarian = "";
  bool _hargaLayarDiubah = false;

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

  bool _stripTengahTerbuka = true;
  String _tombolKuningAktif = '';
  final TextEditingController _cpsTempelC = TextEditingController();
  List> _cpsBaris = [];
  int _modeKeyboard = 0;
  int _mrIndex = -1;
  bool _mrtTerbuka = false;
  TextEditingController? _ctrlKeyboard;
  int _qwertyCaps = 1;
  final TextEditingController _lsCariC = TextEditingController();

  int _poNomor = 1;
  bool _poRevisi = false;
  bool _poDicek = false;
  final TextEditingController _pelangganC = TextEditingController();
  final TextEditingController _nomorWAC = TextEditingController();
  bool _sembunyiSaranPelanggan = false;
  final List> _poTersimpan = [];
  Map<String, TextEditingController> _poCtrls = {};
  int _poTerbukaIndex = -1;


  final Map<String, TextEditingController> _pecahCtrls = {};
  final Map<String, String> _opPecah = {};
  final Map<String, Map<String, dynamic>> _acuanDariLS = {};

  double _acuanDariOp(double hargaSatuan, double angkaSatuan, String op) {
    if (op == '÷') {
      return angkaSatuan == 0 ? hargaSatuan : hargaSatuan / angkaSatuan;
    }
    return hargaSatuan * angkaSatuan;
  }

  final Map<String, double> _satuanBaseline = {};

  Map<String, double> _pecahOtomatis(double harga) {
    if (harga < 2000) return {'dasar': harga, 'bagi': 1};
    for (var b in [2, 3, 4, 5, 6, 8, 10, 12]) {
      if (harga % b == 0) {
        final dasar = harga / b;
        if (dasar >= 1000 && dasar == dasar.roundToDouble()) {
          return {'dasar': dasar, 'bagi': b.toDouble()};
        }
      }
    }
    return {'dasar': harga, 'bagi': 1};
  }

  Map<String, TextEditingController> _stepCtrls = {};
  final Map<String, TextEditingController> _chainCtrls = {};
  final Map<int, List>> _poChain = {};
  Map<int, String> _tipeHargaPO = {};
  Map<int, String> _tipeHargaStep = {};
  Set<int> _poTerpilih = {};
  Set<int> _stepTerpilih = {};
  String? _tagKeyboardAktif;
  bool _diFormTambahBarang = false;

  void _geserStateBarisSetelahHapus(String tag, int deletedIndex) {
    for (final suffix in ['unit', 'satuanHarga']) {
      _pecahCtrls.remove('$tag-$deletedIndex-$suffix')?.dispose();
    }
    _opPecah.remove('$tag-$deletedIndex-op');
    _satuanBaseline.remove('$tag-$deletedIndex-satuanHarga');
    _acuanDariLS.remove('$tag-$deletedIndex');

    final prefixChainHapus = '$tag-$deletedIndex-chain-';
    final keysChainHapus =
        _chainCtrls.keys.where((k) => k.startsWith(prefixChainHapus)).toList();
    for (final k in keysChainHapus) {
      _chainCtrls.remove(k)?.dispose();
    }

    final idxLamaList = <int>{};
    for (final k in _pecahCtrls.keys) {
      if (k.startsWith('$tag-')) {
        final parts = k.split('-');
        if (parts.length >= 3) {
          final idx = int.tryParse(parts[1]);
          if (idx != null && idx > deletedIndex) idxLamaList.add(idx);
        }
      }
    }
    for (final k in _opPecah.keys) {
      if (k.startsWith('$tag-')) {
        final parts = k.split('-');
        if (parts.length >= 3) {
          final idx = int.tryParse(parts[1]);
          if (idx != null && idx > deletedIndex) idxLamaList.add(idx);
        }
      }
    }
    for (final k in _satuanBaseline.keys) {
      if (k.startsWith('$tag-')) {
        final parts = k.split('-');
        if (parts.length >= 3) {
          final idx = int.tryParse(parts[1]);
          if (idx != null && idx > deletedIndex) idxLamaList.add(idx);
        }
      }
    }
    for (final k in _acuanDariLS.keys) {
      if (k.startsWith('$tag-')) {
        final parts = k.split('-');
        if (parts.length >= 2) {
          final idx = int.tryParse(parts[1]);
          if (idx != null && idx > deletedIndex) idxLamaList.add(idx);
        }
      }
    }

    final sortedIdx = idxLamaList.toList()..sort();
    for (final oldIdx in sortedIdx) {
      final newIdx = oldIdx - 1;
      for (final suffix in ['unit', 'satuanHarga']) {
        final c = _pecahCtrls.remove('$tag-$oldIdx-$suffix');
        if (c != null) {
          _pecahCtrls['$tag-$newIdx-$suffix']?.dispose();
          _pecahCtrls['$tag-$newIdx-$suffix'] = c;
        }
      }
      if (_opPecah.containsKey('$tag-$oldIdx-op')) {
        _opPecah['$tag-$newIdx-op'] = _opPecah.remove('$tag-$oldIdx-op')!;
      }
      if (_satuanBaseline.containsKey('$tag-$oldIdx-satuanHarga')) {
        _satuanBaseline['$tag-$newIdx-satuanHarga'] =
            _satuanBaseline.remove('$tag-$oldIdx-satuanHarga')!;
      }
      if (_acuanDariLS.containsKey('$tag-$oldIdx')) {
        _acuanDariLS['$tag-$newIdx'] = _acuanDariLS.remove('$tag-$oldIdx')!;
      }
      final prefixOld = '$tag-$oldIdx-chain-';
      final keysOldChain =
          _chainCtrls.keys.where((k) => k.startsWith(prefixOld)).toList()..sort();
      for (final kOld in keysOldChain) {
        final tail = kOld.substring(prefixOld.length);
        final cChain = _chainCtrls.remove(kOld);
        if (cChain != null) {
          final kNew = '$tag-$newIdx-chain-$tail';
          _chainCtrls.remove(kNew)?.dispose();
          _chainCtrls[kNew] = cChain;
        }
      }
    }
  }

  void _bersihkanSemuaStatePecah(String tag) {
    final keysPecah =
        _pecahCtrls.keys.where((k) => k.startsWith('$tag-')).toList();
    for (final k in keysPecah) {
      _pecahCtrls.remove(k)?.dispose();
    }
    _opPecah.removeWhere((k, _) => k.startsWith('$tag-'));
    _satuanBaseline.removeWhere((k, _) => k.startsWith('$tag-'));
    _acuanDariLS.removeWhere((k, _) => k.startsWith('$tag-'));
    final keysChain =
        _chainCtrls.keys.where((k) => k.startsWith('$tag-')).toList();
    for (final k in keysChain) {
      _chainCtrls.remove(k)?.dispose();
    }
  }

  PoOrder _bangunOrderKartu(Map<String, dynamic> pp) {
    final rawTanggal = '${pp['tanggal'] ?? ''}';
    final tanggalParsed = DateTime.tryParse(rawTanggal) ?? DateTime.now();
    final namaPelanggan = '${pp['pelanggan'] ?? ''}'.trim();
    final nomorWA = '${pp['nomorWA'] ?? ''}'.trim();
    final itemsMentah = (pp['items'] as List?) ?? const [];
    final items = <PoItem>[];

    for (final raw in itemsMentah) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final nama = '${m['nama'] ?? m['namaBarang'] ?? ''}'.trim();
      final qtyNum = (m['qty'] as num?)?.toDouble() ?? 1.0;
      final hargaNum = (m['harga'] as num?)?.toDouble() ?? 0.0;
      final diskonNum = (m['diskonItem'] as num?)?.toDouble() ?? 0.0;
      final qtyBulat = qtyNum.round();
      items.add(
        PoItem(
          namaBarang: nama.isEmpty ? 'Barang' : nama,
          qty: qtyBulat <= 0 ? 1 : qtyBulat,
          hargaSatuan: hargaNum.round(),
          diskonItem: diskonNum.round(),
          satuan: '${m['satuan'] ?? ''}'.trim(),
        ),
      );
    }

    final sudahDicek = (pp['dicek'] as bool?) ?? false;
    return PoOrder(
      id: '${pp['nomor'] ?? ''}'.trim(),
      tanggal: tanggalParsed,
      customer: Customer(
        id: nomorWA.isNotEmpty
            ? nomorWA
            : (namaPelanggan.isNotEmpty ? namaPelanggan : 'tanpa-nama'),
        namaOrang: namaPelanggan.isEmpty ? 'Tanpa Nama' : namaPelanggan,
        nomorWA: nomorWA,
      ),
      items: items,
      status: sudahDicek ? PoStatus.values.last : PoStatus.values.first,
    );
  }

  void _onTapTombolKuning(String tombol) {
    if (_diFormTambahBarang) return;
    setState(() {
      _stripTengahTerbuka = true;
      _tombolKuningAktif = (_tombolKuningAktif == tombol) ? '' : tombol;
      poTerbuka = false;
      _resetKeyboard();
    });
  }

  Widget _tombolStripRapi(String label, Color bg, VoidCallback onTap) {
    final gelap = bg == Colors.black ||
        bg == const Color(0xFF1F2A44) ||
        bg == const Color(0xFF2D7DFF);
    return SizedBox(
      height: 30,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: gelap ? Colors.white : Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stripTengah() {
    if (!_stripTengahTerbuka) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAF5),
        border: Border(bottom: BorderSide(color: Color(0xFF2EBD5A), width: 3)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            _tombolStripRapi('TAX+', Colors.teal, () => pencet('TAX+')),
            const SizedBox(width: 6),
            _tombolStripRapi('TAX-', Colors.teal, () => pencet('TAX-')),
            const SizedBox(width: 6),
            _tombolStripRapi(
                'SET TAX', const Color(0xFF1F2A44), () => pencet('SET TAX')),
            const SizedBox(width: 6),
            _tombolStripRapi('COST', const Color(0xFF2D7DFF), () => pencet('COST')),
            const SizedBox(width: 6),
            _tombolStripRapi('SELL', const Color(0xFF2D7DFF), () => pencet('SELL')),
            const SizedBox(width: 6),
            _tombolStripRapi(
                'MARGIN', const Color(0xFF2D7DFF), () => pencet('MARGIN')),
            const SizedBox(width: 6),
            _tombolStripRapi(
                'CSM CLR', Colors.grey.shade300, () => pencet('CSM CLR')),
            const SizedBox(width: 6),
            _tombolStripRapi(
                'ROUND: $modeRound', Colors.amber.shade100, () => pencet('ROUND')),
            const SizedBox(width: 6),
            _tombolStripRapi(modeAdd2 ? 'ADD2: ON' : 'ADD2: OFF',
                Colors.amber.shade100, () => pencet('ADD2')),
            const SizedBox(width: 6),
            _tombolStripRapi('✕', Colors.grey.shade300,
                () => setState(() => _stripTengahTerbuka = false)),
          ],
        ),
      ),
    );
  }

  int _mrJumlahBaris() {
    if (steps.isNotEmpty) return steps.length;
    return ref.read(poProvider).items.length;
  }

  Map<String, dynamic> _mrBaris(int i) {
    if (steps.isNotEmpty) {
      final st = steps[i];
      return {
        'jumlah': ((st['jumlah'] as num?)?.toDouble() ?? 0),
        'teks': '${st['rumus'] ?? st['item'] ?? ''}',
      };
    }
    final it = ref.read(poProvider).items[i];
    final jml = (it.qty * it.hargaSatuan).toDouble();
    return {
      'jumlah': jml,
      'teks':
          '${it.namaBarang} : ${formatHasil(it.qty.toDouble())} x ${formatRupiah(it.hargaSatuan)} = ${formatRupiah(jml.toInt())}',
    };
  }

  Widget _stripMRT() {
    final totalStep = steps.fold<double>(
        0, (a, st) => a + (((st['jumlah'] as num?)?.toDouble() ?? 0)));
    final daftar =
        steps.map((st) => 'step; ${st['rumus'] ?? st['item'] ?? ''}').join('; ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAF5),
        border: Border(
          top: BorderSide(color: Color(0xFF2D7DFF), width: 3),
          bottom: BorderSide(color: Color(0xFF2EBD5A), width: 3),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text('MRT TOTAL = ${formatHasil(totalStep)}',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          if (daftar.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text('|  $daftar', style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _mrtTerbuka = false),
            child: const Text('✕',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF888888))),
          ),
        ]),
      ),
    );
  }

  Widget _panelForm() {
    final mode = _tombolKuningAktif;
    if (mode.isEmpty) return const SizedBox.shrink();
    const judul = {
      'CEK': 'CEK - Cek & Edit Step',
      'LS': 'LS - List Barang',
      'RIW': 'RIW - Riwayat Log Step',
      'CPS': 'CPS - Copas Teks jadi Step',
      'PO': 'PO - Cari PO Tersimpan',
    };
    Widget isi;
    double tinggi;
    if (mode == 'CEK') {
      isi = _panelCek();
      tinggi = 250;
    } else if (mode == 'LS') {
      isi = _panelLS();
      tinggi = 250;
    } else if (mode == 'RIW') {
      isi = _panelRiw();
      tinggi = 250;
    } else if (mode == 'CPS') {
      isi = _panelCps();
      tinggi = 290;
    } else {
      isi = _panelPO();
      tinggi = 240;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAF5),
        border: Border(
          top: BorderSide(color: Color(0xFF2D7DFF), width: 3),
          bottom: BorderSide(color: Color(0xFF2EBD5A), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(judul[mode] ?? mode,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () => setState(() {
                  _commitSemuaBarisStep();
                  _tombolKuningAktif = '';
                  _resetKeyboard();
                }),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('Tutup X',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF888888))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(height: tinggi, child: isi),
        ],
      ),
    );
  }

  Widget _fieldBorderAtas({
    required String label,
    required TextEditingController controller,
    bool angka = false,
    String? tag,
    bool padat = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      showCursor: true,
      keyboardType: angka ? TextInputType.number : TextInputType.text,
      onTap: () => _aktifkanField(controller, angka ? 2 : 1, tag: tag),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 10, vertical: padat ? 5 : 8),
      ),
    );
  }

  Widget _barisItem({
    required int index,
    required String tag,
    required TextEditingController cNama,
    required TextEditingController cHarga,
    required TextEditingController cSatuan,
    required TextEditingController cQty,
    required bool dicek,
    required VoidCallback onCek,
    required VoidCallback onHapus,
    Widget? tombolExtra,
    bool tampilChain = false,
    List> chain = const [],
    List<TextEditingController> chainCtrls = const [],
    VoidCallback? onChainTambah,
    void Function(int j)? onChainOps,
    void Function(int j)? onChainHapus,
    VoidCallback? onMPlus,
  }) {
    final qty =
        double.tryParse(cQty.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final chainHitung = >[];
    for (var j = 0; j < chain.length; j++) {
      chainHitung.add({
        'ops': chain[j]['ops'],
        'angka': double.tryParse(
                chainCtrls[j].text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0,
      });
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
            color: dicek ? Colors.teal : Colors.grey.shade300,
            width: dicek ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
                width: 36,
                child: Checkbox(value: dicek, onChanged: (_) => onCek())),
            Expanded(
              child: _fieldBorderAtas(
                  label: 'Nama Barang',
                  controller: cNama,
                  tag: '$tag-$index-nama'),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: onHapus,
            ),
            if (tombolExtra != null) tombolExtra,
          ]),
          const SizedBox(height: 8),
          Builder(builder: (ctx) {
            final acuanNow = double.tryParse(
                    cHarga.text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                0;
            final pecah2 = _pecahOtomatis(acuanNow);
            final acuanLS = _acuanDariLS['$tag-$index'];
            final satuanDef = acuanLS != null
                ? (acuanLS['hargaSatuan'] as double)
                : pecah2['dasar']!;
            final bagiDef2 = acuanLS != null
                ? (acuanLS['angkaSatuan'] as double)
                : pecah2['bagi']!;
            final keyOp = '$tag-$index-op';
            _opPecah.putIfAbsent(
                keyOp, () => acuanLS != null ? (acuanLS['op']?.toString() ?? 'x') : 'x');
            final opPecah = _opPecah[keyOp] ?? 'x';
            final keyUnit = '$tag-$index-unit';
            final keySatuan = '$tag-$index-satuanHarga';
            _pecahCtrls.putIfAbsent(
                keyUnit, () => TextEditingController(text: '${bagiDef2.toInt()}'));
            _pecahCtrls.putIfAbsent(
                keySatuan, () => TextEditingController(text: '${satuanDef.toInt()}'));
            final satuanNow = double.tryParse(_pecahCtrls[keySatuan]!
                    .text
                    .replaceAll(RegExp(r'[^0-9.]'), '')) ??
                satuanDef;
            final unitNow = double.tryParse(_pecahCtrls[keyUnit]!
                    .text
                    .replaceAll(RegExp(r'[^0-9.]'), '')) ??
                bagiDef2;
            _satuanBaseline.putIfAbsent(keySatuan, () => satuanDef);
            final patokan = _satuanBaseline[keySatuan]!;
            final persenEdit =
                patokan == 0 ? 0.0 : (satuanNow - patokan) / patokan * 100;
            final acuanUpdate = _acuanDariOp(satuanNow, unitNow, opPecah);
            final jumlahRantai =
                _hitungChain(satuanNow * unitNow, qty, chainHitung);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 104,
                      child: _fieldBorderAtas(
                        label: 'Harga',
                        controller: _pecahCtrls[keySatuan]!,
                        angka: true,
                        tag: '$keySatuan-harga',
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: InkWell(
                        onTap: () => setState(() {
                          _opPecah[keyOp] = opPecah == 'x' ? '÷' : 'x';
                          if (acuanUpdate > 0) {
                            cHarga.text = '${acuanUpdate.toInt()}';
                          }
                        }),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          decoration: BoxDecoration(
                            color: opPecah == '÷'
                                ? Colors.teal.shade100
                                : Colors.orange.shade100,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Center(
                            child: Text(
                              opPecah,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: _fieldBorderAtas(
                        label: 'Angka Satuan',
                        controller: _pecahCtrls[keyUnit]!,
                        angka: true,
                        tag: '$keyUnit-unit',
                      ),
                    ),
                    const Text('x',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 64,
                      child: _fieldBorderAtas(
                        label: 'Qty',
                        controller: cQty,
                        angka: true,
                        tag: '$tag-$index-qty',
                      ),
                    ),
                    for (var j = 0; j < chain.length; j++) ...[
                      SizedBox(
                        width: 44,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero),
                          onPressed: () => onChainOps?.call(j),
                          child: Text(
                            chain[j]['ops']?.toString() ?? 'x',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: _fieldBorderAtas(
                          label: 'Step',
                          controller: chainCtrls[j],
                          angka: true,
                          tag: '$tag-$index-chain-$j',
                        ),
                      ),
                      InkWell(
                        onTap: () => onChainHapus?.call(j),
                        child: const Icon(Icons.close,
                            size: 18, color: Colors.red),
                      ),
                    ],
                    if (onChainTambah != null)
                      OutlinedButton(
                          onPressed: onChainTambah, child: const Text('+')),
                    if (onMPlus != null)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        onPressed: onMPlus,
                        child: const Text('M+'),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text(
                      '${persenEdit.toStringAsFixed(1)}% dari ${formatRupiah(patokan.toInt())}  •  Harga ${formatRupiah(satuanNow.toInt())} $opPecah ${unitNow.toStringAsFixed(unitNow % 1 == 0 ? 0 : 1)} = Harga Acuan ${formatRupiah(acuanUpdate.toInt())}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      cHarga.text = '${acuanUpdate.toInt()}';
                      setState(() {});
                    },
                    child:
                        const Text('Terapkan', style: TextStyle(fontSize: 11)),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: _fieldBorderAtas(
                      label: 'Unit / Satuan',
                      controller: cSatuan,
                      tag: '$tag-$index-satuan',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Jumlah',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      child: Text(
                        formatRupiah(jumlahRantai.toInt()),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ]),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _nomorPO() => 'B.W - ${_poNomor.toString().padLeft(6, '0')}B.I';

  String _namaDariStep(Map<String, dynamic> st) {
    final itemStr = '${st['item'] ?? ''}';
    if (itemStr.contains(' : ')) {
      return itemStr.split(' : ').first.trim();
    }
    return itemStr;
  }

  List> _daftarPelanggan() {
    final map = <String, String>{};
    for (final p in _poTersimpan) {
      final nm = '${p['pelanggan'] ?? ''}'.trim();
      if (nm.isEmpty || nm == 'Tanpa Nama') continue;
      map[nm] = '${p['nomorWA'] ?? ''}'.trim();
    }
    final list =
        map.entries.map((e) => {'nama': e.key, 'wa': e.value}).toList();
    return list.reversed.toList();
  }

  List> _saranPelanggan() {
    final daftar = _daftarPelanggan();
    final diWA = identical(_ctrlKeyboard, _nomorWAC);
    final q = (diWA ? _nomorWAC.text : _pelangganC.text).trim().toLowerCase();
    bool cocok(Map<String, String> m) {
      if (q.isEmpty) return true;
      if (diWA) {
        return m['wa']!.toLowerCase().contains(q) ||
            m['nama']!.toLowerCase().contains(q);
      }
      return m['nama']!.toLowerCase().contains(q);
    }

    final hasil = daftar.where(cocok).toList();
    bool diawali(Map<String, String> m) {
      if (q.isEmpty) return false;
      if (diWA) {
        return m['wa']!.toLowerCase().startsWith(q) ||
            m['nama']!.toLowerCase().startsWith(q);
      }
      return m['nama']!.toLowerCase().startsWith(q);
    }

    hasil.sort((a, b) => (diawali(b) ? 1 : 0) - (diawali(a) ? 1 : 0));
    return hasil;
  }

  void _pilihSaranPelanggan(Map<String, String> m) {
    setState(() {
      _pelangganC.text = m['nama'] ?? '';
      final wa = m['wa'] ?? '';
      if (wa.isNotEmpty) _nomorWAC.text = wa;
      _sembunyiSaranPelanggan = true;
      _resetKeyboard();
    });
  }

  void _autoLengkapiPelanggan() {
    final daftar = _daftarPelanggan();
    final namaKetik = _pelangganC.text.trim().toLowerCase();
    final waKetik = _nomorWAC.text.trim();
    if (identical(_ctrlKeyboard, _pelangganC) &&
        namaKetik.isNotEmpty &&
        waKetik.isEmpty) {
      for (final m in daftar) {
        if (m['nama']!.toLowerCase() == namaKetik &&
            (m['wa'] ?? '').isNotEmpty) {
          _nomorWAC.text = m['wa']!;
          break;
        }
      }
    } else if (identical(_ctrlKeyboard, _nomorWAC) &&
        waKetik.isNotEmpty &&
        _pelangganC.text.trim().isEmpty) {
      for (final m in daftar) {
        if (m['wa'] == waKetik && (m['nama'] ?? '').isNotEmpty) {
          _pelangganC.text = m['nama']!;
          break;
        }
      }
    }
  }

  bool _sembunyiSaranField = false;
  TextEditingController? _satuanCtrlDialog;
  final Set<String> _lsExpand = {};

  Map<String, dynamic>? _barangDariNama(String ketik) {
    final q = ketik.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final b in daftarBarang) {
      if ('${b['nama'] ?? ''}'.trim().toLowerCase() == q) return b;
    }
    return null;
  }

  List> _saranNamaBarang(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return [];
    final cocok = daftarBarang
        .where((b) =>
            '${b['nama'] ?? ''}'.toLowerCase().contains(query) &&
            '${b['nama'] ?? ''}'.toLowerCase() != query)
        .toList();
    cocok.sort((a, b) =>
        ('${b['nama'] ?? ''}'.toLowerCase().startsWith(query) ? 1 : 0) -
        ('${a['nama'] ?? ''}'.toLowerCase().startsWith(query) ? 1 : 0));
    return cocok.take(8).toList();
  }

  List<String> _saranSatuan(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return [];
    final cocok = daftarSatuan
        .where(
            (x) => x.toLowerCase().contains(query) && x.toLowerCase() != query)
        .toList();
    cocok.sort((a, b) =>
        (b.toLowerCase().startsWith(query) ? 1 : 0) -
        (a.toLowerCase().startsWith(query) ? 1 : 0));
    return cocok.take(6).toList();
  }

  List<String> _saranVarian(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return [];
    final semua = <String>{};
    for (final b in daftarBarang) {
      for (final v in '${b['varian'] ?? ''}'.split(',')) {
        final t = v.trim();
        if (t.isNotEmpty) semua.add(t);
      }
    }
    final cocok = semua
        .where(
            (x) => x.toLowerCase().contains(query) && x.toLowerCase() != query)
        .toList();
    cocok.sort((a, b) =>
        (b.toLowerCase().startsWith(query) ? 1 : 0) -
        (a.toLowerCase().startsWith(query) ? 1 : 0));
    return cocok.take(5).toList();
  }

  Map<String, TextEditingController>? _ctrlsBaris(String tag) {
    final parts = tag.split('-');
    if (parts.length < 3) return null;
    if (parts[0] == 'po') return _poCtrls;
    if (parts[0] == 'step') return _stepCtrls;
    return null;
  }

  void _koreksiOtomatis(String tag) {
    final ctrls = _ctrlsBaris(tag);
    if (ctrls == null) return;
    final parts = tag.split('-');
    final key = '${parts[1]}-${parts[2]}';
    if (parts[2] == 'nama') {
      final c = ctrls[key];
      if (c == null) return;
      final b = _barangDariNama(c.text);
      if (b == null) return;
      if (c.text != '${b['nama']}') c.text = '${b['nama']}';
      final h = ctrls['${parts[1]}-harga'];
      if (h != null && h.text.trim().isEmpty) h.text = '${b['harga1'] ?? ''}';
      final st = ctrls['${parts[1]}-satuan'];
      if (st != null && st.text.trim().isEmpty) st.text = '${b['satuan'] ?? ''}';
    } else if (parts[2] == 'satuan') {
      final c = ctrls[key];
      if (c == null) return;
      final ketik = c.text.trim();
      if (ketik.isEmpty) return;
      for (final x in daftarSatuan) {
        if (x.toLowerCase() == ketik.toLowerCase() && x != ketik) {
          c.text = x;
          break;
        }
      }
    }
  }

  List> _saranFieldAktif() {
    if (_sembunyiSaranField) return [];
    final tag = _tagKeyboardAktif;
    if (tag == null || _ctrlKeyboard == null) return [];
    final ctrls = _ctrlsBaris(tag);
    if (ctrls == null) return [];
    final parts = tag.split('-');
    final key = '${parts[1]}-${parts[2]}';
    final c = ctrls[key];
    if (c == null) return [];
    if (parts[2] == 'nama') {
      return _saranNamaBarang(c.text)
          .map((b) => {
                'jenis': 'nama',
                'label': '${b['nama']}',
                'sub':
                    '${formatRupiah(int.tryParse('${b['harga1'] ?? ''}') ?? 0)} / ${b['satuan'] ?? ''}',
                'barang': b,
              })
          .toList();
    }
    if (parts[2] == 'satuan') {
      return _saranSatuan(c.text)
          .map((x) => {'jenis': 'satuan', 'label': x, 'sub': '', 'satuan': x})
          .toList();
    }
    return [];
  }

  void _pilihSaranField(Map<String, dynamic> item) {
    final tag = _tagKeyboardAktif;
    final ctrls = tag == null ? null : _ctrlsBaris(tag);
    if (tag == null || ctrls == null) return;
    final parts = tag.split('-');
    final key = '${parts[1]}-${parts[2]}';
    setState(() {
      if (item['jenis'] == 'nama') {
        final b = item['barang'] as Map<String, dynamic>;
        ctrls[key]?.text = '${b['nama']}';
        final h = ctrls['${parts[1]}-harga'];
        if (h != null && h.text.trim().isEmpty) h.text = '${b['harga1'] ?? ''}';
        final st = ctrls['${parts[1]}-satuan'];
        if (st != null && st.text.trim().isEmpty) st.text = '${b['satuan'] ?? ''}';
      } else if (item['jenis'] == 'satuan') {
        ctrls[key]?.text = '${item['satuan']}';
      }
    });
  }

  Widget _stripSaranField() {
    final saran = _saranFieldAktif();
    if (saran.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.lightbulb, size: 16, color: Colors.teal),
        const SizedBox(width: 4),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: saran.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final it = saran[i];
              return ActionChip(
                label: Text(
                  it['label'] +
                      (it['sub'] == '' ? '' : '  •  ${it['sub']}'),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.white,
                onPressed: () => _pilihSaranField(it),
              );
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          onPressed: () => setState(() => _sembunyiSaranField = true),
        ),
      ]),
    );
  }

  Widget _chipSaranForm(
      List<String> calon, TextEditingController c, StateSetter setSheet) {
    if (calon.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: calon
            .map((x) => ActionChip(
                  label: Text(x, style: const TextStyle(fontSize: 11)),
                  onPressed: () => setSheet(() => c.text = x),
                ))
            .toList(),
      ),
    );
  }

  double _hitungChain(
      double harga, double qty, List> chain) {
    var hasil = harga * qty;
    for (final pr in chain) {
      final ops = pr['ops']?.toString() ?? 'x';
      final angka = (pr['angka'] as num?)?.toDouble() ?? 0;
      if (ops == 'x') {
        hasil *= angka;
      } else if (ops == '÷') {
        if (angka != 0) hasil /= angka;
      } else if (ops == '+') {
        hasil += angka;
      } else if (ops == '-') {
        hasil -= angka;
      }
    }
    return hasil;
  }

  void _syncChainCtrls() {
    final kunciBaru = <String>{};
    for (var i = 0; i < steps.length; i++) {
      final chain = (steps[i]['chain'] as List?) ?? [];
      for (var j = 0; j < chain.length; j++) {
        final k = 'step-$i-chain-$j';
        kunciBaru.add(k);
        _chainCtrls.putIfAbsent(
          k,
          () => TextEditingController(
              text: '${((chain[j] as Map)['angka'] as num?)?.toDouble() ?? 0}'),
        );
      }
    }
    final keysToRemove =
        _chainCtrls.keys.where((k) => !kunciBaru.contains(k)).toList();
    for (final k in keysToRemove) {
      _chainCtrls.remove(k)?.dispose();
    }
  }

  void _bangunStepCtrls() {
    _disposeMapCtrls(_stepCtrls);
    _tipeHargaStep = {};
    for (var i = 0; i < steps.length; i++) {
      final st = steps[i];
      _stepCtrls['$i-nama'] = TextEditingController(text: _namaDariStep(st));
      _stepCtrls['$i-harga'] = TextEditingController(
          text: '${((st['harga'] as num?)?.toDouble() ?? 0).toInt()}');
      _stepCtrls['$i-satuan'] =
          TextEditingController(text: '${st['satuan'] ?? ''}');
      _stepCtrls['$i-qty'] =
          TextEditingController(text: '${((st['qty'] as num?)?.toDouble() ?? 0)}');
      _stepCtrls['$i-step'] =
          TextEditingController(text: '${st['rumus'] ?? st['item'] ?? ''}');
      _tipeHargaStep[i] = '${st['tipeHarga'] ?? 'SATUAN'}';
      if (st['opPecah'] != null) {
        _opPecah['step-$i-op'] = st['opPecah'].toString();
      }
    }
  }

  void _commitBaris(String tag) {
    _koreksiOtomatis(tag);
    final parts = tag.split('-');
    if (parts.length < 3) return;
    final idx = int.tryParse(parts[1]) ?? -1;
    if (idx < 0) return;
    if (parts[0] == 'po') {
      _commitSemuaBarisPO();
    } else if (parts[0] == 'step') {
      _commitBarisStep(idx);
    }
  }

  void _commitBarisStep(int i) {
    if (i < 0 || i >= steps.length) return;
    final nama = _stepCtrls['$i-nama']?.text.trim() ?? '';
    final harga = double.tryParse(
            (_stepCtrls['$i-harga']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0;
    final satuan = _stepCtrls['$i-satuan']?.text.trim() ?? '';
    final qty = double.tryParse(
            (_stepCtrls['$i-qty']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0;
    final chainLama = (steps[i]['chain'] as List?) ?? [];
    final chainBaru = >[];
    for (var j = 0; j < chainLama.length; j++) {
      final opsJ = (chainLama[j] as Map)['ops']?.toString() ?? 'x';
      final angkaJ = double.tryParse((_chainCtrls['step-$i-chain-$j']?.text ?? '')
              .replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0;
      chainBaru.add({'ops': opsJ, 'angka': angkaJ});
    }
    final jumlah = _hitungChain(harga, qty, chainBaru);
    final tipe = _tipeHargaStep[i] ?? 'SATUAN';
    var rumus = '${formatRupiah(harga.toInt())} x ${formatHasil(qty)}';
    for (final pr in chainBaru) {
      rumus +=
          " ${pr['ops']} ${formatHasil((pr['angka'] as num?)?.toDouble() ?? 0)}";
    }
    rumus += ' = ${formatRupiah(jumlah.toInt())}';
    setState(() {
      steps[i] = {
        'item': '$nama : $rumus',
        'rumus': rumus,
        'harga': harga,
        'qty': qty,
        'jumlah': jumlah,
        'satuan': satuan,
        'tipeHarga': tipe,
        'chain': chainBaru,
        'opPecah': _opPecah['step-$i-op'] ?? 'x',
      };
    });
  }

  void _commitSemuaBarisStep() {
    for (var i = 0; i < steps.length; i++) {
      _commitBarisStep(i);
    }
  }

  List> _bacaBarisPO() {
    final po = ref.read(poProvider);
    final list = >[];
    for (var i = 0; i < po.items.length; i++) {
      final nama = _poCtrls['$i-nama']?.text.trim() ?? po.items[i].namaBarang;
      var harga = double.tryParse(
              (_poCtrls['$i-harga']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ??
          po.items[i].hargaSatuan.toDouble();
      final pecahSatuanC = _pecahCtrls['po-$i-satuanHarga'];
      final pecahUnitC = _pecahCtrls['po-$i-unit'];
      if (pecahSatuanC != null && pecahUnitC != null) {
        final ps = double.tryParse(
                pecahSatuanC.text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0;
        final pu = double.tryParse(
                pecahUnitC.text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0;
        if (ps > 0 && pu > 0) {
          harga = _acuanDariOp(ps, pu, _opPecah['po-$i-op'] ?? 'x');
        }
      }
      final satuan = _poCtrls['$i-satuan']?.text.trim() ?? po.items[i].satuan;
      final qty = double.tryParse(
              (_poCtrls['$i-qty']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ??
          po.items[i].qty.toDouble();
      final step = _poCtrls['$i-step']?.text.trim() ?? '';
      list.add({
        'nama': nama,
        'harga': harga,
        'satuan': satuan,
        'qty': qty,
        'step': step,
        'jumlah': qty * harga,
        'tipeHarga': _tipeHargaPO[i] ?? 'SATUAN',
      });
    }
    return list;
  }

  void _tulisUlangPO(List> items) {
    final notif = ref.read(poProvider.notifier);
    while (ref.read(poProvider).items.isNotEmpty) {
      notif.hapusItem(0);
    }
    if (items.isEmpty) {
      _bersihkanSemuaStatePecah('po');
      _poChain.clear();
      _tipeHargaPO.clear();
      _disposeMapCtrls(_poCtrls);
      return;
    }
    for (final m in items) {
      final nama = '${m['nama'] ?? ''}'.trim();
      final qty = ((m['qty'] as num?)?.toDouble() ?? 0);
      final harga = ((m['harga'] as num?)?.toDouble() ?? 0).round();
      final satuan = '${m['satuan'] ?? 'pcs'}'.trim();
      if (nama.isEmpty && qty == 0 && harga == 0) continue;
      final parsed = parseInputCepat('${qty.round()} x $nama $harga');
      if (parsed != null) {
        notif.tambahItem(parsed.copyWith(
          qty: qty.round() == qty ? qty.round() : parsed.qty,
          satuan: satuan.isEmpty ? 'pcs' : satuan,
        ));
      } else {
        notif.tambahItem(PoItem(
          namaBarang: nama.isEmpty ? 'Barang' : nama,
          qty: qty.round() <= 0 ? 1 : qty.round(),
          hargaSatuan: harga,
          satuan: satuan.isEmpty ? 'pcs' : satuan,
        ));
      }
    }
  }

  void _commitSemuaBarisPO() => _tulisUlangPO(_bacaBarisPO());

  void _riwKePOLangsung(int index, {bool bukaPO = true}) {
    if (index < 0 || index >= steps.length) return;
    final st = steps[index];
    final nama = _namaDariStep(st);
    final harga = ((st['harga'] as num?)?.toDouble() ?? 0).round();
    final qty = ((st['qty'] as num?)?.toDouble() ?? 0);
    final satuan = '${st['satuan'] ?? ''}';
    final step = '${st['rumus'] ?? st['item'] ?? ''}';
    final lama = _bacaBarisPO();
    final pecahSatuanCek = double.tryParse(
            (_pecahCtrls['step-$index-satuanHarga']?.text ?? '')
                .replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0;
    final pecahUnitCek = double.tryParse(
            (_pecahCtrls['step-$index-unit']?.text ?? '')
                .replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0;
    final idxSama = lama.indexWhere((m) =>
        '${m['nama']}'.trim().toLowerCase() == nama.trim().toLowerCase() &&
        ((m['harga'] as num?)?.toDouble() ?? 0) == harga.toDouble());
    if (idxSama >= 0) {
      lama[idxSama]['qty'] =
          ((lama[idxSama]['qty'] as num?)?.toDouble() ?? 0) + qty;
    } else {
      lama.add({
        'nama': nama,
        'harga': harga.toDouble(),
        'satuan': satuan,
        'qty': qty,
        'step': step,
        'jumlah': qty * harga,
        'tipeHarga': 'SATUAN',
      });
    }
    _tulisUlangPO(lama);
    if (idxSama < 0 && pecahSatuanCek > 0 && pecahUnitCek > 0) {
      final idxBaru = lama.length - 1;
      String teksAngka(double v) =>
          v % 1 == 0 ? v.toInt().toString() : v.toString();
      _pecahCtrls['po-$idxBaru-satuanHarga']?.dispose();
      _pecahCtrls['po-$idxBaru-unit']?.dispose();
      _pecahCtrls['po-$idxBaru-satuanHarga'] =
          TextEditingController(text: teksAngka(pecahSatuanCek));
      _pecahCtrls['po-$idxBaru-unit'] =
          TextEditingController(text: teksAngka(pecahUnitCek));
      _satuanBaseline['po-$idxBaru-satuanHarga'] = pecahSatuanCek;
      _opPecah['po-$idxBaru-op'] = _opPecah['step-$index-op'] ?? 'x';
    }
    _disposeMapCtrls(_poCtrls);
    for (var i = 0; i < lama.length; i++) {
      _poCtrls['$i-nama'] = TextEditingController(text: '${lama[i]['nama']}');
      _poCtrls['$i-harga'] = TextEditingController(
          text: '${(lama[i]['harga'] as num?)?.round() ?? 0}');
      _poCtrls['$i-satuan'] =
          TextEditingController(text: '${lama[i]['satuan'] ?? ''}');
      _poCtrls['$i-qty'] = TextEditingController(text: '${lama[i]['qty']}');
      _poCtrls['$i-step'] =
          TextEditingController(text: '${lama[i]['step'] ?? ''}');
    }
    if (bukaPO) {
      setState(() {
        _tombolKuningAktif = '';
        poTerbuka = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$nama masuk PO - ${_nomorPO()}')));
    }
  }

  void _poKeIndex(int idx) {
    if (idx < 0 || idx >= _poTersimpan.length) return;
    final po = _poTersimpan[idx];
    final items = (po['items'] as List)
        .map((e) => {
              'nama': e['nama'] ?? '',
              'harga': (e['harga'] as num?)?.toDouble() ?? 0,
              'satuan': e['satuan'] ?? '',
              'qty': (e['qty'] as num?)?.toDouble() ?? 0,
              'step': e['step'] ?? '',
              'jumlah': (e['jumlah'] as num?)?.toDouble() ?? 0,
            })
        .toList();
    _tulisUlangPO(items);
    _disposeMapCtrls(_poCtrls);
    for (var i = 0; i < items.length; i++) {
      _poCtrls['$i-nama'] = TextEditingController(text: '${items[i]['nama']}');
      _poCtrls['$i-harga'] = TextEditingController(
          text: '${(items[i]['harga'] as num?)?.round() ?? 0}');
      _poCtrls['$i-satuan'] =
          TextEditingController(text: '${items[i]['satuan'] ?? ''}');
      _poCtrls['$i-qty'] = TextEditingController(text: '${items[i]['qty']}');
      _poCtrls['$i-step'] =
          TextEditingController(text: '${items[i]['step'] ?? ''}');
    }
    setState(() {
      _poTerbukaIndex = idx;
      _poNomor = (po['nomorInt'] as int?) ?? _poNomor;
      _pelangganC.text = '${po['pelanggan'] ?? ''}';
      _nomorWAC.text = '${po['nomorWA'] ?? ''}';
      _poRevisi = true;
      poTerbuka = true;
    });
  }

  Future<void> _simpanCepatDariNomorPO() async => _simpanPO();

  Future<void> _simpanPO() async {
    final messenger = ScaffoldMessenger.of(context);
    _commitSemuaBarisPO();
    final data = _bacaBarisPO();
    if (data.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('PO kosong, isi dulu 1 baris.')));
      return;
    }
    final pelanggan =
        _pelangganC.text.trim().isEmpty ? 'Tanpa Nama' : _pelangganC.text.trim();
    final nomorWA = _nomorWAC.text.trim();
    final total = data.fold<double>(
        0, (a, m) => a + ((m['jumlah'] as num?)?.toDouble() ?? 0));
    final nomorSimpan = _nomorPO();
    final tanggalSimpan = DateTime.now().toIso8601String();
    final itemsDB = data
        .map((m) => {
              'item':
                  "${m['nama']} : ${formatHasil(((m['qty'] as num?)?.toDouble() ?? 0))} x ${formatRupiah(((m['harga'] as num?)?.toDouble() ?? 0).round())} = ${formatRupiah(((m['jumlah'] as num?)?.toDouble() ?? 0).round())}",
              'rumus': m['step'] ?? '',
              'namaBarang': m['nama'] ?? '',
              'hargaAcuan': m['harga'],
              'satuanAngka': 1,
              'opSatuan': 'x',
              'harga': m['harga'],
              'qty': m['qty'],
              'jumlah': m['jumlah'],
              'satuan': m['satuan'] ?? '',
            })
        .toList();
    int? dbId;
    if (_poRevisi) {
      final idx = _poTersimpan.indexWhere((pp) => pp['nomorInt'] == _poNomor);
      dbId = idx >= 0 ? _poTersimpan[idx]['dbId'] as int? : null;
      if (dbId != null) {
        try {
          await _db.updatePo(
            id: dbId,
            tanggal: tanggalSimpan,
            pelanggan: pelanggan,
            nomorWA: nomorWA,
            dicek: _poDicek,
            total: total,
            items: itemsDB,
          );
        } catch (_) {}
      }
    } else {
      try {
        dbId = await _db.simpanPoBaru(
          nomor: nomorSimpan,
          tanggal: tanggalSimpan,
          pelanggan: pelanggan,
          nomorWA: nomorWA,
          dicek: _poDicek,
          total: total,
          items: itemsDB,
        );
      } catch (_) {}
    }
    try {
      await _db.simpanPelanggan(pelanggan);
    } catch (_) {}
    setState(() {
      if (_poRevisi) {
        final idx =
            _poTersimpan.indexWhere((pp) => pp['nomorInt'] == _poNomor);
        final tanggalLama = idx >= 0
            ? '${_poTersimpan[idx]['tanggal'] ?? tanggalSimpan}'
            : tanggalSimpan;
        final isi = {
          'nomorInt': _poNomor,
          'nomor': nomorSimpan,
          'tanggal': tanggalLama,
          'pelanggan': pelanggan,
          'items': data,
          'total': total,
          'dicek': _poDicek,
          'nomorWA': nomorWA,
          'dbId': dbId,
        };
        if (idx >= 0) {
          _poTersimpan[idx] = isi;
        } else {
          _poTersimpan.add(isi);
        }
      } else {
        _poTersimpan.add({
          'nomorInt': _poNomor,
          'nomor': nomorSimpan,
          'tanggal': tanggalSimpan,
          'pelanggan': pelanggan,
          'items': data,
          'total': total,
          'dicek': _poDicek,
          'nomorWA': nomorWA,
          'dbId': dbId,
        });
        _poNomor++;
      }
      _tulisUlangPO([]);
      _poTerpilih = {};
      _pelangganC.clear();
      _nomorWAC.clear();
      _poDicek = false;
      _poRevisi = false;
      _sembunyiSaranPelanggan = false;
      _resetKeyboard();
    });
    messenger.showSnackBar(
        SnackBar(content: Text('PO $nomorSimpan tersimpan untuk $pelanggan.')));
  }

  void _muatPO(Map<String, dynamic> p) {
    final items = (p['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _tulisUlangPO(items);
      _disposeMapCtrls(_poCtrls);
      _tipeHargaPO = {};
      for (var i = 0; i < items.length; i++) {
        final m = items[i];
        _poCtrls['$i-nama'] = TextEditingController(text: '${m['nama'] ?? ''}');
        _poCtrls['$i-harga'] = TextEditingController(
            text: '${((m['harga'] as num?)?.toDouble() ?? 0).round()}');
        _poCtrls['$i-satuan'] =
            TextEditingController(text: '${m['satuan'] ?? ''}');
        _poCtrls['$i-qty'] = TextEditingController(
            text: '${((m['qty'] as num?)?.toDouble() ?? 0)}');
        _poCtrls['$i-step'] =
            TextEditingController(text: '${m['step'] ?? ''}');
        _tipeHargaPO[i] = '${m['tipeHarga'] ?? 'SATUAN'}';
      }
      _poNomor = (p['nomorInt'] as int?) ?? _poNomor;
      _pelangganC.text = '${p['pelanggan'] ?? ''}';
      _nomorWAC.text = '${p['nomorWA'] ?? ''}';
      _poDicek = (p['dicek'] as bool?) ?? false;
      _poRevisi = true;
      _poTerpilih = {};
      _tombolKuningAktif = '';
      poTerbuka = true;
      _resetKeyboard();
    });
  }

  void _logKePO(int i) {
    _commitBarisStep(i);
    _riwKePOLangsung(i, bukaPO: false);
    _habisMPlus = true;
  }

  Widget _panelCek() {
    if (_stepCtrls.length != steps.length * 5) _bangunStepCtrls();
    _syncChainCtrls();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Centang baris yang sudah dicek. Tap field untuk edit lewat keyboard bawah.',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      const SizedBox(height: 6),
      if (steps.isEmpty)
        const Center(child: Text('Belum ada step. Pencet = dulu.')),
      if (steps.isNotEmpty)
        Expanded(
          child: ListView.builder(
            itemCount: steps.length,
            itemBuilder: (_, i) {
              final chainI = (steps[i]['chain'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [];
              return _barisItem(
                index: i,
                tag: 'step',
                cNama: _stepCtrls['$i-nama']!,
                cHarga: _stepCtrls['$i-harga']!,
                cSatuan: _stepCtrls['$i-satuan']!,
                cQty: _stepCtrls['$i-qty']!,
                dicek: _stepTerpilih.contains(i),
                onCek: () => setState(() {
                  if (_stepTerpilih.contains(i)) {
                    _stepTerpilih.remove(i);
                  } else {
                    _stepTerpilih.add(i);
                  }
                }),
                onHapus: () => setState(() {
                  steps.removeAt(i);
                  _stepTerpilih.remove(i);
                  _geserStateBarisSetelahHapus('step', i);
                  _bangunStepCtrls();
                }),
                tampilChain: true,
                chain: chainI,
                chainCtrls: List.generate(
                    chainI.length, (j) => _chainCtrls['step-$i-chain-$j']!),
                onChainTambah: () {
                  _commitBarisStep(i);
                  setState(() {
                    (steps[i]['chain'] as List)
                        .add({'ops': 'x', 'angka': 0.0});
                  });
                },
                onChainOps: (j) {
                  setState(() {
                    const opsList = ['x', '÷', '+', '-'];
                    final cur =
                        (steps[i]['chain'] as List)[j]['ops']?.toString() ??
                            'x';
                    (steps[i]['chain'] as List)[j]['ops'] =
                        opsList[(opsList.indexOf(cur) + 1) % opsList.length];
                  });
                  _commitBarisStep(i);
                },
                onChainHapus: (j) {
                  _commitBarisStep(i);
                  setState(() {
                    (steps[i]['chain'] as List).removeAt(j);
                    final ch = steps[i]['chain'] as List;
                    for (var k = 0; k < ch.length; k++) {
                      _chainCtrls['step-$i-chain-$k']?.text =
                          '${((ch[k] as Map)['angka'] as num?)?.toDouble() ?? 0}';
                    }
                    final keysToDrop = _chainCtrls.keys
                        .where((key) =>
                            key.startsWith('step-$i-chain-') &&
                            (int.tryParse(key.split('-').last) ?? -1) >=
                                ch.length)
                        .toList();
                    for (final kd in keysToDrop) {
                      _chainCtrls.remove(kd)?.dispose();
                    }
                  });
                },
                onMPlus: () => _logKePO(i),
              );
            },
          ),
        ),
    ]);
  }

  List> _entriVarianLS(Map<String, dynamic> b) {
    final hasil = >[];
    final namaVarian = '${b['varian'] ?? ''}'
        .split(',')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    String labelDari(Map m) {
      final sb = '${m['satuanBaru'] ?? ''}';
      final st = '${m['satuan'] ?? ''}';
      return sb.trim().isNotEmpty ? sb : st;
    }

    final perVarian = (b['satuanPerVarian'] as List?) ?? [];
    if (perVarian.isNotEmpty) {
      for (var gi = 0; gi < perVarian.length; gi++) {
        final grup = (perVarian[gi] as List?) ?? [];
        final nama = gi < namaVarian.length ? namaVarian[gi] : '';
        final hargaListB = (b['hargaList'] as List?) ?? [];
        final hargaVarianGi = gi < hargaListB.length
            ? (double.tryParse('${hargaListB[gi]}') ?? 0)
            : (gi == 0 ? (double.tryParse('${b['harga1'] ?? ''}') ?? 0) : 0.0);
        var pertama = true;
        for (final x in grup) {
          final m = Map<String, dynamic>.from(x as Map);
          final label = labelDari(m);
          if (label.trim().isEmpty) continue;
          hasil.add({
            'varian': ((m['varian'] as String?)?.trim().isNotEmpty == true
                ? m['varian'].toString()
                : nama),
            'tampilVarian': pertama,
            'satuan': label,
            'nominal': double.tryParse('${m['nominal'] ?? ''}') ?? 0.0,
            'op': m['op']?.toString() ?? 'x',
            'isi': double.tryParse('${m['isi'] ?? ''}') ?? 0.0,
            'hargaVarian': hargaVarianGi,
          });
          pertama = false;
        }
      }
    }
    if (hasil.isEmpty) {
      var pertama = true;
      for (final x in (b['satuanList'] as List?) ?? []) {
        final m = Map<String, dynamic>.from(x as Map);
        final label = labelDari(m);
        if (label.trim().isEmpty) continue;
        hasil.add({
          'varian': ((m['varian'] as String?)?.trim().isNotEmpty == true
              ? m['varian'].toString()
              : (namaVarian.isNotEmpty ? namaVarian.first : '')),
          'tampilVarian': pertama,
          'satuan': label,
          'nominal': double.tryParse('${m['nominal'] ?? ''}') ?? 0.0,
          'op': m['op']?.toString() ?? 'x',
          'isi': double.tryParse('${m['isi'] ?? ''}') ?? 0.0,
          'hargaVarian': double.tryParse('${b['harga1'] ?? ''}') ?? 0.0,
        });
        pertama = false;
      }
    }
    return hasil;
  }

  Map<String, dynamic> _barisDasarLS(Map<String, dynamic> b) {
    final perVarian = (b['satuanPerVarian'] as List?) ?? [];
    Map<String, dynamic>? row;
    if (perVarian.isNotEmpty) {
      final grup = (perVarian[0] as List?) ?? [];
      for (final x in grup) {
        final m = Map<String, dynamic>.from(x as Map);
        if (m['dasar'] == true) {
          row = m;
          break;
        }
      }
      row ??=
          grup.isNotEmpty ? Map<String, dynamic>.from(grup.first as Map) : null;
    }
    row ??= ((b['satuanList'] as List?) ?? []).isNotEmpty
        ? Map<String, dynamic>.from(((b['satuanList'] as List).first as Map))
        : null;
    final hargaVarian = double.tryParse('${b['harga1'] ?? ''}') ?? 0.0;
    if (row == null) {
      return {'op': 'x', 'isi': 0.0, 'hargaVarian': hargaVarian};
    }
    return {
      'op': row['op']?.toString() ?? 'x',
      'isi': double.tryParse('${row['isi'] ?? ''}') ?? 0.0,
      'hargaVarian': hargaVarian,
    };
  }

  Widget _panelLS() {
    final q = queryLS.toLowerCase();
    final filtered = daftarBarang.where((b) {
      if (q.isEmpty) return true;
      return b['nama'].toString().toLowerCase().contains(q) ||
          b['kode'].toString().toLowerCase().contains(q) ||
          b['kategori'].toString().toLowerCase().contains(q);
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _lsCariC,
            readOnly: true,
            showCursor: true,
            onTap: () => _aktifkanField(_lsCariC, 1),
            decoration: dec('Cari kode / nama / kategori...'),
            onChanged: (v) => setState(() => queryLS = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          width: 36,
          child: FilledButton(
            onPressed: bukaFormTambahBarang,
            style: FilledButton.styleFrom(
                padding: EdgeInsets.zero, shape: const CircleBorder()),
            child: const Text('+',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (filtered.isEmpty)
        const Center(child: Text('Belum ada barang. Tap + untuk tambah.')),
      if (filtered.isNotEmpty)
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final b = filtered[i];
              final idxDaftar =
                  daftarBarang.indexWhere((x) => x['kode'] == b['kode']);
              final aktif =
                  barangDipilih != null && barangDipilih!['kode'] == b['kode'];
              final entriVarian = _entriVarianLS(b);
              final dasarLS = _barisDasarLS(b);
              final kodeB = b['kode'].toString();
              final expanded = _lsExpand.contains(kodeB);
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: aktif ? Colors.green.shade100 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        final h1 = double.tryParse(b['harga1']
                                .toString()
                                .replaceAll(RegExp(r'[^0-9.]'), '')) ??
                            0;
                        setState(() {
                          barangDipilih = {
                            'kode': b['kode'].toString(),
                            'nama': b['nama'].toString(),
                            'kategori': b['kategori'].toString(),
                            'harga1': b['harga1'].toString(),
                            'satuan': (b['satuan'] ?? '').toString(),
                            'opPecah': dasarLS['op']?.toString() ?? 'x',
                            'isiSatuan': '${dasarLS['isi']}',
                            'hargaVarian': '${dasarLS['hargaVarian']}',
                          };
                          _hargaAcuanVarian = h1 > 0 ? h1 : null;
                          _labelSaranVarian = (b['satuan'] ?? '').toString();
                          _hargaLayarDiubah = false;
                          _qtyMPlus = null;
                          adaQtyHitung = false;
                          ekspresi = "Saran ${b['nama']}";
                          layar = _groupBacktick(h1.toStringAsFixed(0));
                          entryBaru = true;
                          _resetKeyboard();
                        });
                      },
                      child: Row(children: [
                        CircleAvatar(
                          radius: 14,
                          child: Text(
                            b['nama'].toString().isEmpty
                                ? '?'
                                : b['nama'].toString()[0].toLowerCase(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${b['nama']}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: '  •  ${b['kategori']}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            expanded
                                ? Icons.close_fullscreen
                                : Icons.open_in_full,
                            size: 18,
                            color: Colors.teal,
                          ),
                          tooltip:
                              expanded ? 'Ciutkan' : 'Maximize - lihat varian',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => setState(() {
                            if (expanded) {
                              _lsExpand.remove(kodeB);
                            } else {
                              _lsExpand.add(kodeB);
                            }
                          }),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit,
                              size: 18, color: Colors.teal),
                          tooltip: 'Edit barang',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => bukaFormTambahBarang(barangEdit: b),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              size: 18, color: Colors.red),
                          tooltip: 'Hapus barang',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            if (idxDaftar >= 0) {
                              setState(() {
                                daftarBarang.removeAt(idxDaftar);
                                if (barangDipilih != null &&
                                    barangDipilih!['kode'] == b['kode']) {
                                  barangDipilih = null;
                                  _hargaAcuanVarian = null;
                                  _labelSaranVarian = "";
                                  _hargaLayarDiubah = false;
                                }
                              });
                            }
                          },
                        ),
                      ]),
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entriVarian.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: Text(
                                  'Belum ada varian',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600),
                                ),
                              ),
                            for (var ei = 0; ei < entriVarian.length; ei++) ...[
                              if (ei > 0)
                                Container(
                                    height: 1, color: Colors.grey.shade200),
                              InkWell(
                                onTap: () {
                                  final nomDouble =
                                      (entriVarian[ei]['nominal'] as double);
                                  final nomInt = nomDouble.round();
                                  final namaVar =
                                      '${entriVarian[ei]['varian'] ?? ''}'
                                          .trim();
                                  final satVar =
                                      '${entriVarian[ei]['satuan'] ?? ''}'
                                          .trim();
                                  final opVar =
                                      entriVarian[ei]['op']?.toString() ?? 'x';
                                  final isiVar =
                                      (entriVarian[ei]['isi'] as num?)
                                              ?.toDouble() ??
                                          1;
                                  final hargaVarAcuan =
                                      (entriVarian[ei]['hargaVarian'] as num?)
                                              ?.toDouble() ??
                                          nomDouble;
                                  setState(() {
                                    barangDipilih = {
                                      'kode': b['kode'].toString(),
                                      'nama': b['nama'].toString(),
                                      'kategori': b['kategori'].toString(),
                                      'harga1': nomInt.toString(),
                                      'satuan': satVar,
                                      'opPecah': opVar,
                                      'isiSatuan':
                                          '${isiVar > 0 ? isiVar : 1.0}',
                                      'hargaVarian':
                                          '${hargaVarAcuan > 0 ? hargaVarAcuan : nomDouble}',
                                    };
                                    _hargaAcuanVarian = nomDouble > 0
                                        ? nomDouble
                                        : hargaVarAcuan;
                                    _labelSaranVarian = namaVar.isNotEmpty
                                        ? '$namaVar • $satVar'
                                        : satVar;
                                    _hargaLayarDiubah = false;
                                    _qtyMPlus = null;
                                    adaQtyHitung = false;
                                    opPending = "";
                                    op = "";
                                    ekspresi =
                                        "Saran ${b['nama']} ($satVar)";
                                    layar = _groupBacktick(
                                        (nomDouble > 0
                                                ? nomInt
                                                : hargaVarAcuan.round())
                                            .toString());
                                    entryBaru = true;
                                    _resetKeyboard();
                                  });
                                },
                                child: Container(
                                  color: (barangDipilih != null &&
                                          barangDipilih!['kode'] ==
                                              b['kode'].toString() &&
                                          barangDipilih!['satuan'] ==
                                              '${entriVarian[ei]['satuan']}' &&
                                          barangDipilih!['harga1'] ==
                                              (entriVarian[ei]['nominal']
                                                      as double)
                                                  .round()
                                                  .toString())
                                      ? Colors.green.shade100
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  child: Text(
                                    '${entriVarian[ei]['varian']}'.trim().isNotEmpty
                                        ? '${entriVarian[ei]['varian']} => ${entriVarian[ei]['satuan']} ✓ ${formatRupiah((entriVarian[ei]['nominal'] as double).round())}'
                                        : '${entriVarian[ei]['satuan']} ✓ ${formatRupiah((entriVarian[ei]['nominal'] as double).round())}',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            if (entriVarian.isNotEmpty)
                              Container(
                                  height: 1, color: Colors.grey.shade200),
                            InkWell(
                              onTap: () => bukaFormTambahBarang(barangEdit: b),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: Text(
                                  '+ Tambah varian',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.teal.shade700,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _panelRiw() {
    if (_stepCtrls.length != steps.length * 5) _bangunStepCtrls();
    _syncChainCtrls();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
          child: Text(
            'Log hitung. Tap → PO untuk pakai lagi baris ini ke PO.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_sweep, size: 18),
          label: const Text('Hapus Semua'),
          onPressed: () => setState(() {
            steps.clear();
            _stepTerpilih.clear();
            _bersihkanSemuaStatePecah('step');
            _disposeMapCtrls(_stepCtrls);
          }),
        ),
      ]),
      const SizedBox(height: 6),
      if (steps.isEmpty)
        const Center(
          child: Text(
            'Belum ada log step. Hitung / pencet = / M+ dulu.',
            textAlign: TextAlign.center,
          ),
        ),
      if (steps.isNotEmpty)
        Expanded(
          child: ListView.builder(
            itemCount: steps.length,
            itemBuilder: (_, i) {
              final chainI = (steps[i]['chain'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [];
              return _barisItem(
                index: i,
                tag: 'step',
                cNama: _stepCtrls['$i-nama']!,
                cHarga: _stepCtrls['$i-harga']!,
                cSatuan: _stepCtrls['$i-satuan']!,
                cQty: _stepCtrls['$i-qty']!,
                dicek: _stepTerpilih.contains(i),
                onCek: () => setState(() {
                  if (_stepTerpilih.contains(i)) {
                    _stepTerpilih.remove(i);
                  } else {
                    _stepTerpilih.add(i);
                  }
                }),
                onHapus: () => setState(() {
                  steps.removeAt(i);
                  _stepTerpilih.remove(i);
                  _geserStateBarisSetelahHapus('step', i);
                  _bangunStepCtrls();
                }),
                tombolExtra: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ElevatedButton(
                      onPressed: () => _logKePO(i), child: const Text('→ PO')),
                ),
                tampilChain: true,
                chain: chainI,
                chainCtrls: List.generate(
                    chainI.length, (j) => _chainCtrls['step-$i-chain-$j']!),
                onChainTambah: () {
                  _commitBarisStep(i);
                  setState(() {
                    (steps[i]['chain'] as List)
                        .add({'ops': 'x', 'angka': 0.0});
                  });
                },
                onChainOps: (j) {
                  setState(() {
                    const opsList = ['x', '÷', '+', '-'];
                    final cur =
                        (steps[i]['chain'] as List)[j]['ops']?.toString() ??
                            'x';
                    (steps[i]['chain'] as List)[j]['ops'] =
                        opsList[(opsList.indexOf(cur) + 1) % opsList.length];
                  });
                  _commitBarisStep(i);
                },
                onChainHapus: (j) {
                  _commitBarisStep(i);
                  setState(() {
                    (steps[i]['chain'] as List).removeAt(j);
                    final ch = steps[i]['chain'] as List;
                    for (var k = 0; k < ch.length; k++) {
                      _chainCtrls['step-$i-chain-$k']?.text =
                          '${((ch[k] as Map)['angka'] as num?)?.toDouble() ?? 0}';
                    }
                    final keysToDrop = _chainCtrls.keys
                        .where((key) =>
                            key.startsWith('step-$i-chain-') &&
                            (int.tryParse(key.split('-').last) ?? -1) >=
                                ch.length)
                        .toList();
                    for (final kd in keysToDrop) {
                      _chainCtrls.remove(kd)?.dispose();
                    }
                  });
                },
              );
            },
          ),
        ),
    ]);
  }

  Widget _panelCps() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        '1 baris = 1 barang. Angka pertama = qty, angka kedua = harga.',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _cpsTempelC,
        maxLines: 3,
        readOnly: true,
        showCursor: true,
        onTap: () => _aktifkanField(_cpsTempelC, 1),
        decoration: dec('Tempel di sini...'),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.paste, size: 18),
            label: const Text('Tempel Clipboard'),
            onPressed: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              final t = d?.text ?? '';
              if (t.isNotEmpty) setState(() => _cpsTempelC.text = t);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Urai jadi Baris'),
            onPressed: () => setState(() {
              _cpsBaris = _cpsTempelC.text
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .map(_parseSatuCPS)
                  .toList();
            }),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (_cpsBaris.isEmpty)
        const Text(
          'Belum ada baris. Tempel teks lalu pencet Urai jadi Baris.',
          textAlign: TextAlign.center,
        ),
      if (_cpsBaris.isNotEmpty)
        Expanded(
          child: ListView.builder(
            itemCount: _cpsBaris.length,
            itemBuilder: (_, i) {
              final r = _cpsBaris[i];
              final jumlah = ((r['qty'] as num?)?.toDouble() ?? 0) *
                  ((r['harga'] as num?)?.toDouble() ?? 0);
              final namaCps = '${r['nama']}';
              final saranCps = _barangDariNama(namaCps) == null
                  ? _saranNamaBarang(namaCps)
                  : >[];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(namaCps,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(
                              'Qty ${r['qty']} x ${formatRupiah(((r['harga'] as num?)?.toDouble() ?? 0).round())} = ${formatRupiah(jumlah.round())}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete,
                            size: 18, color: Colors.red),
                        onPressed: () => setState(() => _cpsBaris.removeAt(i)),
                      ),
                    ]),
                    if (saranCps.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Maksudnya?',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            for (final b in saranCps)
                              ActionChip(
                                label: Text('${b['nama']}',
                                    style: const TextStyle(fontSize: 11)),
                                onPressed: () => setState(() {
                                  final lama = '${r['nama']}'.toLowerCase();
                                  r['nama'] = '${b['nama']}';
                                  if (((r['harga'] as num?)?.toDouble() ??
                                          0) ==
                                      0) {
                                    r['harga'] =
                                        double.tryParse('${b['harga1'] ?? ''}') ??
                                            0;
                                  }
                                  _aliasCopas[lama] = '${b['kode']}';
                                }),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: Text('Masukkan ${_cpsBaris.length} Baris ke CEK'),
          onPressed: _cpsBaris.isEmpty
              ? null
              : () {
                  for (final r in _cpsBaris) {
                    final nama = '${r['nama']}';
                    final qty = (r['qty'] as num?)?.toDouble() ?? 0;
                    final harga = (r['harga'] as num?)?.toDouble() ?? 0;
                    final jumlah = qty * harga;
                    steps.add({
                      'item':
                          '$nama : ${formatHasil(qty)} x ${formatRupiah(harga.round())} = ${formatRupiah(jumlah.round())}',
                      'rumus':
                          '$nama : ${formatHasil(qty)} x ${formatRupiah(harga.round())} = ${formatRupiah(jumlah.round())}',
                      'harga': harga,
                      'qty': qty,
                      'jumlah': jumlah,
                    });
                  }
                  final n = _cpsBaris.length;
                  setState(() {
                    _cpsBaris = [];
                    _cpsTempelC.clear();
                    layar = formatHasil(totalCek);
                    ekspresi = 'Total CEK = ${formatHasil(totalCek)}';
                    _tombolKuningAktif = 'CEK';
                    _resetKeyboard();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$n baris masuk CEK.')));
                },
        ),
      ),
    ]);
  }

  Widget _panelPO() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Tap kartu untuk revisi PO di panel PO. Tap 🗑 untuk hapus PO tersimpan.',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.list_alt, size: 18),
          label: const Text('PO Recent (Daftar Item)'),
          onPressed: () => setState(() {
            poTerbuka = true;
            _tombolKuningAktif = '';
            _resetKeyboard();
          }),
        ),
      ),
      const SizedBox(height: 8),
      if (_poTersimpan.isEmpty)
        const Center(
          child: Text(
            'Belum ada PO tersimpan.\nPO aktif tersimpan otomatis sebagai draf.',
            textAlign: TextAlign.center,
          ),
        ),
      if (_poTersimpan.isNotEmpty)
        Expanded(
          child: ListView.builder(
            itemCount: _poTersimpan.length,
            itemBuilder: (_, i) {
              final pp = _poTersimpan[i];
              final orderKartu = _bangunOrderKartu(pp);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: KartuPO(
                      po: orderKartu,
                      onTap: () => _muatPO(pp),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                    tooltip: 'Hapus PO tersimpan',
                    onPressed: () async {
                      final dbId = pp['dbId'] as int?;
                      if (dbId != null) {
                        try {
                          await _db.hapusPo(dbId);
                        } catch (_) {}
                      }
                      if (!mounted) return;
                      setState(() => _poTersimpan.removeAt(i));
                    },
                  ),
                ],
              );
            },
          ),
        ),
    ]);
  }

  Widget _panelDaftarItemPO() {
    final po = ref.watch(poProvider);
    final n = po.items.length;
    if (_poCtrls.length != n * 5) {
      _disposeMapCtrls(_poCtrls);
      for (var i = 0; i < n; i++) {
        final it = po.items[i];
        _poCtrls['$i-nama'] = TextEditingController(text: it.namaBarang);
        _poCtrls['$i-harga'] = TextEditingController(text: '${it.hargaSatuan}');
        _poCtrls['$i-satuan'] = TextEditingController(text: it.satuan);
        _poCtrls['$i-qty'] = TextEditingController(text: '${it.qty}');
        _poCtrls['$i-step'] = TextEditingController(
            text:
                '${it.namaBarang} : ${it.qty} x ${formatRupiah(it.hargaSatuan)} = ${formatRupiah(it.qty * it.hargaSatuan)}');
      }
    }
    double total = 0;
    for (var i = 0; i < n; i++) {
      final qty = double.tryParse(
              (_poCtrls['$i-qty']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0;
      final harga = double.tryParse((_poCtrls['$i-harga']?.text ?? '')
              .replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0;
      total += qty * harga;
    }
    final saran = _saranPelanggan();
    final tampilSaran =
        (_ctrlKeyboard == _pelangganC || _ctrlKeyboard == _nomorWAC) &&
            !_sembunyiSaranPelanggan &&
            saran.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: Color(0xFFE0F7E9),
        border: Border(top: BorderSide(color: Color(0xFF2EBD5A), width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text(
            'PO - Daftar Item',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F5132)),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Tutup PO, balik ke keypad',
            onPressed: () => setState(() {
              _commitSemuaBarisPO();
              poTerbuka = false;
              _resetKeyboard();
            }),
          ),
        ]),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.amber.shade200,
                borderRadius: BorderRadius.circular(16)),
            child: Text(
              'No. PO: ${_nomorPO()}${_poRevisi ? ' (revisi)' : ''}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _simpanCepatDariNomorPO,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: Color(0xFF2EBD5A), shape: BoxShape.circle),
              child: const Icon(Icons.save, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _poTerbukaIndex > 0
                ? () => _poKeIndex(_poTerbukaIndex - 1)
                : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:
                    _poTerbukaIndex > 0 ? Colors.teal : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_left,
                  size: 18, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _poTersimpan.isEmpty
                  ? 'PO 1/1'
                  : 'PO ${_poTerbukaIndex < 0 ? _poTersimpan.length + 1 : _poTerbukaIndex + 1}/${_poTersimpan.length + 1}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          InkWell(
            onTap: _poTerbukaIndex >= 0 &&
                    _poTerbukaIndex < _poTersimpan.length - 1
                ? () => _poKeIndex(_poTerbukaIndex + 1)
                : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _poTerbukaIndex >= 0 &&
                        _poTerbukaIndex < _poTersimpan.length - 1
                    ? Colors.teal
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_right,
                  size: 18, color: Colors.white),
            ),
          ),
          if (_poDicek) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.teal, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                '✓ Sudah dicek',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
              child: _fieldBorderAtas(
                  label: 'Nama Pelanggan', padat: true, controller: _pelangganC)),
          const SizedBox(width: 8),
          Expanded(
              child: _fieldBorderAtas(
                  label: 'Nomor WA (08...)',
                  controller: _nomorWAC,
                  angka: true,
                  padat: true)),
        ]),
        if (_poTersimpan.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var pi = 0; pi < _poTersimpan.length; pi++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(
                      '${_poTersimpan[pi]['nomor'] ?? ''} • ${_poTersimpan[pi]['pelanggan'] ?? ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: _poTerbukaIndex == pi
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    backgroundColor: _poTerbukaIndex == pi
                        ? Colors.teal.shade100
                        : Colors.white,
                    onPressed: () => _poKeIndex(pi),
                  ),
                ),
              ActionChip(
                label: const Text('+ PO Baru', style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() {
                  _poTerbukaIndex = -1;
                  _poRevisi = false;
                  _pelangganC.clear();
                  _nomorWAC.clear();
                }),
              ),
            ]),
          ),
        ],
        if (tampilSaran) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.shade200),
            ),
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: saran.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, si) {
                final m = saran[si];
                return InkWell(
                  onTap: () => _pilihSaranPelanggan(m),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          m['nama'] ?? '',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (m['wa'] ?? '').isEmpty ? 'tanpa WA' : m['wa']!,
                        style: TextStyle(
                          fontSize: 12,
                          color: (m['wa'] ?? '').isEmpty
                              ? Colors.grey
                              : Colors.teal.shade800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.north_west,
                          size: 14, color: Colors.grey),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: n == 0
              ? const Center(
                  child: Text(
                    'Belum ada item - pencet LS pilih barang, lalu ketik qty, lalu M+',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: n,
                  itemBuilder: (_, i) {
                    final chainPo = _poChain.putIfAbsent(i, () => []);
                    for (var j = 0; j < chainPo.length; j++) {
                      _chainCtrls.putIfAbsent(
                        'po-$i-chain-$j',
                        () => TextEditingController(
                            text:
                                '${((chainPo[j] as Map)['angka'] as num?)?.toDouble() ?? 0}'),
                      );
                    }
                    return _barisItem(
                      index: i,
                      tag: 'po',
                      cNama: _poCtrls['$i-nama']!,
                      cHarga: _poCtrls['$i-harga']!,
                      cSatuan: _poCtrls['$i-satuan']!,
                      cQty: _poCtrls['$i-qty']!,
                      dicek: _poTerpilih.contains(i),
                      onCek: () => setState(() {
                        if (_poTerpilih.contains(i)) {
                          _poTerpilih.remove(i);
                        } else {
                          _poTerpilih.add(i);
                        }
                      }),
                      onHapus: () => setState(() {
                        ref.read(poProvider.notifier).hapusItem(i);
                        _poTerpilih.remove(i);
                        _geserStateBarisSetelahHapus('po', i);
                        final chainBaru = <int, List>>{};
                        final tipeBaru = <int, String>{};
                        _poChain.forEach((k, v) {
                          if (k < i) {
                            chainBaru[k] = v;
                          } else if (k > i) {
                            chainBaru[k - 1] = v;
                          }
                        });
                        _tipeHargaPO.forEach((k, v) {
                          if (k < i) {
                            tipeBaru[k] = v;
                          } else if (k > i) {
                            tipeBaru[k - 1] = v;
                          }
                        });
                        _poChain
                          ..clear()
                          ..addAll(chainBaru);
                        _tipeHargaPO
                          ..clear()
                          ..addAll(tipeBaru);
                        _disposeMapCtrls(_poCtrls);
                      }),
                      tampilChain: true,
                      chain: chainPo,
                      chainCtrls: List.generate(chainPo.length,
                          (j) => _chainCtrls['po-$i-chain-$j']!),
                      onChainTambah: () {
                        _commitSemuaBarisPO();
                        setState(() {
                          _poChain
                              .putIfAbsent(i, () => [])
                              .add({'ops': 'x', 'angka': 0.0});
                        });
                      },
                      onChainOps: (j) {
                        setState(() {
                          const opsList = ['x', '÷', '+', '-'];
                          final cur = (_poChain[i]!)[j]['ops']?.toString() ??
                              'x';
                          (_poChain[i]!)[j]['ops'] = opsList[
                              (opsList.indexOf(cur) + 1) % opsList.length];
                        });
                        _commitSemuaBarisPO();
                      },
                      onChainHapus: (j) {
                        _commitSemuaBarisPO();
                        setState(() {
                          (_poChain[i]!).removeAt(j);
                          for (var k = 0; k < (_poChain[i]!).length; k++) {
                            _chainCtrls['po-$i-chain-$k']?.text =
                                '${(((_poChain[i]!)[k] as Map)['angka'] as num?)?.toDouble() ?? 0}';
                          }
                          final keysToDrop = _chainCtrls.keys
                              .where((key) =>
                                  key.startsWith('po-$i-chain-') &&
                                  (int.tryParse(key.split('-').last) ?? -1) >=
                                      (_poChain[i]!).length)
                              .toList();
                          for (final kd in keysToDrop) {
                            _chainCtrls.remove(kd)?.dispose();
                          }
                        });
                      },
                      onMPlus: () {
                        _commitSemuaBarisPO();
                        setState(() {});
                      },
                    );
                  },
                ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: const Color(0xFF0F766E),
              borderRadius: BorderRadius.circular(8)),
          child: Text(
            'Total Jumlah: ${formatRupiah(total.round())}  |  $n baris',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
      ]),
    );
  }

  PoOrder _poOrderAktif() {
    final po = ref.read(poProvider);
    final namaPelanggan =
        _pelangganC.text.trim().isEmpty ? 'Tanpa Nama' : _pelangganC.text.trim();
    final nomorWA = _nomorWAC.text.trim();
    final idPelanggan = nomorWA.isEmpty ? namaPelanggan : nomorWA;
    final items = <PoItem>[];
    for (var i = 0; i < po.items.length; i++) {
      final it = po.items[i];
      final satuanBaris =
          (_poCtrls['$i-satuan']?.text.trim().isNotEmpty == true)
              ? _poCtrls['$i-satuan']!.text.trim()
              : it.satuan;
      items.add(
        PoItem(
          namaBarang: it.namaBarang,
          qty: it.qty,
          hargaSatuan: it.hargaSatuan,
          diskonItem: it.diskonItem,
          kodeBarang: it.kodeBarang,
          variasi: it.variasi,
          satuan: satuanBaris,
        ),
      );
    }
    return PoOrder(
      id: _nomorPO(),
      tanggal: DateTime.now(),
      customer:
          Customer(id: idPelanggan, namaOrang: namaPelanggan, nomorWA: nomorWA),
      items: items,
      diskonTotal: 0,
      ongkir: 0,
      dp: 0,
      catatan: '',
      status: PoStatus.values.first,
    );
  }

  PoOrder? _poTerakhir;

  Future<void> _kirimWA() async {
    final messenger = ScaffoldMessenger.of(context);
    if (poTerbuka) _commitSemuaBarisPO();
    final po = poTerbuka ? _poOrderAktif() : (_poTerakhir ?? _poOrderAktif());
    if (po.items.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('PO kosong, isi dulu 1 baris.')));
      return;
    }
    try {
      await shareNotaPdf(po);
    } catch (e) {
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text('Gagal buat nota: $e')));
    }
  }

  void _tampilNota() {
    if (poTerbuka) _commitSemuaBarisPO();
    final po = _poOrderAktif();
    if (po.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PO kosong, isi dulu 1 baris.')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              const Text('Preview Nota',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: NotaPreview(
                po: po,
                onChanged: (u) => setState(() => _poTerakhir = u),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _resetKeyboard() {
    _modeKeyboard = 0;
    _ctrlKeyboard = null;
    _qwertyCaps = 1;
    _tagKeyboardAktif = null;
  }

  void _aktifkanField(TextEditingController c, int mode, {String? tag}) {
    if (_tagKeyboardAktif != null && _tagKeyboardAktif != tag) {
      _commitBaris(_tagKeyboardAktif!);
    }
    setState(() {
      _ctrlKeyboard = c;
      _modeKeyboard = mode;
      _tagKeyboardAktif = tag;
      if (mode == 1) _qwertyCaps = 1;
      if (identical(c, _pelangganC) || identical(c, _nomorWAC)) {
        _sembunyiSaranPelanggan = false;
      }
      _sembunyiSaranField = false;
    });
  }

  void _ketikKeyboard(String s) {
    final c = _ctrlKeyboard;
    if (c == null) return;
    final sel = c.selection;
    final text = c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final baru = text.replaceRange(start, end, s);
    c.value = c.value.copyWith(
        text: baru, selection: TextSelection.collapsed(offset: start + s.length));
    setState(() {
      if (identical(c, _lsCariC)) queryLS = baru;
      if (identical(c, _pelangganC) || identical(c, _nomorWAC)) {
        _sembunyiSaranPelanggan = false;
      }
      _sembunyiSaranField = false;
      if (_modeKeyboard == 1 && _qwertyCaps == 1) _qwertyCaps = 0;
    });
    _autoLengkapiPelanggan();
    _koreksiOtomatis(_tagKeyboardAktif ?? '');
  }

  void _hapusKeyboard() {
    final c = _ctrlKeyboard;
    if (c == null) return;
    final sel = c.selection;
    final text = c.text;
    String baru;
    int pos;
    if (sel.isValid && sel.start != sel.end) {
      baru = text.replaceRange(sel.start, sel.end, '');
      pos = sel.start;
    } else if (sel.isValid && sel.start > 0) {
      baru = text.replaceRange(sel.start - 1, sel.start, '');
      pos = sel.start - 1;
    } else if (text.isNotEmpty) {
      baru = text.substring(0, text.length - 1);
      pos = baru.length;
    } else {
      return;
    }
    c.value = c.value
        .copyWith(text: baru, selection: TextSelection.collapsed(offset: pos));
    setState(() {
      if (identical(c, _lsCariC)) queryLS = baru;
      if (identical(c, _pelangganC) || identical(c, _nomorWAC)) {
        _sembunyiSaranPelanggan = false;
      }
      _sembunyiSaranField = false;
    });
    _autoLengkapiPelanggan();
    _koreksiOtomatis(_tagKeyboardAktif ?? '');
  }

  String _huruf(String k) =>
      _qwertyCaps == 0 ? k.toLowerCase() : k.toUpperCase();

  Widget _tombolKeyboard(
    String label, {
    int flex = 1,
    Color? bg,
    Color? fg,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: bg ?? Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black26),
              boxShadow: const [
                BoxShadow(
                    color: Color(0xFFB8A888), offset: Offset(0, 3), blurRadius: 0)
              ],
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: fg ?? Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTapBaskoroKeypad() => _onTapTombolKuning('CEK');

  Widget _tombolBaskoroKeypad() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: GestureDetector(
          onTap: _onTapBaskoroKeypad,
          child: Container(
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black26, width: 0.8),
              boxShadow: const [
                BoxShadow(
                    color: Color(0xFFB8A888), offset: Offset(0, 4), blurRadius: 0),
                BoxShadow(
                    color: Colors.white70, offset: Offset(0, -1), blurRadius: 0),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('BSKRO',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: 0.3)),
                    Container(
                        width: 26,
                        height: 1.5,
                        color: Colors.white,
                        margin: const EdgeInsets.symmetric(vertical: 2)),
                    const Text('WCUN',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tombolBaskoro(VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.blue.shade400,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black26),
              boxShadow: const [
                BoxShadow(
                    color: Color(0xFFB8A888), offset: Offset(0, 3), blurRadius: 0)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('BSKRO',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1)),
                    Container(
                        width: 26,
                        height: 1.5,
                        color: Colors.white,
                        margin: const EdgeInsets.symmetric(vertical: 2)),
                    const Text('WCUN',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barisBaskoro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: GestureDetector(
        onTap: () => setState(() => _modeKeyboard = 1),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.blue.shade400,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black26),
          ),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'BASKORO•WINGCHUN',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barisQwerty(List<String> keys) {
    return Expanded(
      child: Row(children: [
        for (final k in keys)
          _tombolKeyboard(_huruf(k), onTap: () => _ketikKeyboard(_huruf(k)))
      ]),
    );
  }

  Widget _keyboardQwerty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(children: [
        if (_saranFieldAktif().isNotEmpty) _stripSaranField(),
        _barisQwerty(['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P']),
        _barisQwerty(['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L']),
        Expanded(
          child: Row(children: [
            _tombolKeyboard(
              _qwertyCaps == 2 ? '⇪' : '⇧',
              bg: _qwertyCaps == 0
                  ? Colors.grey.shade300
                  : (_qwertyCaps == 1
                      ? Colors.blue.shade200
                      : Colors.blue),
              fg: _qwertyCaps == 2 ? Colors.white : Colors.black,
              onTap: () => setState(() {
                if (_qwertyCaps == 2) {
                  _qwertyCaps = 0;
                } else {
                  _qwertyCaps = _qwertyCaps == 0 ? 1 : 0;
                }
              }),
              onLongPress: () => setState(() => _qwertyCaps = 2),
            ),
            for (final k in ['Z', 'X', 'C', 'V', 'B', 'N', 'M'])
              _tombolKeyboard(_huruf(k), onTap: () => _ketikKeyboard(_huruf(k))),
            _tombolKeyboard('⌫',
                bg: Colors.grey.shade300, onTap: _hapusKeyboard),
          ]),
        ),
        Expanded(
          child: Row(children: [
            _tombolKeyboard('123',
                bg: Colors.grey.shade300,
                onTap: () => setState(() => _modeKeyboard = 3)),
            _tombolKeyboard('Spasi',
                flex: 3, onTap: () => _ketikKeyboard(' ')),
            _tombolKeyboard('.', onTap: () => _ketikKeyboard('.')),
            _tombolKeyboard('⏎', onTap: () => _ketikKeyboard('\n')),
            _tombolBaskoro(() => setState(() => _modeKeyboard = 0)),
          ]),
        ),
      ]),
    );
  }

  Widget _keyboardSimbol() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(children: [
        Expanded(
          child: Row(children: [
            for (final k in ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')'])
              _tombolKeyboard(k, onTap: () => _ketikKeyboard(k))
          ]),
        ),
        Expanded(
          child: Row(children: [
            for (final k in ['-', '_', '=', '+', '/', '?', ':', ';', "'", '"'])
              _tombolKeyboard(k, onTap: () => _ketikKeyboard(k))
          ]),
        ),
        Expanded(
          child: Row(children: [
            for (final k in ['.', ',', '<', '>', '[', ']', '{', '}'])
              _tombolKeyboard(k, onTap: () => _ketikKeyboard(k)),
            _tombolKeyboard('⌫',
                bg: Colors.grey.shade300, onTap: _hapusKeyboard),
          ]),
        ),
        Expanded(
          child: Row(children: [
            _tombolKeyboard('123',
                bg: Colors.grey.shade300,
                onTap: () => setState(() => _modeKeyboard = 2)),
            _tombolKeyboard('Spasi',
                flex: 3, onTap: () => _ketikKeyboard(' ')),
            _tombolKeyboard('.', onTap: () => _ketikKeyboard('.')),
            _tombolKeyboard('⏎', onTap: () => _ketikKeyboard('\n')),
            _tombolBaskoro(() => setState(() => _modeKeyboard = 0)),
          ]),
        ),
      ]),
    );
  }

  Widget _keyboardAngka() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(children: [
        for (final baris in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9']
        ])
          Expanded(
            child: Row(children: [
              for (final k in baris)
                _tombolKeyboard(k, onTap: () => _ketikKeyboard(k))
            ]),
          ),
        Expanded(
          child: Row(children: [
            _tombolKeyboard('−', onTap: () => _ketikKeyboard('-')),
            _tombolKeyboard('0', onTap: () => _ketikKeyboard('0')),
            _tombolKeyboard('⌫',
                bg: Colors.grey.shade300, onTap: _hapusKeyboard),
          ]),
        ),
        Expanded(
          child: Row(children: [
            _tombolKeyboard('ABC',
                bg: Colors.grey.shade300,
                onTap: () => setState(() => _modeKeyboard = 1)),
            _tombolKeyboard('.', onTap: () => _ketikKeyboard('.')),
            _tombolBaskoro(() => setState(() => _modeKeyboard = 0)),
          ]),
        ),
      ]),
    );
  }

  Widget _areaTombolBawah() {
    if (_modeKeyboard == 1) return _keyboardQwerty();
    if (_modeKeyboard == 2) return _keyboardAngka();
    if (_modeKeyboard == 3) return _keyboardSimbol();
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(children: [
            Expanded(
              child: Row(children: [
                tombol('AC', bg: Colors.blue.shade400, fg: Colors.white),
                tombol('MRT', bg: Colors.grey.shade400),
                tombol('M-', bg: Colors.grey.shade400),
                tombol('LS', bg: Colors.orange.shade100, besar: true),
                _tombolBaskoroKeypad(),
                tombol('CPS', bg: Colors.amber, fg: Colors.black),
                tombol('BEP', bg: Colors.pink, fg: Colors.white),
              ]),
            ),
            Expanded(
              child: Row(children: [
                tombol('OFF', bg: Colors.blue.shade400, fg: Colors.white),
                tombol('7'),
                tombol('8'),
                tombol('9'),
                tombol('RIW', bg: Colors.grey.shade300),
                tombol('MU', bg: Colors.grey.shade300),
                tombol('MC', bg: Colors.grey.shade300),
              ]),
            ),
            Expanded(
              child: Row(children: [
                tombol('%', bg: Colors.grey.shade300),
                tombol('4'),
                tombol('5'),
                tombol('6'),
                tombol('-', bg: Colors.grey.shade300),
                tombol('÷', bg: Colors.grey.shade300),
                tombol('MR', bg: Colors.grey.shade300),
              ]),
            ),
            Expanded(
              child: Row(children: [
                tombol('+/-', bg: Colors.grey.shade300),
                tombol('1'),
                tombol('2'),
                tombol('3'),
                tombol('+', bg: Colors.grey.shade300),
                tombol('x', bg: Colors.grey.shade300),
                tombol('PO', bg: Colors.teal, fg: Colors.white),
              ]),
            ),
            Expanded(
              child: Row(children: [
                tombol('ON/C', bg: Colors.blue.shade400, fg: Colors.white),
                tombol('0'),
                tombol('00'),
                tombol('.'),
                tombol('=', bg: Colors.blue, fg: Colors.white, besar: true),
                tombol('M+', bg: Colors.green, fg: Colors.white),
                tombol('⌫', bg: Colors.grey.shade300),
              ]),
            ),
          ]),
        ),
      ),
      if (_ctrlKeyboard != null) _barisBaskoro(),
    ]);
  }

  Map<String, dynamic> _parseSatuCPS(String mentah) {
    final teks =
        mentah.replaceAll('`', '').replaceAll(RegExp(r'[Rr][Pp]'), '');
    final nums = RegExp(r'[0-9]+(?:[.,][0-9]+)?')
        .allMatches(teks)
        .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0)
        .toList();
    var nama = teks.replaceAll(RegExp(r'[0-9]+(?:[.,][0-9]+)?'), ' ');
    nama = nama.replaceAll(RegExp(r'[xX]'), ' ');
    nama = nama.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ');
    nama = nama.replaceAll(RegExp(r' +'), ' ').trim();
    if (nama.isEmpty) nama = 'Barang';
    double qty = 1;
    double harga = 0;
    if (nums.length >= 2) {
      qty = nums[0];
      harga = nums[1];
    } else if (nums.length == 1 && nums[0] > 1000) {
      qty = 1;
      harga = nums[0];
    } else if (nums.length == 1) {
      qty = nums[0];
    }
    final kunci = nama.toLowerCase();
    Map<String, dynamic>? barangAlias;
    if (_aliasCopas.containsKey(kunci)) {
      final kode = _aliasCopas[kunci]!;
      for (final b in daftarBarang) {
        if ('${b['kode']}'.toLowerCase() == kode.toLowerCase()) {
          barangAlias = b;
          break;
        }
      }
    }
    if (barangAlias == null) {
      for (final b in daftarBarang) {
        if ('${b['nama']}'.toLowerCase() == kunci) {
          barangAlias = b;
          _aliasCopas[kunci] = '${b['kode']}';
          _db.simpanAliasCopas(namaCopas: kunci, kodeBarang: '${b['kode']}');
          break;
        }
      }
    }
    if (harga == 0) {
      if (barangAlias != null) {
        harga = double.tryParse('${barangAlias['harga1']}') ?? 0;
      }
      if (harga == 0) harga = hargaAcuan;
    }
    return {'nama': nama, 'qty': qty, 'harga': harga};
  }

  final List> daftarBarang = [];
  String queryLS = "";
  final kodeCtrl = TextEditingController();
  final namaCtrl = TextEditingController();
  String kategoriPilih = "";
  final List<String> listKategori = ["Semen", "Besi", "Cat", "Keramik", "Pipa"];
  final kategoriBaruCtrl = TextEditingController();
  final unitCtrl = TextEditingController();
  final harga1Ctrl = TextEditingController();
  final List<TextEditingController> varianCtrls = [TextEditingController()];
  final List<TextEditingController> hargaCtrls = [TextEditingController()];
  List<List<SatuanItem>> satuanPerVarian = [
    [
      SatuanItem(
          satuan: "",
          dasar: true,
          qty: "",
          isi: "",
          op: "x",
          nominal: "",
          satuanBaru: "")
    ]
  ];
  List<SatuanItem> _satuanBaruKosong() => [
        SatuanItem(
            satuan: "",
            dasar: true,
            qty: "",
            isi: "",
            op: "x",
            nominal: "",
            satuanBaru: "")
      ];
  List> _satuanGabunganMap() =>
      satuanPerVarian.expand((g) => g.map((x) => x.toMap())).toList();
  final Set<String> daftarSatuan = {"sak", "kg", "kilo", "m", "pcs"};

  void tambahKeDaftarSatuan(String nama) {
    final v = nama.trim().toLowerCase();
    if (v.isEmpty) return;
    daftarSatuan.add(v);
  }

  InputDecoration dec(String hint, {String? prefix}) {
    return InputDecoration(
      hintText: hint,
      prefixText: prefix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      border: const OutlineInputBorder(),
    );
  }

  List<SatuanItem> satuanList = [
    SatuanItem(
        satuan: "",
        dasar: true,
        qty: "",
        isi: "",
        op: "x",
        nominal: "",
        satuanBaru: ""),
  ];
  String modeHitung = "PEMBULATAN";
  int desimal = 0;
  final List> steps = [];

  double get hargaAcuan {
    if (_hargaAcuanVarian != null && _hargaAcuanVarian! > 0) {
      return _hargaAcuanVarian!;
    }
    if (barangDipilih != null) {
      return double.tryParse("${barangDipilih!["harga1"]}") ?? 0;
    }
    return 0;
  }

  double get manual => double.tryParse(_stripBacktick(layar)) ?? 0;

  double get hargaAktifKalkulator {
    final l = manual;
    if (_hargaLayarDiubah && l > 0) return l;
    return hargaAcuan;
  }

  double get persen {
    if (hargaAcuan == 0) return 0;
    final current = hargaAktifKalkulator;
    if (current == 0) return 0;
    return ((current - hargaAcuan) / hargaAcuan) * 100;
  }

  Color warnaSaran() {
    if (hargaAcuan == 0) return Colors.black;
    if (hargaAktifKalkulator == 0) return Colors.black;
    if (persen < -20) return const Color(0xFFB71C1C);
    if (persen < 0) return Colors.red;
    if (persen < 5) return const Color(0xFFB58900);
    if (persen < 15) return Colors.blue;
    return Colors.green;
  }

  String teksAcuan() {
    if (hargaAcuan == 0) return "---";
    final dasar = formatRupiah(hargaAcuan.round());
    if (_labelSaranVarian.isNotEmpty) {
      return "Saran: $dasar ($_labelSaranVarian)";
    }
    return "Saran: $dasar";
  }

  String teksSaran() {
    if (hargaAcuan == 0) return "---";
    return "${persen >= 0 ? '+' : ''}${persen.toStringAsFixed(1)}%";
  }

  String _stripBacktick(String s) => s
      .replaceAll('`', '')
      .replaceAll('Rp', '')
      .replaceAll(' ', '')
      .replaceAll(',', '')
      .trim();

  double _parseLayar() => double.tryParse(_stripBacktick(layar)) ?? 0;

  String _groupBacktick(String s) {
    if (s == "E" || s.isEmpty) return s;
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      s = s.substring(1);
    }
    var dotParts = s.split('.');
    var integer = dotParts[0].replaceAll(RegExp(r'[^0-9]'), '');
    if (integer.isEmpty) integer = "0";
    var rev = integer.split('').reversed.toList();
    var grouped = <String>[];
    for (var i = 0; i < rev.length; i++) {
      if (i > 0 && i % 3 == 0) grouped.add('`');
      grouped.add(rev[i]);
    }
    var hasil = grouped.reversed.join('');
    if (dotParts.length > 1 && dotParts[1].isNotEmpty) {
      hasil = "$hasil.${dotParts[1]}";
    }
    return neg ? "-$hasil" : hasil;
  }

  String _layarAtasCasio() {
    if (ekspresi.isEmpty) return '';
    var e = ekspresi.replaceAll('`', '');
    if (e.length > 14) e = e.substring(e.length - 14);
    return e;
  }

  String _layarBawahCasio() {
    var bersih = _stripBacktick(layar);
    if (bersih == 'E' || bersih.isEmpty) return bersih;
    var parts = bersih.split('.');
    var integer = parts[0].replaceAll('-', '');
    if (integer.length > 12) {
      var neg2 = bersih.startsWith('-') ? '-' : '';
      var digits = integer + (parts.length > 1 ? parts[1] : '');
      var mantissa = '${digits[0]}.${digits.substring(1, 10)}';
      var eksponen = integer.length - 1;
      return '$neg2$mantissa $eksponen';
    }
    return _groupBacktick(bersih);
  }

  String formatHasil(double v) {
    if (v.isNaN || v.isInfinite) return "E";
    String mentah;
    if (modeHitung == "ORIGINAL") {
      mentah = v.toStringAsFixed(desimal);
    } else if (modeRound == "CUT") {
      final p = desimal == 0 ? 1.0 : _pow10(desimal);
      final potong = (v * p).truncate() / p;
      mentah = desimal == 0
          ? potong.round().toString()
          : potong.toStringAsFixed(desimal);
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
    if (!s.contains('.')) return s;
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s.isEmpty ? "0" : s;
  }

  double? hitungDasar(double a, String o, double b) {
    if (o == "+") return a + b;
    if (o == "-") return a - b;
    if (o == "x") return a * b;
    if (o == "÷" || o == "/") {
      if (b == 0) return null;
      return a / b;
    }
    return b;
  }

  double hitungNominal(SatuanItem s, {String? hargaTeks}) {
    final qty = double.tryParse(s.qtyCtrl.text) ?? 1;
    final isi = double.tryParse(s.isiCtrl.text) ?? 1;
    final hargaForm = double.tryParse(
            (hargaTeks ?? harga1Ctrl.text).replaceAll(RegExp(r'[^0-9]'), '')) ??
        0;
    final harga = hargaForm > 0 ? hargaForm : hargaAcuan;
    if (s.dasar) return harga * qty;
    if (s.op == "÷") {
      if (isi == 0) return 0;
      return qty * (harga / isi);
    }
    return qty * harga * isi;
  }

  void refreshNominal(SatuanItem s, {String? hargaTeks}) {
    if (s.nominalManual) return;
    final hasil = hitungNominal(s, hargaTeks: hargaTeks);
    s.nominalCtrl.text = hasil.toStringAsFixed(0);
  }

  void syncUnitDariDasar({int? grup}) {
    final list =
        satuanPerVarian[(grup ?? 0).clamp(0, satuanPerVarian.length - 1)];
    final dasar =
        list.firstWhere((x) => x.dasar == true, orElse: () => list.first);
    unitCtrl.text = dasar.namaCtrl.text;
  }

  String teksRumusSatuan(SatuanItem s, {String? hargaTeks}) {
    final qty = s.qtyCtrl.text.isEmpty ? "1" : s.qtyCtrl.text;
    final isi = s.isiCtrl.text.isEmpty ? "1" : s.isiCtrl.text;
    final satuanBiru = s.namaCtrl.text;
    final unitHijau =
        s.satuanBaruCtrl.text.isEmpty ? satuanBiru : s.satuanBaruCtrl.text;
    final infoHasil = hitungNominal(s, hargaTeks: hargaTeks);
    if (s.dasar) {
      return "$qty $satuanBiru = ${formatRupiah(infoHasil.round())}  (info)";
    }
    return "$qty $satuanBiru ${s.op} $isi $unitHijau = ${formatRupiah(infoHasil.round())}  (info)";
  }

  void dialogBabe() {
    final namaBarang = barangDipilih == null
        ? "Belum pilih barang (pencet LS)"
        : "${barangDipilih!["nama"]}";
    final acuan = hargaAcuan;
    final nilaiManual = hargaAktifKalkulator;
    final warna = warnaSaran();
    final namaWarna = warna == Colors.black
        ? "HITAM - belum ada acuan"
        : warna == const Color(0xFFB71C1C)
            ? "MERAH TUA - rugi besar"
            : warna == Colors.red
                ? "MERAH - rugi"
                : warna == const Color(0xFFB58900)
                    ? "KUNING - waspada"
                    : warna == Colors.blue
                        ? "BIRU - untung kecil"
                        : "HIJAU - untung";
    final bep = acuan > 0 ? acuan * 1.1 : 0.0;
    final totalStep = steps.fold<double>(
        0, (a, x) => a + ((x["jumlah"] as num?)?.toDouble() ?? 0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("BABE•INFO - Dialog Uni"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Barang: $namaBarang",
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              Text("Unit Biru (auto sama): ${unitCtrl.text}",
                  style: const TextStyle(fontSize: 11)),
              const Divider(),
              Text(
                "Layar: $layar | Acuan: ${acuan == 0 ? "---" : formatRupiah(acuan.round())} | Persen: ${acuan == 0 || nilaiManual == 0 ? "---" : "${persen.toStringAsFixed(1)}%"}",
                style: TextStyle(fontSize: 11, color: warna),
              ),
              Text(
                "Warna: $namaWarna | BEP: ${bep == 0 ? "---" : formatRupiah(bep.round())} | Memori: ${formatRupiah(memori.round())}",
                style: const TextStyle(fontSize: 11),
              ),
              const Divider(),
              const Text("SATUAN - Biru = dasar, Hijau = satuan baru",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              for (var gi = 0; gi < satuanPerVarian.length; gi++) ...[
                if (satuanPerVarian.length > 1)
                  Text(
                    "Varian ${gi + 1} • Harga ${gi + 1} = ${formatRupiah(double.tryParse(hargaCtrls[gi].text.replaceAll(RegExp(r'[^0-9]'), ''))?.round() ?? 0)}",
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                for (var x in satuanPerVarian[gi])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      "${teksRumusSatuan(x, hargaTeks: hargaCtrls[gi].text)}${x.nominalManual ? " • NOMINAL MANUAL" : " • NOMINAL AUTO"}",
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
              const Divider(),
              const Text("CEK - STEP (riwayat hitung Casio)",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              if (steps.isEmpty)
                const Text("Belum ada step.", style: TextStyle(fontSize: 11)),
              ...steps.asMap().entries.map((e) => Text(
                    "${e.key + 1}. ${e.value["rumus"] ?? e.value["item"]}",
                    style: const TextStyle(fontSize: 11),
                  )),
              if (steps.isNotEmpty)
                Text("Total step: ${formatRupiah(totalStep.round())}",
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Tutup"))
        ],
      ),
    );
  }

  void refreshSemuaNominal() {
    for (var gi = 0; gi < satuanPerVarian.length; gi++) {
      for (var s in satuanPerVarian[gi]) {
        refreshNominal(s, hargaTeks: hargaCtrls[gi].text);
      }
    }
  }

  void _inputAngka(String t) {
    _habisMPlus = false;
    _hargaLayarDiubah = true;
    if (adaError) {
      layar = "0";
      ekspresi = "";
      akumulator = 0;
      opPending = "";
      op = "";
      adaError = false;
      entryBaru = true;
    }
    layar = _stripBacktick(layar);
    if (entryBaru) {
      layar = (t == ".") ? "0." : t;
      entryBaru = false;
      adaQtyHitung = false;
    } else {
      if (t == "." && layar.contains(".")) return;
      if (layar.replaceAll("-", "").replaceAll(".", "").length >= 12) return;
      if (layar == "0" && t != ".") {
        layar = t;
      } else {
        layar += t;
      }
    }
    layar = _groupBacktick(layar);
  }

  void _inputOperator(String t) {
    _habisMPlus = false;
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    if (opPending.isNotEmpty && entryBaru) {
      opPending = t;
      op = t;
      ekspresi = "${formatHasil(akumulator)} $t";
      entryBaru = true;
      return;
    }
    if (opPending.isNotEmpty && !entryBaru) {
      final h = hitungDasar(akumulator, opPending, cur);
      if (h == null) {
        layar = "E";
        adaError = true;
        return;
      }
      akumulator = h;
      angka1 = h;
      layar = formatHasil(h);
    } else if (opPending.isEmpty) {
      akumulator = cur;
      angka1 = cur;
      qtyHitung = cur;
      adaQtyHitung = true;
    }
    opPending = t;
    op = t;
    ekspresi = "${formatHasil(akumulator)} $t";
    entryBaru = true;
  }

  void _inputSamaDengan() {
    if (adaError) return;
    if (_habisMPlus) {
      _habisMPlus = false;
      _akhiriSatuPO();
      return;
    }
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    double a, b;
    String o;
    if (opPending.isNotEmpty) {
      a = akumulator;
      b = cur;
      o = opPending;
      lastOp = o;
      lastAngka2 = b;
    } else if (lastOp.isNotEmpty) {
      a = cur;
      b = lastAngka2;
      o = lastOp;
    } else {
      return;
    }
    final h = hitungDasar(a, o, b);
    if (h == null) {
      layar = "E";
      ekspresi = "${formatHasil(a)} $o ${formatHasil(b)} = E";
      adaError = true;
      return;
    }
    ekspresi = "${formatHasil(a)} $o ${formatHasil(b)} = ${formatHasil(h)}";
    final hargaB = barangDipilih == null
        ? -1.0
        : (double.tryParse('${barangDipilih!["harga1"]}') ?? -1);
    final hargaStep = (hargaB >= 0 && b == hargaB)
        ? b
        : (hargaB >= 0 && a == hargaB)
            ? a
            : a;
    final qtyStep = (hargaB >= 0 && b == hargaB)
        ? a
        : (hargaB >= 0 && a == hargaB)
            ? b
            : b;
    _qtyMPlus = qtyStep;
    final namaB = barangDipilih == null ? '' : '${barangDipilih!["nama"]} : ';
    steps.add({
      "item": "$namaB$ekspresi",
      "rumus": ekspresi,
      "harga": hargaStep,
      "qty": qtyStep,
      "jumlah": h,
      "chain": >[],
    });
    akumulator = h;
    angka1 = h;
    layar = formatHasil(h);
    opPending = "";
    op = "";
    entryBaru = true;
  }

  void _akhiriSatuPO() {
    _commitSemuaBarisPO();
    _simpanSemuaKeDB();
    final total = ref.read(poProvider).items.fold<double>(
        0, (a, e) => a + (e.qty.toDouble() * e.hargaSatuan.toDouble()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'PO ${_nomorPO()} selesai - Total ${formatRupiah(total.round())} - ketik PO berikutnya'),
      ),
    );
    setState(() {
      poTerbuka = false;
      _tombolKuningAktif = '';
      _resetKeyboard();
    });
  }

  void _inputPersen() {
    if (adaError) return;
    final cur = double.tryParse(_stripBacktick(layar)) ?? 0;
    double h;
    if (opPending == "+") {
      h = akumulator + (akumulator * cur / 100);
    } else if (opPending == "-") {
      h = akumulator - (akumulator * cur / 100);
    } else if (opPending == "x") {
      h = akumulator * cur / 100;
    } else if (opPending == "÷" || opPending == "/") {
      if (cur == 0) {
        layar = "E";
        adaError = true;
        return;
      }
      h = akumulator / (cur / 100);
    } else {
      h = cur / 100;
    }
    ekspresi = opPending.isEmpty
        ? "$cur% = ${formatHasil(h)}"
        : "${formatHasil(akumulator)} $opPending $cur% = ${formatHasil(h)}";
    steps.add({
      "item": ekspresi,
      "rumus": ekspresi,
      "harga": akumulator,
      "qty": cur,
      "jumlah": h,
    });
    layar = formatHasil(h);
    akumulator = h;
    angka1 = h;
    opPending = "";
    op = "";
    entryBaru = true;
  }

  double _angkaLayar() => _parseLayar();

  void _pencetTaxPlus() {
    final v = _angkaLayar();
    final pajak = v * tarifPajak / 100;
    layar = formatHasil(v + pajak);
    ekspresi =
        "${formatHasil(v)} TAX+ $tarifPajak% = ${formatHasil(v + pajak)}";
    steps.add({
      "item": ekspresi,
      "rumus": ekspresi,
      "harga": v,
      "qty": tarifPajak,
      "jumlah": v + pajak,
    });
    entryBaru = true;
  }

  void _pencetTaxMin() {
    final v = _angkaLayar();
    final bersih = v / (1 + tarifPajak / 100);
    layar = formatHasil(bersih);
    ekspresi =
        "${formatHasil(v)} TAX- $tarifPajak% = ${formatHasil(bersih)}";
    steps.add({
      "item": ekspresi,
      "rumus": ekspresi,
      "harga": v,
      "qty": tarifPajak,
      "jumlah": bersih,
    });
    entryBaru = true;
  }

  void _setTax() {
    final v = _angkaLayar();
    if (v >= 0 && v <= 100) {
      tarifPajak = v;
      ekspresi = "SET TAX = ${formatHasil(v)}%";
      layar = formatHasil(v);
      entryBaru = true;
    }
  }

  void _pencetCost() {
    laciCost = _angkaLayar();
    ekspresi = "COST = ${formatHasil(laciCost)}";
    entryBaru = true;
    _hitungCSM();
  }

  void _pencetSell() {
    laciSell = _angkaLayar();
    ekspresi = "SELL = ${formatHasil(laciSell)}";
    entryBaru = true;
    _hitungCSM();
  }

  void _pencetMargin() {
    final v = _angkaLayar();
    if (v > 0 && v < 100) {
      laciMargin = v;
      ekspresi = "MARGIN = ${formatHasil(v)}%";
      entryBaru = true;
      _hitungCSM();
    }
  }

  void _hitungCSM() {
    if (laciCost > 0 && laciMargin > 0 && laciMargin < 100 && laciSell == 0) {
      laciSell = laciCost / (1 - laciMargin / 100);
      layar = formatHasil(laciSell);
      ekspresi = "SELL = COST / (1 - MARGIN) = ${formatHasil(laciSell)}";
    } else if (laciSell > 0 &&
        laciMargin > 0 &&
        laciMargin < 100 &&
        laciCost == 0) {
      laciCost = laciSell * (1 - laciMargin / 100);
      layar = formatHasil(laciCost);
      ekspresi = "COST = SELL x (1 - MARGIN) = ${formatHasil(laciCost)}";
    } else if (laciCost > 0 && laciSell > 0 && laciSell != laciCost) {
      laciMargin = (laciSell - laciCost) / laciSell * 100;
      layar = formatHasil(laciMargin);
      ekspresi = "MARGIN = (SELL - COST) / SELL = ${formatHasil(laciMargin)}%";
    }
    if (laciCost > 0 || laciSell > 0 || laciMargin > 0) {
      steps.add({
        "item": ekspresi,
        "rumus": ekspresi,
        "harga": laciCost,
        "qty": laciMargin,
        "jumlah": laciSell,
      });
    }
  }

  void _resetCSM() {
    laciCost = 0;
    laciSell = 0;
    laciMargin = 0;
    ekspresi = "COST / SELL / MARGIN direset";
  }

  void _gantiRound() {
    modeRound = modeRound == "5/4"
        ? "CUT"
        : modeRound == "CUT"
            ? "F"
            : "5/4";
    ekspresi = "ROUND = $modeRound";
    layar = formatHasil(_angkaLayar());
  }

  void _gantiAdd2() {
    modeAdd2 = !modeAdd2;
    ekspresi = modeAdd2 ? "ADD2 ON: ketik 123 -> 1.23" : "ADD2 OFF";
  }

  double _terapkanAdd2(double v) => modeAdd2 ? v / 100 : v;

  double get totalCek {
    double t = 0;
    for (final s in steps) {
      t += (s["jumlah"] as num?)?.toDouble() ?? 0;
    }
    return t;
  }

  void pencet(String t) {
    if (_mrIndex >= 0 && t != 'MR' && t != 'M-' && t != 'MC' && t != 'MRT') {
      _mrIndex = -1;
    }
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC") {
        layar = "0";
        ekspresi = "";
        akumulator = 0;
        angka1 = 0;
        opPending = "";
        op = "";
        entryBaru = true;
        adaError = false;
        lastOp = "";
        lastAngka2 = 0;
        adaQtyHitung = false;
        qtyHitung = 1;
        _qtyMPlus = null;
        _hargaAcuanVarian = null;
        _labelSaranVarian = "";
        _hargaLayarDiubah = false;
      } else if (t == "ON/C") {
        layar = "0";
        entryBaru = true;
        adaError = false;
        _hargaLayarDiubah = false;
      } else if (t == "OFF") {
        layar = "0";
        ekspresi = "";
        entryBaru = true;
        _hargaLayarDiubah = false;
      } else if (t == "PO") {
        _onTapTombolKuning('PO');
      } else if (t == "LS") {
        _onTapTombolKuning('LS');
      } else if (t == "CEK") {
        _onTapTombolKuning('CEK');
      } else if (t == "CPS") {
        _onTapTombolKuning('CPS');
      } else if (t == "RIW") {
        _onTapTombolKuning('RIW');
      } else if (t == "TAX+") {
        _pencetTaxPlus();
      } else if (t == "TAX-") {
        _pencetTaxMin();
      } else if (t == "SET TAX") {
        _setTax();
      } else if (t == "COST") {
        _pencetCost();
      } else if (t == "SELL") {
        _pencetSell();
      } else if (t == "MARGIN") {
        _pencetMargin();
      } else if (t == "CSM CLR") {
        _resetCSM();
      } else if (t == "ROUND") {
        _gantiRound();
      } else if (t == "ADD2") {
        _gantiAdd2();
      } else if (t == "BEP") {
        if (hargaAcuan > 0) {
          layar = formatHasil(hargaAcuan * 1.1);
          ekspresi = "BEP = Acuan x 110%";
        } else {
          layar = formatHasil((double.tryParse(_stripBacktick(layar)) ?? 0) + 120);
        }
        entryBaru = true;
      } else if (t == "M+") {
        final hargaTerpilihM = barangDipilih == null
            ? -1
            : (int.tryParse("${barangDipilih!["harga1"]}") ?? -1);
        int qtyPO;
        if (!entryBaru) {
          final angkaKetik = int.tryParse(_stripBacktick(layar)) ?? 1;
          qtyPO = (angkaKetik == hargaTerpilihM) ? 1 : angkaKetik;
        } else if (_qtyMPlus != null) {
          qtyPO = _qtyMPlus!.round();
        } else if (adaQtyHitung) {
          qtyPO = (qtyHitung.round() == hargaTerpilihM) ? 1 : qtyHitung.round();
        } else {
          qtyPO = 1;
        }
        final qtyAman = qtyPO <= 0 ? 1 : qtyPO;
        memori += double.tryParse(_stripBacktick(layar)) ?? 0;
        if (barangDipilih != null) {
          final hargaAwal = int.tryParse("${barangDipilih!["harga1"]}") ?? 0;
          final nilaiLayar = double.tryParse(_stripBacktick(layar)) ?? 0;
          int harga = hargaAwal;
          if (_hargaLayarDiubah) {
            if (opPending.isNotEmpty && akumulator > 0) {
              harga = akumulator.round();
            } else if (nilaiLayar > 0) {
              harga = nilaiLayar.round();
            }
          }
          final satuanBarang = "${barangDipilih!["satuan"] ?? ''}".trim();
          final jumlah = qtyAman * harga;
          final opLS = (barangDipilih!["opPecah"]?.toString() ?? 'x');
          final isiLS = double.tryParse("${barangDipilih!["isiSatuan"]}") ?? 0;
          final hargaVarianLS =
              double.tryParse("${barangDipilih!["hargaVarian"]}") ?? 0;
          final idxPoBaru = ref.read(poProvider).items.length;
          final it =
              parseInputCepat("$qtyAman x ${barangDipilih!["nama"]} $harga");
          if (it != null) {
            ref.read(poProvider.notifier).tambahItem(
                it.copyWith(satuan: satuanBarang.isEmpty ? 'pcs' : satuanBarang));
          }
          final idxStepBaru = steps.length;
          steps.add({
            "item":
                "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}",
            "rumus":
                "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}",
            "harga": harga,
            "qty": qtyAman,
            "jumlah": jumlah,
            "satuan": satuanBarang,
            "chain": >[],
            "opPecah": opLS,
          });
          if (hargaVarianLS > 0 && isiLS > 0) {
            _acuanDariLS['step-$idxStepBaru'] = {
              'hargaSatuan': hargaVarianLS,
              'angkaSatuan': isiLS,
              'op': opLS,
            };
            _acuanDariLS['po-$idxPoBaru'] = {
              'hargaSatuan': hargaVarianLS,
              'angkaSatuan': isiLS,
              'op': opLS,
            };
            _opPecah['step-$idxStepBaru-op'] = opLS;
            _opPecah['po-$idxPoBaru-op'] = opLS;
          }
          _poCtrls['$idxPoBaru-harga']?.text = '$harga';
          _poCtrls['$idxPoBaru-satuan']?.text = satuanBarang;
          _stepCtrls['$idxStepBaru-harga']?.text = '$harga';
          _stepCtrls['$idxStepBaru-satuan']?.text = satuanBarang;
        }
        _hargaLayarDiubah = false;
        _habisMPlus = true;
        layar = "0";
        entryBaru = true;
        adaQtyHitung = false;
      } else if (t == "M-") {
        if (_mrIndex >= 0 && _mrJumlahBaris() > 0) {
          final idx = _mrIndex.clamp(0, _mrJumlahBaris() - 1);
          final hapus = _mrBaris(idx);
          memori -= hapus['jumlah'] as double;
          if (steps.isNotEmpty && idx < steps.length) {
            steps.removeAt(idx);
            _geserStateBarisSetelahHapus('step', idx);
            _bangunStepCtrls();
          }
          final poItemsM = ref.read(poProvider).items;
          if (idx < poItemsM.length) {
            ref.read(poProvider.notifier).hapusItem(idx);
            _geserStateBarisSetelahHapus('po', idx);
            _disposeMapCtrls(_poCtrls);
          }
          if (_mrJumlahBaris() == 0) {
            _mrIndex = -1;
            layar = "0";
            ekspresi = "MR: semua baris sudah dihapus.";
            entryBaru = true;
          } else {
            if (_mrIndex >= _mrJumlahBaris()) _mrIndex = _mrJumlahBaris() - 1;
            final st = _mrBaris(_mrIndex);
            layar = formatHasil(st['jumlah'] as double);
            ekspresi = "MR ${_mrIndex + 1}/${_mrJumlahBaris()} • ${st['teks']}";
            entryBaru = true;
          }
          Future.microtask(() {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Baris MR dihapus.')));
            }
          });
        } else {
          memori -= double.tryParse(_stripBacktick(layar)) ?? 0;
          var pesanM = '';
          final poItemsM = ref.read(poProvider).items;
          if (poItemsM.isNotEmpty) {
            final lastIdx = poItemsM.length - 1;
            final namaHapus = poItemsM.last.namaBarang;
            ref.read(poProvider.notifier).hapusItem(lastIdx);
            _geserStateBarisSetelahHapus('po', lastIdx);
            _disposeMapCtrls(_poCtrls);
            pesanM = 'Baris PO "$namaHapus" dihapus. ';
          }
          if (steps.isNotEmpty) {
            final lastIdxStep = steps.length - 1;
            steps.removeLast();
            _geserStateBarisSetelahHapus('step', lastIdxStep);
            _bangunStepCtrls();
            pesanM += 'Step terakhir CEK dihapus.';
          }
          if (pesanM.isEmpty) pesanM = 'Tidak ada baris PO / step CEK.';
          layar = "0";
          entryBaru = true;
          final pesanFinal = pesanM;
          Future.microtask(() {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(pesanFinal)));
            }
          });
        }
      } else if (t == "MRT") {
        final totalStep = steps.fold<double>(
            0, (a, st) => a + (((st['jumlah'] as num?)?.toDouble() ?? 0)));
        _mrtTerbuka = !_mrtTerbuka;
        layar = formatHasil(totalStep);
        ekspresi = "MRT = total ${steps.length} step";
        entryBaru = true;
      } else if (t == "MR") {
        final nMR = _mrJumlahBaris();
        if (nMR == 0) {
          _mrIndex = -1;
          layar = "0";
          ekspresi = "MR: tidak ada baris M+.";
          entryBaru = true;
        } else {
          if (_mrIndex < 0) {
            _mrIndex = 0;
          } else {
            _mrIndex = (_mrIndex + 1) % nMR;
          }
          final bMR = _mrBaris(_mrIndex);
          layar = formatHasil(bMR['jumlah'] as double);
          ekspresi = "MR ${_mrIndex + 1}/$nMR • ${bMR['teks']}";
          entryBaru = true;
        }
      } else if (t == "MC") {
        final nPO = ref.read(poProvider).items.length;
        final nStep = steps.length;
        memori = 0;
        _mrIndex = -1;
        _mrtTerbuka = false;
        _tulisUlangPO([]);
        steps.clear();
        _stepTerpilih.clear();
        _poTerpilih.clear();
        _bersihkanSemuaStatePecah('step');
        _disposeMapCtrls(_stepCtrls);
        layar = "0";
        entryBaru = true;
        final pesanFinal =
            'MC: semua M+ dibersihkan ($nPO baris PO + $nStep step CEK).';
        Future.microtask(() {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(pesanFinal)));
          }
        });
      } else if (t == "MU") {
        final modal = double.tryParse(_stripBacktick(layar)) ?? 0;
        final jual = modal / (1 - 0.10);
        ekspresi = "MU 10% dari ${formatHasil(modal)}";
        layar = formatHasil(jual);
        entryBaru = true;
      } else if (t == "▶" || t == "⌫") {
        if (adaError) {
          layar = "0";
          adaError = false;
          entryBaru = true;
        } else if (!entryBaru) {
          _hargaLayarDiubah = true;
          if (layar.length > 1) {
            layar = _groupBacktick(_stripBacktick(layar)
                .substring(0, _stripBacktick(layar).length - 1));
            if (layar.isEmpty || layar == "-") layar = "0";
          } else {
            layar = "0";
          }
        }
      } else if (["+", "-", "x", "÷", "/"].contains(t)) {
        _inputOperator(t);
      } else if (t == "=") {
        if (modeAdd2 && opPending.isEmpty) {
          layar = formatHasil(_terapkanAdd2(_angkaLayar()));
        }
        _inputSamaDengan();
      } else if (t == "+/-") {
        if (adaError) return;
        _hargaLayarDiubah = true;
        if (layar.startsWith("-")) {
          layar = layar.substring(1);
        } else if (layar != "0") {
          layar = "-$layar";
        }
      } else if (t == "%") {
        _inputPersen();
      } else {
        _inputAngka(t);
      }
    });
  }

  void bukaFormTambahBarang({Map<String, dynamic>? barangEdit}) {
    _diFormTambahBarang = true;
    final edit = barangEdit != null;
    final kodeLama = edit ? '${barangEdit["kode"] ?? ''}' : '';
    if (edit) {
      final b = barangEdit;
      kodeCtrl.text = '${b["kode"] ?? ''}';
      namaCtrl.text = '${b["nama"] ?? ''}';
      final kat = '${b["kategori"] ?? ''}';
      if (kat.isNotEmpty && !listKategori.contains(kat)) {
        listKategori.add(kat);
      }
      kategoriPilih = kat.isNotEmpty ? kat : listKategori.first;
      unitCtrl.text = '${b["satuan"] ?? ''}';
      kategoriBaruCtrl.clear();
      final hargaListLama =
          (b["hargaList"] as List?)?.map((e) => '$e').toList();
      final satuanPerVarianLama = (b["satuanPerVarian"] as List?)
          ?.map((g) => (g as List).map((x) {
                final m = Map<String, dynamic>.from(x as Map);
                return SatuanItem(
                  satuan: '${m["satuan"] ?? ''}',
                  dasar: m["dasar"] == true,
                  qty: '${m["qty"] ?? ''}',
                  isi: '${m["isi"] ?? ''}',
                  op: '${m["op"] ?? 'x'}',
                  nominal: '${m["nominal"] ?? ''}',
                  satuanBaru: '${m["satuanBaru"] ?? ''}',
                );
              }).toList())
          .toList();
      final varianTeks = '${b["varian"] ?? ''}';
      final varianList = varianTeks
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final nVarian = varianList.isEmpty ? 1 : varianList.length;
      varianCtrls.clear();
      hargaCtrls.clear();
      satuanPerVarian = [];
      for (var gi = 0; gi < nVarian; gi++) {
        varianCtrls.add(TextEditingController(
            text: gi < varianList.length ? varianList[gi] : ''));
        final hargaGi = (hargaListLama != null && gi < hargaListLama.length)
            ? hargaListLama[gi]
            : (gi == 0 ? '${b["harga1"] ?? ''}' : '');
        hargaCtrls.add(TextEditingController(text: hargaGi));
        if (satuanPerVarianLama != null &&
            gi < satuanPerVarianLama.length &&
            satuanPerVarianLama[gi].isNotEmpty) {
          satuanPerVarian.add(satuanPerVarianLama[gi]);
        } else if (gi == 0) {
          final sl = (b["satuanList"] as List?) ?? [];
          satuanPerVarian.add(sl.isNotEmpty
              ? sl.map((x) {
                  final m = Map<String, dynamic>.from(x as Map);
                  return SatuanItem(
                    satuan: '${m["satuan"] ?? ''}',
                    dasar: m["dasar"] == true,
                    qty: '${m["qty"] ?? ''}',
                    isi: '${m["isi"] ?? ''}',
                    op: '${m["op"] ?? 'x'}',
                    nominal: '${m["nominal"] ?? ''}',
                    satuanBaru: '${m["satuanBaru"] ?? ''}',
                  );
                }).toList()
              : _satuanBaruKosong());
        } else {
          satuanPerVarian.add(_satuanBaruKosong());
        }
      }
      harga1Ctrl.text = hargaCtrls.first.text;
      satuanList = _satuanGabunganMap()
          .map((m) => SatuanItem(
                satuan: '${m["satuan"] ?? ''}',
                dasar: m["dasar"] == true,
                qty: '${m["qty"] ?? ''}',
                isi: '${m["isi"] ?? ''}',
                op: '${m["op"] ?? 'x'}',
                nominal: '${m["nominal"] ?? ''}',
                satuanBaru: '${m["satuanBaru"] ?? ''}',
              ))
          .toList();
    } else {
      kodeCtrl.clear();
      namaCtrl.clear();
      kategoriPilih = listKategori.first;
      unitCtrl.clear();
      harga1Ctrl.clear();
      kategoriBaruCtrl.clear();
      varianCtrls.clear();
      varianCtrls.add(TextEditingController());
      hargaCtrls.clear();
      hargaCtrls.add(TextEditingController());
      satuanPerVarian = [_satuanBaruKosong()];
      satuanList = [
        SatuanItem(
            satuan: "",
            dasar: true,
            qty: "",
            isi: "",
            op: "x",
            nominal: "",
            satuanBaru: "")
      ];
    }
    _satuanCtrlDialog = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 12,
                right: 12,
                top: 12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        edit ? "Edit Barang" : "Tambah Barang",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: kodeCtrl, decoration: dec("Code *"))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: namaCtrl,
                        decoration: dec("Name *"),
                        onChanged: (_) => setSheet(() {}),
                      ),
                    ),
                  ]),
                  _chipSaranForm(
                      _saranNamaBarang(namaCtrl.text)
                          .map((b) => '${b['nama']}')
                          .toList(),
                      namaCtrl,
                      setSheet),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Category • dropdown + tambah/delete",
                              style: TextStyle(fontSize: 11)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: kategoriPilih,
                            decoration: dec("Kategori"),
                            items: listKategori
                                .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e,
                                        style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setSheet(() => kategoriPilih = v);
                              }
                            },
                          ),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: kategoriBaruCtrl,
                                    decoration: dec("Kategori baru"))),
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
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unitCtrl,
                        decoration: dec("Unit (Biru - auto sama)"),
                        onChanged: (v) {
                          for (var g in satuanPerVarian) {
                            final dasar = g.firstWhere((x) => x.dasar == true,
                                orElse: () => g.first);
                            dasar.namaCtrl.text = v;
                          }
                          setSheet(() => refreshSemuaNominal());
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Varian",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton(
                        onPressed: () => setSheet(() {
                          varianCtrls.add(TextEditingController());
                          hargaCtrls.add(TextEditingController());
                          satuanPerVarian.add(_satuanBaruKosong());
                        }),
                        child: const Text("+Tambah Varian",
                            style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...varianCtrls.asMap().entries.map((ve) {
                    final gi = ve.key;
                    final grup = satuanPerVarian[gi];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.teal.shade200),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFF6FBF8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text("Varian ${gi + 1}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal)),
                            const Spacer(),
                            if (varianCtrls.length > 1)
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.red, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 26, minHeight: 26),
                                onPressed: () => setSheet(() {
                                  varianCtrls.removeAt(gi);
                                  hargaCtrls.removeAt(gi);
                                  satuanPerVarian.removeAt(gi);
                                }),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          TextField(
                            controller: ve.value,
                            decoration: dec("Varian"),
                            onChanged: (v) {
                              tambahKeDaftarSatuan(v);
                              setSheet(() {});
                            },
                          ),
                          _chipSaranForm(
                              _saranVarian(ve.value.text), ve.value, setSheet),
                          const SizedBox(height: 10),
                          Text("Harga ${gi + 1} • Acuan 100%",
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: hargaCtrls[gi],
                            keyboardType: TextInputType.number,
                            decoration: dec("0"),
                            onChanged: (v) => setSheet(() {
                              for (var x in grup) {
                                refreshNominal(x, hargaTeks: v);
                              }
                            }),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Satuan",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              ElevatedButton(
                                onPressed: () => setSheet(() {
                                  grup.add(SatuanItem(
                                      satuan: unitCtrl.text,
                                      dasar: false,
                                      qty: "1",
                                      isi: "1",
                                      op: "÷",
                                      nominal: "0",
                                      satuanBaru: ""));
                                }),
                                child: const Text("+Tambah Satuan",
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          const Text(
                            "Qty + satuan BIRU, x/÷, isi + unit HIJAU = nominal. Baris bawah (merah) = INFO dari Harga varian ini, bukan dari field Rp.",
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          ...grup.asMap().entries.map((e) {
                            final it = e.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.white,
                              ),
                              child: Column(children: [
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    _AutoField(
                                      controller: it.qtyCtrl,
                                      hint: "1",
                                      angka: true,
                                      min: 44,
                                      max: 70,
                                      onChanged: (_) => setSheet(() {
                                        it.nominalManual = false;
                                        refreshNominal(it,
                                            hargaTeks: hargaCtrls[gi].text);
                                      }),
                                    ),
                                    _AutoField(
                                      controller: it.namaCtrl,
                                      hint: "satuan",
                                      min: 52,
                                      max: 100,
                                      onTap: () => setSheet(
                                          () => _satuanCtrlDialog = it.namaCtrl),
                                      onChanged: (v) {
                                        if (it.dasar) unitCtrl.text = v;
                                        setSheet(() => refreshNominal(it,
                                            hargaTeks: hargaCtrls[gi].text));
                                      },
                                    ),
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: InkWell(
                                        onTap: () => setSheet(() {
                                          it.op = it.op == "x" ? "÷" : "x";
                                          it.nominalManual = false;
                                          refreshNominal(it,
                                              hargaTeks: hargaCtrls[gi].text);
                                        }),
                                        borderRadius: BorderRadius.circular(18),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: it.op == "÷"
                                                ? Colors.teal.shade100
                                                : Colors.orange.shade100,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.grey.shade400),
                                          ),
                                          child: Center(
                                            child: Text(
                                              it.op,
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _AutoField(
                                      controller: it.isiCtrl,
                                      hint: "isi",
                                      angka: true,
                                      min: 44,
                                      max: 70,
                                      onChanged: (_) => setSheet(() {
                                        it.nominalManual = false;
                                        refreshNominal(it,
                                            hargaTeks: hargaCtrls[gi].text);
                                      }),
                                    ),
                                    _AutoField(
                                      controller: it.satuanBaruCtrl,
                                      hint: "unit",
                                      min: 52,
                                      max: 100,
                                      onTap: () => setSheet(() =>
                                          _satuanCtrlDialog = it.satuanBaruCtrl),
                                      onChanged: (v) {
                                        tambahKeDaftarSatuan(v);
                                        setSheet(() => refreshNominal(it,
                                            hargaTeks: hargaCtrls[gi].text));
                                      },
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 30, minHeight: 30),
                                      tooltip:
                                          it.dasar ? "Dasar" : "Jadikan dasar",
                                      icon: Icon(
                                        it.dasar
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: it.dasar
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 22,
                                      ),
                                      onPressed: () => setSheet(() {
                                        for (var x in grup) {
                                          x.dasar = false;
                                        }
                                        it.dasar = true;
                                        syncUnitDariDasar(grup: gi);
                                        refreshSemuaNominal();
                                      }),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.red, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 36, minHeight: 36),
                                      tooltip: 'Hapus baris satuan',
                                      onPressed: () => setSheet(() {
                                        if (grup.length > 1) {
                                          grup.removeAt(e.key);
                                        } else {
                                          it.qtyCtrl.clear();
                                          it.namaCtrl.clear();
                                          it.isiCtrl.clear();
                                          it.satuanBaruCtrl.clear();
                                          it.nominalManual = false;
                                          refreshNominal(it,
                                              hargaTeks: hargaCtrls[gi].text);
                                        }
                                      }),
                                    ),
                                  ],
                                ),
                                if ((_satuanCtrlDialog == it.namaCtrl ||
                                        _satuanCtrlDialog ==
                                            it.satuanBaruCtrl) &&
                                    _satuanCtrlDialog != null)
                                  _chipSaranForm(
                                      _saranSatuan(_satuanCtrlDialog!.text),
                                      _satuanCtrlDialog!,
                                      setSheet),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: it.nominalCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: dec(
                                      "nominal - harga jual per unit hijau (boleh edit)",
                                      prefix: "Rp "),
                                  onTap: () => it.nominalManual = true,
                                  onChanged: (_) {
                                    it.nominalManual = true;
                                    setSheet(() {});
                                  },
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    "INFO: ${teksRumusSatuan(it, hargaTeks: hargaCtrls[gi].text)}",
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFB71C1C)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ]),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                      onPressed: () {
                        final varian = varianCtrls.map((c) => c.text).join(", ");
                        for (var c in varianCtrls) {
                          tambahKeDaftarSatuan(c.text);
                        }
                        for (var g in satuanPerVarian) {
                          for (var x in g) {
                            tambahKeDaftarSatuan(x.satuanBaruCtrl.text);
                          }
                        }
                        setState(() {
                          final hargaListSimpan = hargaCtrls
                              .map((c) =>
                                  c.text.replaceAll(RegExp(r'[^0-9]'), ''))
                              .toList();
                          final satuanPerVarianSimpan = satuanPerVarian
                              .asMap()
                              .entries
                              .map((e) {
                                final namaV = e.key < varianCtrls.length
                                    ? varianCtrls[e.key].text.trim()
                                    : '';
                                return e.value
                                    .where((x) =>
                                        x.namaCtrl.text.trim().isNotEmpty ||
                                        x.satuanBaruCtrl.text.trim().isNotEmpty)
                                    .map((x) => {...x.toMap(), 'varian': namaV})
                                    .toList();
                              })
                              .toList();
                          final gabunganSimpan =
                              satuanPerVarianSimpan.expand((g) => g).toList();
                          final barangBaru = {
                            "kode": kodeCtrl.text,
                            "nama": namaCtrl.text,
                            "kategori": kategoriPilih,
                            "harga1": hargaListSimpan.isEmpty
                                ? ''
                                : hargaListSimpan.first,
                            "hargaList": hargaListSimpan,
                            "satuan": unitCtrl.text,
                            "varian": varian,
                            "satuanList": gabunganSimpan,
                            "satuanPerVarian": satuanPerVarianSimpan,
                          };
                          harga1Ctrl.text =
                              hargaCtrls.isEmpty ? '' : hargaCtrls.first.text;
                          satuanList = gabunganSimpan
                              .map((m) => SatuanItem(
                                    satuan: '${m["satuan"] ?? ''}',
                                    dasar: m["dasar"] == true,
                                    qty: '${m["qty"] ?? ''}',
                                    isi: '${m["isi"] ?? ''}',
                                    op: '${m["op"] ?? 'x'}',
                                    nominal: '${m["nominal"] ?? ''}',
                                    satuanBaru: '${m["satuanBaru"] ?? ''}',
                                  ))
                              .toList();
                          if (edit) {
                            final idx = daftarBarang
                                .indexWhere((x) => x["kode"] == kodeLama);
                            if (idx >= 0) {
                              daftarBarang[idx] = barangBaru;
                            } else {
                              daftarBarang.add(barangBaru);
                            }
                            if (barangDipilih != null &&
                                barangDipilih!["kode"] == kodeLama) {
                              barangDipilih = {
                                "kode": kodeCtrl.text,
                                "nama": namaCtrl.text,
                                "kategori": kategoriPilih,
                                "harga1": hargaListSimpan.isEmpty
                                    ? ''
                                    : hargaListSimpan.first,
                              };
                            }
                          } else {
                            final idxSama = daftarBarang.indexWhere(
                                (x) => x["kode"] == kodeCtrl.text);
                            if (idxSama >= 0) {
                              daftarBarang[idxSama] = barangBaru;
                            } else {
                              daftarBarang.add(barangBaru);
                            }
                            barangDipilih = {
                              "kode": kodeCtrl.text,
                              "nama": namaCtrl.text,
                              "kategori": kategoriPilih,
                              "harga1": hargaListSimpan.isEmpty
                                  ? ''
                                  : hargaListSimpan.first,
                            };
                          }
                        });
                        _simpanSemuaKeDB();
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        edit ? "Update Barang" : "Simpan Barang",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        });
      },
    ).then((_) {
      _diFormTambahBarang = false;
      _satuanCtrlDialog = null;
    });
  }

  Widget tombol(String label, {Color? bg, Color? fg, bool besar = false}) {
    final isDown = tombolDitekan == label && tekanTombol;
    final baseColor = bg ?? Colors.white;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          onTapDown: (_) => setState(() {
            tombolDitekan = label;
            tekanTombol = true;
          }),
          onTapUp: (_) {
            setState(() => tekanTombol = false);
            pencet(label);
          },
          onTapCancel: () => setState(() => tekanTombol = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: double.infinity,
            transform: Matrix4.translationValues(0, isDown ? 2.5 : 0, 0),
            decoration: BoxDecoration(
              color: isDown ? baseColor.withValues(alpha: 0.85) : baseColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black26, width: 0.8),
              boxShadow: isDown
                  ? []
                  : [
                      const BoxShadow(
                          color: Color(0xFFB8A888),
                          offset: Offset(0, 4),
                          blurRadius: 0),
                      const BoxShadow(
                          color: Colors.white70,
                          offset: Offset(0, -1),
                          blurRadius: 0),
                    ],
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: besar ? 16 : 14,
                  fontWeight: FontWeight.w800,
                  color: fg ?? Colors.black,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerKalkulator = Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "BASKORO WINGCHUN",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
            GestureDetector(
              onTap: dialogBabe,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: const Text(
                  "BABE•INFO",
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFF3A2A1A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black54),
          ),
          child: Row(
            children: List.generate(
              5,
              (_) => Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  color: const Color(0xFF5A3D22),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFDDE8D0),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
          child: Column(children: [
            SizedBox(
              height: 16,
              width: double.infinity,
              child: DotMatrixText(
                text: _layarAtasCasio().isEmpty ? ' ' : _layarAtasCasio(),
                size: DotMatrixSize.small,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 26,
              child: Row(children: [
                Expanded(
                  child: Text(
                    teksAcuan(),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: DotMatrixText(
                      text: _layarBawahCasio(),
                      size: DotMatrixSize.nota,
                      color: adaError ? Colors.red : Colors.black,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 14,
              child: Row(children: [
                Expanded(
                  child: Text(
                    barangDipilih == null
                        ? "Pilih barang via LS"
                        : "${barangDipilih!["nama"]} • ${barangDipilih!["kategori"]}",
                    style: const TextStyle(fontSize: 9, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  teksSaran(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: warnaSaran()),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () => setState(() {
                modeHitung =
                    modeHitung == "PEMBULATAN" ? "ORIGINAL" : "PEMBULATAN";
              }),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text(
                      "5/4",
                      style:
                          TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      modeHitung,
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 28,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0, label: Text("0", style: TextStyle(fontSize: 9))),
                  ButtonSegment(
                      value: 2, label: Text("2", style: TextStyle(fontSize: 9))),
                  ButtonSegment(
                      value: 3, label: Text("3", style: TextStyle(fontSize: 9))),
                ],
                selected: {desimal},
                onSelectionChanged: (s) => setState(() => desimal = s.first),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 28,
              child: FilledButton(
                onPressed: _kirimWA,
                style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 10)),
                child: const Text("Kirim WA"),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: _tampilNota,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 9),
                  backgroundColor: Colors.white,
                ),
                child: const Text("Nota"),
              ),
            ),
          ),
        ]),
      ]),
    );
    return Scaffold(
      backgroundColor: const Color(0xFFE8E0C8),
      body: SafeArea(
        child: Column(children: [
          headerKalkulator,
          _panelForm(),
          if (poTerbuka) Expanded(child: _panelDaftarItemPO()),
          if (!poTerbuka) _stripTengah(),
          if (_mrtTerbuka) _stripMRT(),
          Expanded(child: _areaTombolBawah()),
        ]),
      ),
    );
  }
}

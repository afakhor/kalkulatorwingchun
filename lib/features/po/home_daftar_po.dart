import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import '../../core/po_database.dart';
import '../../core/formatter.dart';
import '../po/po_models.dart';
import '../nota/nota_pdf.dart';
import '../nota/nota_preview.dart';
import 'package:share_plus/share_plus.dart';
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
  // ===== PERSISTENSI: semua data tersimpan ke SQLite (sqflite) di lib/core/po_database.dart =====
  // LS barang, step CEK, PO aktif (PO Recent), PO tersimpan, pelanggan, alias CPS.
  // Tutup kalkulator / tutup aplikasi -> buka lagi -> data balik lagi.
  final PoDatabase _db = PoDatabase();
  Map<String, String> _aliasCopas = {}; // nama copasan (huruf kecil) -> kode barang LS
  Timer? _timerSimpanDB;
  @override
  void initState() {
    super.initState();
    _muatDariDB();
  }
  @override
  void dispose() {
    _timerSimpanDB?.cancel();
    _nomorWAC.dispose();
    super.dispose();
  }
  // setState dibungkus: tiap ada perubahan, jadwalkan simpan ke DB (debounce 500ms).
  // Jadi edit apapun (tambah barang, M+, edit baris, hapus) otomatis tersimpan, tanpa tombol simpan khusus.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _jadwalSimpanDB();
  }
  void _jadwalSimpanDB() {
    _timerSimpanDB?.cancel();
    _timerSimpanDB = Timer(const Duration(milliseconds: 500), () { if (mounted) { _simpanSemuaKeDB(); } });
  }
  // Simpan barang LS + step CEK + PO aktif (PO Recent) ke DB. PO aktif auto-tersimpan sebagai draf; tombol Simpan/Cek PO di panel PO sudah dihapus.
  Future<void> _simpanSemuaKeDB() async {
    try {
      await _db.simpanBarang(daftarBarang);
      await _db.simpanStepDraf(steps);
      final poItems = ref.read(poProvider).items;
      final poDraf = <Map<String, dynamic>>[];
      for (var i = 0; i < poItems.length; i++) {
        final it = poItems[i];
        poDraf.add({'nama': it.namaBarang, 'harga': it.hargaSatuan, 'qty': it.qty, 'jumlah': it.qty * it.hargaSatuan, 'satuan': _poCtrls['$i-satuan']?.text.trim() ?? '', 'step': _poCtrls['$i-step']?.text.trim() ?? ''});
      }
      await _db.simpanPoDraf(poDraf);
    } catch (_) {}
  }
  // Muat semua data dari DB saat kalkulator dibuka.
  Future<void> _muatDariDB() async {
    try {
      final barang = await _db.muatBarang();
      final poList = await _db.muatSemuaPo();
      final draf = await _db.muatStepDraf();
      final poDraf = await _db.muatPoDraf();
      final alias = await _db.muatAliasCopas();
      if (!mounted) return;
      setState(() {
        daftarBarang.clear();
        daftarBarang.addAll(barang.map((b) => Map<String, dynamic>.from(b)));
        _aliasCopas = alias;
        steps.clear();
        steps.addAll(draf.map((st) => {'item': st['item'], 'rumus': st['rumus'], 'harga': st['harga'], 'qty': st['qty'], 'jumlah': st['jumlah'], 'satuan': st['satuan'] ?? '', 'tipeHarga': 'SATUAN'}));
        _poTersimpan.clear();
        var maxNomor = 0;
        for (final p in poList) {
          final nomorStr = '${p['nomor'] ?? ''}';
          final nomorInt = int.tryParse(RegExp(r'(\d+)').firstMatch(nomorStr)?.group(1) ?? '') ?? 0;
          if (nomorInt > maxNomor) { maxNomor = nomorInt; }
          _poTersimpan.add({
            'nomorInt': nomorInt, 'nomor': nomorStr, 'pelanggan': p['pelanggan'] ?? '',
            'items': (p['items'] as List).map((e) => {'nama': e['namaBarang'] ?? '', 'harga': e['harga'], 'satuan': e['satuan'] ?? '', 'qty': e['qty'], 'step': e['rumus'] ?? '', 'jumlah': e['jumlah'], 'tipeHarga': 'SATUAN'}).toList(),
            'total': p['total'], 'dicek': (p['dicek'] ?? 0) == 1, 'nomorWA': p['nomorWA'] ?? '', 'dbId': p['id'],
          });
        }
        if (maxNomor >= _poNomor) { _poNomor = maxNomor + 1; }
        if (poDraf.isNotEmpty) {
          _tulisUlangPO(poDraf.map((e) => {'nama': e['nama'], 'qty': e['qty'], 'harga': e['harga'], 'satuan': e['satuan'] ?? '', 'step': e['step'] ?? '', 'jumlah': e['jumlah']}).toList());
          _poCtrls = {};
          for (var i = 0; i < poDraf.length; i++) {
            final e = poDraf[i];
            _poCtrls['$i-nama'] = TextEditingController(text: '${e['nama'] ?? ''}');
            _poCtrls['$i-harga'] = TextEditingController(text: '${(e['harga'] as num?)?.toInt() ?? 0}');
            _poCtrls['$i-satuan'] = TextEditingController(text: '${e['satuan'] ?? ''}');
            _poCtrls['$i-qty'] = TextEditingController(text: '${e['qty'] ?? 0}');
            _poCtrls['$i-step'] = TextEditingController(text: '${e['step'] ?? ''}');
          }
        }
      });
    } catch (_) {}
  }

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
  double? _qtyMPlus; // qty hitungan terakhir (=): operand yang BUKAN harga barang. Dipakai M+ biar qty tidak jadi hasil/jumlah (fix Qty 3750000.0).
  double memori = 0;
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

  // ===== STRIP TENGAH - dibuka LS/CEK/CPS/RIW/PO, kecuali form tambah barang =====
  bool _stripTengahTerbuka = true;
  String _tombolKuningAktif = ''; // panel form tertutup sampai tombol CEK/LS/RIW/CPS/PO ditekan
  final TextEditingController _cpsTempelC = TextEditingController();
  List<Map<String, dynamic>> _cpsBaris = []; // baris hasil urai CPS di panel
  // KEYBOARD BAWAH: 0 = Casio default, 1 = QWERTY BlackBerry (field teks), 2 = keypad angka (field angka), 3 = simbol karakter.
  // Form tambahBarang TIDAK ikut: field-nya tetap pakai keyboard HP seperti semula.
  int _modeKeyboard = 0;
  int _mrIndex = -1; // mode cek cepat MR: -1 = tidak cek, >=0 = index baris yang sedang didisplay
  bool _mrtTerbuka = false; // strip MRT total semua step terbuka
  TextEditingController? _ctrlKeyboard; // controller field form yang sedang diisi keyboard bawah
  int _qwertyCaps = 1; // 0 = huruf kecil, 1 = huruf besar 1x (Shift), 2 = huruf besar semua (Caps Lock, tap lama ⇧)
  final TextEditingController _lsCariC = TextEditingController();
  // ===== PO DAFTAR ITEM (BARU) =====
  int _poNomor = 1; // nomor PO auto iterasi, naik tiap PO baru disimpan
  bool _poRevisi = false; // true = lagi revisi PO tersimpan (simpan menimpa PO yang sama)
  bool _poDicek = false; // true = PO ini sudah dicek (icon cek)
  final TextEditingController _pelangganC = TextEditingController();
  final TextEditingController _nomorWAC = TextEditingController(); // nomor WA pelanggan di panel PO
  bool _sembunyiSaranPelanggan = false;
  final List<Map<String, dynamic>> _poTersimpan = []; // PO tersimpan: {nomorInt, nomor, pelanggan, items, total, dicek}
  Map<String, TextEditingController> _poCtrls = {}; // controller baris PO: "$i-nama", "$i-harga", "$i-satuan", "$i-qty", "$i-step"
  Map<String, TextEditingController> _stepCtrls = {}; // controller baris CEK/RIW: sama
  final Map<String, TextEditingController> _chainCtrls = {}; // controller angka Step rantai CEK: 'step-$i-chain-$j'
  Map<int, String> _tipeHargaPO = {}; // per baris PO: 'ACUAN' / 'SATUAN'
  Map<int, String> _tipeHargaStep = {}; // per baris step: 'ACUAN' / 'SATUAN'
  Set<int> _poTerpilih = {}; // baris PO yang dicek (checkbox)
  Set<int> _stepTerpilih = {}; // baris step yang dicek (checkbox)
  String? _tagKeyboardAktif; // tag field baris yang sedang diisi keyboard bawah, misal "po-2-qty"
  bool _diFormTambahBarang = false;
  void _onTapTombolKuning(String tombol) {
    if (_diFormTambahBarang) return; // flag dibalik false di .then() showModalBottomSheet bukaFormTambahBarang()
    setState(() { _stripTengahTerbuka = true; _tombolKuningAktif = (_tombolKuningAktif == tombol) ? '' : tombol; poTerbuka = false; _resetKeyboard(); }); // tombol kuning = tutup Daftar Item, tampilkan panelnya sendiri, jangan numpuk
  }
  Widget _tombolStripRapi(String label, Color bg, VoidCallback onTap) {
    final gelap = bg == Colors.black || bg == const Color(0xFF1F2A44) || bg == const Color(0xFF2D7DFF);
    return SizedBox(height: 36, child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: gelap ? Colors.white : Colors.black, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2, height: 1.0)))));
  }
  Widget _stripTengah() {
    if (!_stripTengahTerbuka) return const SizedBox.shrink();
    // STRIP ASAL: chip TAX+ sampai ADD2, 1 BARIS, geser kiri-kanan. Tanpa tulisan Mode / LS MODE. GT DIBUANG (tidak perlu, MR sudah cukup).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(color: Color(0xFFFAFAF5), border: Border(bottom: BorderSide(color: Color(0xFF2EBD5A), width: 3))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _tombolStripRapi('TAX+', Colors.teal, () => pencet('TAX+')),
            const SizedBox(width: 8),
            _tombolStripRapi('TAX-', Colors.teal, () => pencet('TAX-')),
            const SizedBox(width: 8),
            _tombolStripRapi('SET TAX', const Color(0xFF1F2A44), () => pencet('SET TAX')),
            const SizedBox(width: 8),
            _tombolStripRapi('COST', const Color(0xFF2D7DFF), () => pencet('COST')),
            const SizedBox(width: 8),
            _tombolStripRapi('SELL', const Color(0xFF2D7DFF), () => pencet('SELL')),
            const SizedBox(width: 8),
            _tombolStripRapi('MARGIN', const Color(0xFF2D7DFF), () => pencet('MARGIN')),
            const SizedBox(width: 8),
            _tombolStripRapi('CSM CLR', Colors.grey.shade300, () => pencet('CSM CLR')),
            const SizedBox(width: 8),
            _tombolStripRapi('ROUND: $modeRound', Colors.amber.shade100, () => pencet('ROUND')),
            const SizedBox(width: 8),
            _tombolStripRapi(modeAdd2 ? 'ADD2: ON' : 'ADD2: OFF', Colors.amber.shade100, () => pencet('ADD2')),
            const SizedBox(width: 8),
            _tombolStripRapi('✕', Colors.grey.shade300, () => setState(() { _stripTengahTerbuka = false; })),
          ],
        ),
      ),
    );
  }
  // ===== SISTEM M: M+ / M- / MR / MC / MRT (berlaku untuk PO + CEK, TIDAK untuk RIW) =====
  // RIW = log, bukan cek, jadi tidak ikut sistem M ini. Edit baris tetap lewat tombol hitam BSKR/WCUN.
  // Daftar yang dicek MR: step CEK kalau ada, kalau CEK kosong pakai baris PO.
  int _mrJumlahBaris() {
    if (steps.isNotEmpty) { return steps.length; }
    return ref.read(poProvider).items.length;
  }
  // 1 baris MR ke-i: {'jumlah': double, 'teks': String}. Dari step CEK kalau ada, kalau tidak dari baris PO.
  Map<String, dynamic> _mrBaris(int i) {
    if (steps.isNotEmpty) {
      final st = steps[i];
      return {'jumlah': ((st['jumlah'] as num?)?.toDouble() ?? 0), 'teks': '${st['rumus'] ?? st['item'] ?? ''}'};
    }
    final it = ref.read(poProvider).items[i];
    final jml = it.qty * it.hargaSatuan;
    return {'jumlah': jml, 'teks': '${it.namaBarang} : ${formatHasil(it.qty.toDouble())} x ${formatRupiah(it.hargaSatuan.toInt())} = ${formatRupiah(jml.toInt())}'};
  }
  // Strip MRT: total semua step + daftar step ditandai "step; ", 1 BARIS, cuma bisa geser kiri-kanan.
  // Step-nya tidak mengganggu layar kalkulator (tidak numpuk ke bawah, tidak nutupin keypad).
  Widget _stripMRT() {
    final totalStep = steps.fold<double>(0, (a, st) => a + (((st['jumlah'] as num?)?.toDouble() ?? 0)));
    final daftar = steps.map((st) => 'step; ${st['rumus'] ?? st['item'] ?? ''}').join('; ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(color: Color(0xFFFAFAF5), border: Border(top: BorderSide(color: Color(0xFF2D7DFF), width: 3), bottom: BorderSide(color: Color(0xFF2EBD5A), width: 3))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text('MRT TOTAL = ${formatHasil(totalStep)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          if (daftar.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text('|  $daftar', style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(width: 12),
          GestureDetector(onTap: () => setState(() { _mrtTerbuka = false; }), child: const Text('✕', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF888888)))),
        ]),
      ),
    );
  }

  // ===== PANEL FORM DI BAWAH LAYAR KALKULATOR (GARIS BIRU) =====
  // Isi panel ganti sesuai tombol kuning yang ditekan:
  // CEK -> form CEK, LS -> form LS, RIW -> form RIW, CPS -> form CPS, PO -> form PO.
  // Tap tombol yang sama 2x = tutup panel. Strip TAX+..ADD2 di bawah panel ini TIDAK ikut berubah.
  Widget _panelForm() {
    final mode = _tombolKuningAktif;
    if (mode.isEmpty) { return const SizedBox.shrink(); }
    const judul = {'CEK': 'CEK - Cek & Edit Step', 'LS': 'LS - List Barang', 'RIW': 'RIW - Riwayat Log Step', 'CPS': 'CPS - Copas Teks jadi Step', 'PO': 'PO - Cari PO Tersimpan'};
    Widget isi; double tinggi;
    if (mode == 'CEK') { isi = _panelCek(); tinggi = 250; }
    else if (mode == 'LS') { isi = _panelLS(); tinggi = 250; }
    else if (mode == 'RIW') { isi = _panelRiw(); tinggi = 250; }
    else if (mode == 'CPS') { isi = _panelCps(); tinggi = 290; }
    else { isi = _panelPO(); tinggi = 240; }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(color: Color(0xFFFAFAF5), border: Border(top: BorderSide(color: Color(0xFF2D7DFF), width: 3), bottom: BorderSide(color: Color(0xFF2EBD5A), width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(judul[mode] ?? mode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          GestureDetector(onTap: () => setState(() { _commitSemuaBarisStep(); _tombolKuningAktif = ''; _resetKeyboard(); }), child: const Padding(padding: EdgeInsets.all(4), child: Text('Tutup X', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF888888))))),
        ]),
        const SizedBox(height: 6),
        SizedBox(height: tinggi, child: isi),
      ]),
    );
  }

  // ===== FIELD & BARIS BARU: label di BORDER ATAS =====
  // Field dengan label di border atas (labelText). Tap field -> keyboard bawah (QWERTY teks / angka).
  Widget _fieldBorderAtas({required String label, required TextEditingController controller, bool angka = false, String? tag, bool padat = false}) {
    return TextField(controller: controller, readOnly: true, showCursor: true, keyboardType: angka ? TextInputType.number : TextInputType.text, onTap: () => _aktifkanField(controller, angka ? 2 : 1, tag: tag), decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: padat ? 5 : 8)));
  }

  // SATU BARIS: Nama Barang | Harga | Unit/Satuan | Qty | Jumlah. Label di BORDER ATAS tiap field.
  // CEK/RIW pakai rantai Step: Harga Acuan x Angka Unit [Ops Step]... M+. PO pakai layout lama (tampilChain false).
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
    // Rantai Step CEK: harga acuan | angka unit | ops | step | ops | step ... M+. PO tidak pakai.
    bool tampilChain = false,
    List<Map<String, dynamic>> chain = const [],
    List<TextEditingController> chainCtrls = const [],
    VoidCallback? onChainTambah,
    void Function(int j)? onChainOps,
    void Function(int j)? onChainHapus,
    VoidCallback? onMPlus,
  }) {
    final qty = double.tryParse(cQty.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final harga = double.tryParse(cHarga.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final chainHitung = <Map<String, dynamic>>[];
    for (var j = 0; j < chain.length; j++) {
      chainHitung.add({'ops': chain[j]['ops'], 'angka': double.tryParse(chainCtrls[j].text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0});
    }
    final jumlah = tampilChain ? _hitungChain(harga, qty, chainHitung) : qty * harga;
    final jumlahWidget = Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Jumlah', isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)), child: Text(formatRupiah(jumlah.toInt()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))));
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: dicek ? Colors.teal : Colors.grey.shade300, width: dicek ? 2 : 1), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 36, child: Checkbox(value: dicek, onChanged: (_) => onCek())),
          Expanded(child: _fieldBorderAtas(label: 'Nama Barang', controller: cNama, tag: '$tag-$index-nama')),
          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: onHapus),
          if (tombolExtra != null) tombolExtra,
        ]),
        if (tampilChain) ...[
          const SizedBox(height: 8),
          // Rantai: Harga Acuan x Angka Unit [Ops Step]... [+] [M+]
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 112, child: _fieldBorderAtas(label: 'Harga Acuan', controller: cHarga, angka: true, tag: '$tag-$index-harga')),
            const Text('x', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(width: 92, child: _fieldBorderAtas(label: 'Angka Unit', controller: cQty, angka: true, tag: '$tag-$index-qty')),
            for (var j = 0; j < chain.length; j++) ...[
              SizedBox(width: 46, child: OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () => onChainOps?.call(j), child: Text('${chain[j]['ops'] ?? 'x'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
              SizedBox(width: 92, child: _fieldBorderAtas(label: 'Step', controller: chainCtrls[j], angka: true, tag: '$tag-$index-chain-$j')),
              InkWell(onTap: () => onChainHapus?.call(j), child: const Icon(Icons.close, size: 18, color: Colors.red)),
            ],
            OutlinedButton(onPressed: onChainTambah, child: const Text('+')),
            if (onMPlus != null) ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: onMPlus, child: const Text('M+')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _fieldBorderAtas(label: 'Unit / Satuan', controller: cSatuan, tag: '$tag-$index-satuan')),
            const SizedBox(width: 8),
            jumlahWidget,
          ]),
        ] else ...[
          const SizedBox(height: 8),
          _fieldBorderAtas(label: 'Harga', controller: cHarga, angka: true, tag: '$tag-$index-harga'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _fieldBorderAtas(label: 'Unit / Satuan', controller: cSatuan, tag: '$tag-$index-satuan')),
            const SizedBox(width: 8),
            Expanded(child: _fieldBorderAtas(label: 'Qty', controller: cQty, angka: true, tag: '$tag-$index-qty')),
            const SizedBox(width: 8),
            jumlahWidget,
          ]),
        ],
      ]),
    );
  }

  // ===== BANTUAN PO / STEP =====
  String _nomorPO() { return 'PO B•WC-${_poNomor.toString().padLeft(3, '0')}B•I'; }
  String _namaDariStep(Map<String, dynamic> st) {
    final itemStr = '${st['item'] ?? ''}';
    if (itemStr.contains(' : ')) { return itemStr.split(' : ').first.trim(); }
    return itemStr;
  }
  List<String> _saranPelanggan() {
    final q = _pelangganC.text.trim().toLowerCase();
    final semua = <String>{};
    for (final p in _poTersimpan) { final nm = '${p['pelanggan'] ?? ''}'.trim(); if (nm.isNotEmpty) { semua.add(nm); } }
    final list = semua.toList();
    if (q.isEmpty) { return list; }
    return list.where((nm) => nm.toLowerCase().contains(q)).toList();
  }
  // Hitung rantai: Harga Acuan x Angka Unit, lalu tiap pasang (ops, step) berurutan.
  double _hitungChain(double harga, double qty, List<Map<String, dynamic>> chain) {
    var hasil = harga * qty;
    for (final pr in chain) {
      final ops = '${pr['ops'] ?? 'x'}';
      final angka = (pr['angka'] as num?)?.toDouble() ?? 0;
      if (ops == 'x') { hasil *= angka; }
      else if (ops == '÷') { if (angka != 0) { hasil /= angka; } }
      else if (ops == '+') { hasil += angka; }
      else if (ops == '-') { hasil -= angka; }
    }
    return hasil;
  }
  // Sinkron controller rantai dengan steps[i]['chain']: tambah yang baru, buang yang sudah tidak ada. Controller lama (edit jalan) dipertahankan.
  void _syncChainCtrls() {
    final kunciBaru = <String>{};
    for (var i = 0; i < steps.length; i++) {
      final chain = (steps[i]['chain'] as List?) ?? [];
      for (var j = 0; j < chain.length; j++) {
        final k = 'step-$i-chain-$j';
        kunciBaru.add(k);
        _chainCtrls.putIfAbsent(k, () => TextEditingController(text: '${((chain[j] as Map)['angka'] as num?)?.toDouble() ?? 0}'));
      }
    }
    _chainCtrls.removeWhere((k, _) => !kunciBaru.contains(k));
  }
  void _bangunStepCtrls() {
    _stepCtrls = {};
    _tipeHargaStep = {};
    for (var i = 0; i < steps.length; i++) {
      final st = steps[i];
      _stepCtrls['$i-nama'] = TextEditingController(text: _namaDariStep(st));
      _stepCtrls['$i-harga'] = TextEditingController(text: '${((st['harga'] as num?)?.toDouble() ?? 0).toInt()}');
      _stepCtrls['$i-satuan'] = TextEditingController(text: '${st['satuan'] ?? ''}');
      _stepCtrls['$i-qty'] = TextEditingController(text: '${((st['qty'] as num?)?.toDouble() ?? 0)}');
      _stepCtrls['$i-step'] = TextEditingController(text: '${st['rumus'] ?? st['item'] ?? ''}');
      _tipeHargaStep[i] = '${st['tipeHarga'] ?? 'SATUAN'}';
    }
  }
  void _commitBaris(String tag) {
    final parts = tag.split('-'); // 'po-2-qty' / 'step-1-nama'
    if (parts.length < 3) { return; }
    final idx = int.tryParse(parts[1]) ?? -1;
    if (idx < 0) { return; }
    if (parts[0] == 'po') { _commitSemuaBarisPO(); }
    else if (parts[0] == 'step') { _commitBarisStep(idx); }
  }
  void _commitBarisStep(int i) {
    if (i < 0 || i >= steps.length) { return; }
    final nama = _stepCtrls['$i-nama']?.text.trim() ?? '';
    final harga = double.tryParse((_stepCtrls['$i-harga']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final satuan = _stepCtrls['$i-satuan']?.text.trim() ?? '';
    final qty = double.tryParse((_stepCtrls['$i-qty']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    // Rantai Step: ops dari steps, angka dari controller rantai.
    final chainLama = (steps[i]['chain'] as List?) ?? [];
    final chainBaru = <Map<String, dynamic>>[];
    for (var j = 0; j < chainLama.length; j++) {
      final opsJ = '${(chainLama[j] as Map)['ops'] ?? 'x'}';
      final angkaJ = double.tryParse((_chainCtrls['step-$i-chain-$j']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      chainBaru.add({'ops': opsJ, 'angka': angkaJ});
    }
    final jumlah = _hitungChain(harga, qty, chainBaru);
    final tipe = _tipeHargaStep[i] ?? 'SATUAN';
    var rumus = '${formatRupiah(harga.toInt())} x ${formatHasil(qty)}';
    for (final pr in chainBaru) { rumus += " ${pr['ops']} ${formatHasil((pr['angka'] as num?)?.toDouble() ?? 0)}"; }
    rumus += ' = ${formatRupiah(jumlah.toInt())}';
    setState(() {
      steps[i] = {'item': '$nama : $rumus', 'rumus': rumus, 'harga': harga, 'qty': qty, 'jumlah': jumlah, 'satuan': satuan, 'tipeHarga': tipe, 'chain': chainBaru};
    });
  }
  void _commitSemuaBarisStep() { for (var i = 0; i < steps.length; i++) { _commitBarisStep(i); } }
  // Baca baris PO dari controller (teks user), bukan dari provider.
  List<Map<String, dynamic>> _bacaBarisPO() {
    final po = ref.read(poProvider);
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < po.items.length; i++) {
      final nama = _poCtrls['$i-nama']?.text.trim() ?? '';
      final harga = double.tryParse((_poCtrls['$i-harga']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      final satuan = _poCtrls['$i-satuan']?.text.trim() ?? '';
      final qty = double.tryParse((_poCtrls['$i-qty']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      final step = _poCtrls['$i-step']?.text.trim() ?? '';
      list.add({'nama': nama, 'harga': harga, 'satuan': satuan, 'qty': qty, 'step': step, 'jumlah': qty * harga, 'tipeHarga': _tipeHargaPO[i] ?? 'SATUAN'});
    }
    return list;
  }
  // Tulis ulang isi PO ke provider, urut dari depan supaya urutan baris tidak berubah.
  void _tulisUlangPO(List<Map<String, dynamic>> items) {
    final notif = ref.read(poProvider.notifier);
    while (ref.read(poProvider).items.isNotEmpty) { notif.hapusItem(0); }
    for (final m in items) {
      final nama = '${m['nama'] ?? ''}'.trim();
      final qty = ((m['qty'] as num?)?.toDouble() ?? 0);
      final harga = ((m['harga'] as num?)?.toDouble() ?? 0).toInt();
      if (nama.isEmpty && qty == 0 && harga == 0) { continue; } // baris kosong total, lewati
      final it = parseInputCepat('${qty.round()} x $nama $harga');
      if (it != null) { notif.tambahItem(it); }
    }
  }
  void _commitSemuaBarisPO() { _tulisUlangPO(_bacaBarisPO()); }
  // Simpan CEK jadi PO: masuk list PO tersimpan, PO aktif dikosongkan untuk PO baru.
  // ignore: unused_element
  Future<void> _simpanPO() async {
    final messenger = ScaffoldMessenger.of(context); // tangkap dulu, baru await, biar aman dari async gap
    _commitSemuaBarisPO();
    final data = _bacaBarisPO();
    if (data.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('PO kosong, isi dulu 1 baris.'))); return; }
    final pelanggan = _pelangganC.text.trim().isEmpty ? 'Tanpa Nama' : _pelangganC.text.trim();
    final nomorWA = _nomorWAC.text.trim();
    final total = data.fold<double>(0, (a, m) => a + ((m['jumlah'] as num?)?.toDouble() ?? 0));
    final nomorSimpan = _nomorPO();
    // PO -> DB (sqflite): 1 baris PO + item-nya. Simpan dulu ke DB biar dapat dbId.
    final itemsDB = data.map((m) => {'item': "${m['nama']} : ${formatHasil(((m['qty'] as num?)?.toDouble() ?? 0))} x ${formatRupiah(((m['harga'] as num?)?.toDouble() ?? 0).toInt())} = ${formatRupiah(((m['jumlah'] as num?)?.toDouble() ?? 0).toInt())}", 'rumus': m['step'] ?? '', 'namaBarang': m['nama'] ?? '', 'hargaAcuan': m['harga'], 'satuanAngka': 1, 'opSatuan': 'x', 'harga': m['harga'], 'qty': m['qty'], 'jumlah': m['jumlah'], 'satuan': m['satuan'] ?? ''}).toList();
    int? dbId;
    if (_poRevisi) {
      final idx = _poTersimpan.indexWhere((pp) => pp['nomorInt'] == _poNomor);
      dbId = idx >= 0 ? _poTersimpan[idx]['dbId'] as int? : null;
      if (dbId != null) {
        try { await _db.updatePo(id: dbId, tanggal: DateTime.now().toIso8601String(), pelanggan: pelanggan, nomorWA: nomorWA, dicek: _poDicek, total: total, items: itemsDB); } catch (_) {}
      }
    } else {
      try { dbId = await _db.simpanPoBaru(nomor: nomorSimpan, tanggal: DateTime.now().toIso8601String(), pelanggan: pelanggan, nomorWA: nomorWA, dicek: _poDicek, total: total, items: itemsDB); } catch (_) {}
    }
    try { await _db.simpanPelanggan(pelanggan); } catch (_) {}
    setState(() {
      if (_poRevisi) {
        final idx = _poTersimpan.indexWhere((pp) => pp['nomorInt'] == _poNomor);
        final isi = {'nomorInt': _poNomor, 'nomor': nomorSimpan, 'pelanggan': pelanggan, 'items': data, 'total': total, 'dicek': _poDicek, 'nomorWA': nomorWA, 'dbId': dbId};
        if (idx >= 0) { _poTersimpan[idx] = isi; } else { _poTersimpan.add(isi); }
      } else {
        _poTersimpan.add({'nomorInt': _poNomor, 'nomor': nomorSimpan, 'pelanggan': pelanggan, 'items': data, 'total': total, 'dicek': _poDicek, 'nomorWA': nomorWA, 'dbId': dbId});
        _poNomor++;
      }
      _tulisUlangPO([]);
      _poCtrls = {};
      _tipeHargaPO = {};
      _poTerpilih = {};
      _pelangganC.clear();
      _nomorWAC.clear();
      _poDicek = false;
      _poRevisi = false;
      _sembunyiSaranPelanggan = false;
      _resetKeyboard();
    });
    messenger.showSnackBar(SnackBar(content: Text('PO $nomorSimpan tersimpan untuk $pelanggan.')));
  }
  // Cek PO: tandai PO ini sudah dicek / lepas tanda cek.
  // ignore: unused_element
  void _cekPO() {
    _commitSemuaBarisPO();
    final data = _bacaBarisPO();
    final total = data.fold<double>(0, (a, m) => a + ((m['jumlah'] as num?)?.toDouble() ?? 0));
    setState(() { _poDicek = !_poDicek; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_poDicek ? 'PO dicek: ${data.length} baris, Total ${formatRupiah(total.toInt())}.' : 'Tanda cek PO dilepas.')));
  }
  // PO Baru: kosongkan PO aktif (PO tersimpan tidak ikut terhapus).
  // ignore: unused_element
  void _poBaru() {
    setState(() {
      _tulisUlangPO([]);
      _poCtrls = {};
      _tipeHargaPO = {};
      _poTerpilih = {};
      _pelangganC.clear();
      _nomorWAC.clear();
      _poDicek = false;
      _poRevisi = false;
      _sembunyiSaranPelanggan = false;
      _resetKeyboard();
    });
  }
  // Muat PO tersimpan ke panel PO untuk direvisi (simpan nanti menimpa PO yang sama).
  void _muatPO(Map<String, dynamic> p) {
    final items = (p['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    setState(() {
      _tulisUlangPO(items);
      _poCtrls = {};
      _tipeHargaPO = {};
      for (var i = 0; i < items.length; i++) {
        final m = items[i];
        _poCtrls['$i-nama'] = TextEditingController(text: '${m['nama'] ?? ''}');
        _poCtrls['$i-harga'] = TextEditingController(text: '${((m['harga'] as num?)?.toDouble() ?? 0).toInt()}');
        _poCtrls['$i-satuan'] = TextEditingController(text: '${m['satuan'] ?? ''}');
        _poCtrls['$i-qty'] = TextEditingController(text: '${((m['qty'] as num?)?.toDouble() ?? 0)}');
        _poCtrls['$i-step'] = TextEditingController(text: '${m['step'] ?? ''}');
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
  // Log RIW dipakai lagi ke PO: tambah sebagai item PO, lalu buka panel PO.
  void _logKePO(int i) {
    _commitBarisStep(i);
    final st = steps[i];
    final nama = _namaDariStep(st);
    final qty = ((st['qty'] as num?)?.toDouble() ?? 0).round();
    final harga = ((st['harga'] as num?)?.toDouble() ?? 0).toInt();
    final it = parseInputCepat('$qty x $nama $harga');
    if (it != null) { ref.read(poProvider.notifier).tambahItem(it); }
    setState(() { poTerbuka = true; _tombolKuningAktif = ''; _resetKeyboard(); });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Log "$nama" masuk ke PO.')));
  }

  // FORM CEK di panel: format baris BARU (label di border atas, checkbox, hapus).
  // Layout CEK LAMA dibuang: bar total hitam + field edit jumlah + SIMPAN.
  Widget _panelCek() {
    if (_stepCtrls.length != steps.length * 5) { _bangunStepCtrls(); }
    _syncChainCtrls();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Centang baris yang sudah dicek. Tap field untuk edit lewat keyboard bawah.', style: TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 6),
      if (steps.isEmpty) const Center(child: Text('Belum ada step. Pencet = dulu.')),
      if (steps.isNotEmpty) Expanded(child: ListView.builder(itemCount: steps.length, itemBuilder: (_, i) {
        final chainI = (steps[i]['chain'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        return _barisItem(
          index: i, tag: 'step',
          cNama: _stepCtrls['$i-nama']!, cHarga: _stepCtrls['$i-harga']!, cSatuan: _stepCtrls['$i-satuan']!, cQty: _stepCtrls['$i-qty']!,
          dicek: _stepTerpilih.contains(i),
          onCek: () => setState(() { if (_stepTerpilih.contains(i)) { _stepTerpilih.remove(i); } else { _stepTerpilih.add(i); } }),
          onHapus: () => setState(() { steps.removeAt(i); _stepTerpilih = {}; }),
          tampilChain: true,
          chain: chainI,
          chainCtrls: List.generate(chainI.length, (j) => _chainCtrls['step-$i-chain-$j']!),
          onChainTambah: () { _commitBarisStep(i); setState(() { (steps[i]['chain'] as List).add({'ops': 'x', 'angka': 0.0}); }); },
          onChainOps: (j) { setState(() { const opsList = ['x', '÷', '+', '-']; final cur = '${(steps[i]['chain'] as List)[j]['ops'] ?? 'x'}'; (steps[i]['chain'] as List)[j]['ops'] = opsList[(opsList.indexOf(cur) + 1) % opsList.length]; }); _commitBarisStep(i); },
          onChainHapus: (j) { _commitBarisStep(i); setState(() { (steps[i]['chain'] as List).removeAt(j); final ch = steps[i]['chain'] as List; for (var k = 0; k < ch.length; k++) { _chainCtrls['step-$i-chain-$k']?.text = '${((ch[k] as Map)['angka'] as num?)?.toDouble() ?? 0}'; } _chainCtrls.removeWhere((key, _) => key.startsWith('step-$i-chain-') && (int.tryParse(key.split('-').last) ?? -1) >= ch.length); }); },
          onMPlus: () => _logKePO(i),
        );
      })),
    ]);
  }

  // FORM LS di panel: cari + list barang + tap pilih + Tambah Barang.
  // Field cari = TEKS -> tap field, tombol bawah jadi keyboard QWERTY BlackBerry.
  Widget _panelLS() {
    final q = queryLS.toLowerCase();
    final filtered = daftarBarang.where((b) {
      if (q.isEmpty) { return true; }
      return b['nama'].toString().toLowerCase().contains(q) || b['kode'].toString().toLowerCase().contains(q) || b['kategori'].toString().toLowerCase().contains(q);
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: TextField(controller: _lsCariC, readOnly: true, showCursor: true, onTap: () => _aktifkanField(_lsCariC, 1), decoration: dec('Cari kode / nama / kategori...'), onChanged: (v) => setState(() { queryLS = v; }))),
        const SizedBox(width: 8),
        TextButton(onPressed: () { bukaFormTambahBarang(); }, child: const Text('+ Tambah Barang')),
      ]),
      const SizedBox(height: 8),
      if (filtered.isEmpty) const Center(child: Text('Belum ada barang. Tap + Tambah Barang.')),
      if (filtered.isNotEmpty) Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
        final b = filtered[i];
        final idxDaftar = daftarBarang.indexWhere((x) => x['kode'] == b['kode']);
        final aktif = barangDipilih != null && barangDipilih!['kode'] == b['kode'];
        final satuanBarang = (b['satuanList'] as List?) ?? [];
        return InkWell(
          // Tap DI LUAR chip putih (area hijau kartu) = pilih barang DASAR: harga1 + satuan dasar.
          onTap: () => setState(() { barangDipilih = {'kode': b['kode'].toString(), 'nama': b['nama'].toString(), 'kategori': b['kategori'].toString(), 'harga1': b['harga1'].toString(), 'satuan': (b['satuan'] ?? 'sak').toString()}; _qtyMPlus = null; adaQtyHitung = false; _tombolKuningAktif = ''; _resetKeyboard(); }),
          child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: aktif ? Colors.green.shade100 : Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [CircleAvatar(radius: 16, child: Text(b['nama'].toString().isEmpty ? '?' : b['nama'].toString()[0].toLowerCase(), style: const TextStyle(fontSize: 14))), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${b['nama']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), Text('${b['kode']} • ${b['kategori']} • ${b['satuan'] ?? 'sak'}', style: const TextStyle(fontSize: 11, color: Colors.grey))])), const SizedBox(width: 6),
              // Ikon EDIT: buka form Tambah Barang, isinya dari barang ini, simpan = update.
              IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.teal), tooltip: 'Edit barang', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () => bukaFormTambahBarang(barangEdit: b)),
              // Ikon HAPUS: hapus barang dari LS. Kalau barang ini sedang dipilih, lepas pilihannya.
              IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), tooltip: 'Hapus barang', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: () { if (idxDaftar >= 0) { setState(() { daftarBarang.removeAt(idxDaftar); if (barangDipilih != null && barangDipilih!['kode'] == b['kode']) { barangDipilih = null; } }); } }),
            ]),
              if (satuanBarang.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 4, children: satuanBarang.map<Widget>((x) { final m = Map<String, dynamic>.from(x as Map); final nom = double.tryParse(m['nominal'].toString()) ?? 0; final labelSatuan = (m['satuanBaru']?.toString().isNotEmpty == true) ? m['satuanBaru'].toString() : m['satuan'].toString(); return ActionChip(label: Text('$labelSatuan - ${formatRupiah(nom.toInt())}', style: const TextStyle(fontSize: 10)), onPressed: () => setState(() { barangDipilih = {'kode': b['kode'].toString(), 'nama': b['nama'].toString(), 'kategori': b['kategori'].toString(), 'harga1': nom.toInt().toString(), 'satuan': labelSatuan}; _qtyMPlus = null; adaQtyHitung = false; layar = nom.toStringAsFixed(0); entryBaru = true; _tombolKuningAktif = ''; _resetKeyboard(); })); /* tap chip PUTIH = pilih VARIAN yang ditap: nominal + satuan chip itu, harga chip tampil di layar */ }).toList())],
            ])),
        );
      })),
    ]);
  }

  // FORM RIW di panel: LOG, bukan PO. Format baris sama seperti PO.
  // Tiap baris bisa dipakai lagi ke PO (tombol → PO).
  Widget _panelRiw() {
    if (_stepCtrls.length != steps.length * 5) { _bangunStepCtrls(); }
    _syncChainCtrls();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Log hitung. Tap → PO untuk pakai lagi baris ini ke PO.', style: TextStyle(fontSize: 11, color: Colors.grey))),
        TextButton.icon(icon: const Icon(Icons.delete_sweep, size: 18), label: const Text('Hapus Semua'), onPressed: () => setState(() { steps.clear(); _stepTerpilih = {}; })),
      ]),
      const SizedBox(height: 6),
      if (steps.isEmpty) const Center(child: Text('Belum ada log step. Hitung / pencet = / M+ dulu.', textAlign: TextAlign.center)),
      if (steps.isNotEmpty) Expanded(child: ListView.builder(itemCount: steps.length, itemBuilder: (_, i) {
        final chainI = (steps[i]['chain'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        return _barisItem(
          index: i, tag: 'step',
          cNama: _stepCtrls['$i-nama']!, cHarga: _stepCtrls['$i-harga']!, cSatuan: _stepCtrls['$i-satuan']!, cQty: _stepCtrls['$i-qty']!,
          dicek: _stepTerpilih.contains(i),
          onCek: () => setState(() { if (_stepTerpilih.contains(i)) { _stepTerpilih.remove(i); } else { _stepTerpilih.add(i); } }),
          onHapus: () => setState(() { steps.removeAt(i); _stepTerpilih = {}; }),
          tombolExtra: Padding(padding: const EdgeInsets.only(left: 4), child: ElevatedButton(onPressed: () => _logKePO(i), child: const Text('→ PO'))),
          tampilChain: true,
          chain: chainI,
          chainCtrls: List.generate(chainI.length, (j) => _chainCtrls['step-$i-chain-$j']!),
          onChainTambah: () { _commitBarisStep(i); setState(() { (steps[i]['chain'] as List).add({'ops': 'x', 'angka': 0.0}); }); },
          onChainOps: (j) { setState(() { const opsList = ['x', '÷', '+', '-']; final cur = '${(steps[i]['chain'] as List)[j]['ops'] ?? 'x'}'; (steps[i]['chain'] as List)[j]['ops'] = opsList[(opsList.indexOf(cur) + 1) % opsList.length]; }); _commitBarisStep(i); },
          onChainHapus: (j) { _commitBarisStep(i); setState(() { (steps[i]['chain'] as List).removeAt(j); final ch = steps[i]['chain'] as List; for (var k = 0; k < ch.length; k++) { _chainCtrls['step-$i-chain-$k']?.text = '${((ch[k] as Map)['angka'] as num?)?.toDouble() ?? 0}'; } _chainCtrls.removeWhere((key, _) => key.startsWith('step-$i-chain-') && (int.tryParse(key.split('-').last) ?? -1) >= ch.length); }); },
        );
      })),
    ]);
  }

  // FORM CPS di panel: tempel teks, urai, masukkan ke CEK.
  // Field tempel = TEKS -> tap field, tombol bawah jadi keyboard QWERTY BlackBerry.
  Widget _panelCps() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('1 baris = 1 barang. Angka pertama = qty, angka kedua = harga.', style: TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 6),
      TextField(controller: _cpsTempelC, maxLines: 3, readOnly: true, showCursor: true, onTap: () => _aktifkanField(_cpsTempelC, 1), decoration: dec('Tempel di sini...')),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.paste, size: 18), label: const Text('Tempel Clipboard'), onPressed: () async { final d = await Clipboard.getData(Clipboard.kTextPlain); final t = d?.text ?? ''; if (t.isNotEmpty) { setState(() { _cpsTempelC.text = t; }); } })),
        const SizedBox(width: 8),
        Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.auto_fix_high, size: 18), label: const Text('Urai jadi Baris'), onPressed: () => setState(() { _cpsBaris = _cpsTempelC.text.split('\n').where((l) => l.trim().isNotEmpty).map((l) => _parseSatuCPS(l)).toList(); }))),
      ]),
      const SizedBox(height: 6),
      if (_cpsBaris.isEmpty) const Text('Belum ada baris. Tempel teks lalu pencet Urai jadi Baris.', textAlign: TextAlign.center),
      if (_cpsBaris.isNotEmpty) Expanded(child: ListView.builder(itemCount: _cpsBaris.length, itemBuilder: (_, i) {
        final r = _cpsBaris[i];
        final jumlah = ((r['qty'] as num?)?.toDouble() ?? 0) * ((r['harga'] as num?)?.toDouble() ?? 0);
        return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${r['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('Qty ${r['qty']} x ${formatRupiah(((r['harga'] as num?)?.toDouble() ?? 0).toInt())} = ${formatRupiah(jumlah.toInt())}', style: const TextStyle(fontSize: 12))])), IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => setState(() { _cpsBaris.removeAt(i); }))]));
      })),
      const SizedBox(height: 6),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.check, size: 18), label: Text('Masukkan ${_cpsBaris.length} Baris ke CEK'), onPressed: _cpsBaris.isEmpty ? null : () {
        for (final r in _cpsBaris) { final nama = '${r['nama']}'; final qty = (r['qty'] as num?)?.toDouble() ?? 0; final harga = (r['harga'] as num?)?.toDouble() ?? 0; final jumlah = qty * harga; steps.add({'item': '$nama : ${formatHasil(qty)} x ${formatRupiah(harga.toInt())} = ${formatRupiah(jumlah.toInt())}', 'rumus': '$nama : ${formatHasil(qty)} x ${formatRupiah(harga.toInt())} = ${formatRupiah(jumlah.toInt())}', 'harga': harga, 'qty': qty, 'jumlah': jumlah}); }
        final n = _cpsBaris.length;
        setState(() { _cpsBaris = []; _cpsTempelC.clear(); layar = formatHasil(totalCek); ekspresi = 'Total CEK = ${formatHasil(totalCek)}'; _tombolKuningAktif = 'CEK'; _resetKeyboard(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n baris masuk CEK.')));
      })),
    ]);
  }

  // FORM PO di panel: LIST PO TERSIMPAN. Tombol buka panel PO DIBUANG.
  // Per baris: ✎ edit (masuk panel PO) + 🗑 hapus.
  Widget _panelPO() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tap ✎ untuk revisi PO di panel PO. Tap 🗑 untuk hapus PO tersimpan.', style: TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.list_alt, size: 18), label: const Text('PO Recent (Daftar Item)'), onPressed: () => setState(() { poTerbuka = true; _tombolKuningAktif = ''; _resetKeyboard(); }))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.list_alt, size: 18), label: const Text('Lihat PO Aktif (Daftar Item)'), onPressed: () => setState(() { poTerbuka = true; _tombolKuningAktif = ''; _resetKeyboard(); }))),
      const SizedBox(height: 8),
      if (_poTersimpan.isEmpty) const Center(child: Text('Belum ada PO tersimpan.\nPO aktif tersimpan otomatis sebagai draf.', textAlign: TextAlign.center)),
      if (_poTersimpan.isNotEmpty) Expanded(child: ListView.builder(itemCount: _poTersimpan.length, itemBuilder: (_, i) {
        final pp = _poTersimpan[i];
        final items = (pp['items'] as List?) ?? [];
        return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${pp['nomor'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('Pelanggan: ${pp['pelanggan'] ?? ''}', style: const TextStyle(fontSize: 12)),
              if ('${pp['nomorWA'] ?? ''}'.isNotEmpty) Text('WA: ${pp['nomorWA']}', style: const TextStyle(fontSize: 12)),
              Text('${items.length} baris  •  Total ${formatRupiah(((pp['total'] as num?)?.toDouble() ?? 0).toInt())}${(pp['dicek'] == true) ? '  •  ✓ dicek' : ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
            IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.teal), tooltip: 'Edit, masuk panel PO', onPressed: () => _muatPO(pp)),
            IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), tooltip: 'Hapus PO tersimpan', onPressed: () async { final dbId = _poTersimpan[i]['dbId'] as int?; if (dbId != null) { try { await _db.hapusPo(dbId); } catch (_) {} } setState(() { _poTersimpan.removeAt(i); }); }),
          ]));
      })),
    ]);
  }

  // ===== PO - DAFTAR ITEM (panel bawah, background CERAH, bukan hitam) =====
  // Garis kuning = nomor PO auto. Garis putih = icon simpan CEK + cek PO. Garis hijau = nama pelanggan + saran.
  Widget _panelDaftarItemPO() {
    final po = ref.watch(poProvider);
    final n = po.items.length;
    if (_poCtrls.length != n * 5) {
      _poCtrls = {};
      for (var i = 0; i < n; i++) {
        final it = po.items[i];
        _poCtrls['$i-nama'] = TextEditingController(text: it.namaBarang);
        _poCtrls['$i-harga'] = TextEditingController(text: '${it.hargaSatuan.toInt()}');
        _poCtrls['$i-satuan'] = TextEditingController(text: '');
        _poCtrls['$i-qty'] = TextEditingController(text: '${it.qty}');
        _poCtrls['$i-step'] = TextEditingController(text: '${it.namaBarang} : ${it.qty} x ${formatRupiah(it.hargaSatuan.toInt())} = ${formatRupiah((it.qty * it.hargaSatuan).toInt())}');
      }
    }
    double total = 0;
    for (var i = 0; i < n; i++) {
      final qty = double.tryParse((_poCtrls['$i-qty']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      final harga = double.tryParse((_poCtrls['$i-harga']?.text ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      total += qty * harga;
    }
    final saran = _saranPelanggan();
    final tampilSaran = _ctrlKeyboard == _pelangganC && !_sembunyiSaranPelanggan && saran.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(color: Color(0xFFE0F7E9), border: Border(top: BorderSide(color: Color(0xFF2EBD5A), width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('PO - Daftar Item', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F5132))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Tutup PO, balik ke keypad', onPressed: () => setState(() { _commitSemuaBarisPO(); poTerbuka = false; _resetKeyboard(); })),
        ]),
        // Header PO SATU BARIS: No. PO | Nama Pelanggan | Nomor WA.
        // Tombol "Simpan CEK jadi PO" + "Cek PO" DIHAPUS (PO aktif auto-tersimpan sebagai draf lewat _simpanSemuaKeDB).
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.amber.shade200, borderRadius: BorderRadius.circular(16)), child: Text('No. PO: ${_nomorPO()}${_poRevisi ? ' (revisi)' : ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          if (_poDicek) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(16)), child: const Text('✓ Sudah dicek', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)))],
          const SizedBox(width: 8),
          Expanded(child: _fieldBorderAtas(label: 'Nama Pelanggan', padat: true, controller: _pelangganC)),
          const SizedBox(width: 8),
          Expanded(child: _fieldBorderAtas(label: 'Nomor WA (08...)', controller: _nomorWAC, angka: true, padat: true)),
        ]),
        if (tampilSaran) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: saran.map((nm) => ActionChip(label: Text(nm, style: const TextStyle(fontSize: 11)), onPressed: () => setState(() { _pelangganC.text = nm; _sembunyiSaranPelanggan = true; }))).toList()),
        ],
        const SizedBox(height: 4),
        Expanded(child: n == 0 ? const Center(child: Text('Belum ada item - pencet LS pilih barang, lalu ketik qty, lalu M+', textAlign: TextAlign.center)) : ListView.builder(itemCount: n, itemBuilder: (_, i) {
          return _barisItem(
            index: i, tag: 'po',
            cNama: _poCtrls['$i-nama']!, cHarga: _poCtrls['$i-harga']!, cSatuan: _poCtrls['$i-satuan']!, cQty: _poCtrls['$i-qty']!,
            dicek: _poTerpilih.contains(i),
            onCek: () => setState(() { if (_poTerpilih.contains(i)) { _poTerpilih.remove(i); } else { _poTerpilih.add(i); } }),
            onHapus: () => setState(() { ref.read(poProvider.notifier).hapusItem(i); _poTerpilih = {}; }),
          );
        })),
        const SizedBox(height: 4),
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF0F766E), borderRadius: BorderRadius.circular(8)),
          child: Text('Total Jumlah: ${formatRupiah(total.toInt())}  |  $n baris', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
      ]),
    );
  }

  // ===== NOTA: PO aktif -> PoOrder (buat preview + PDF kirim WA) =====
  PoOrder _poOrderAktif() {
    final po = ref.read(poProvider);
    final namaPelanggan = _pelangganC.text.trim().isEmpty ? 'Tanpa Nama' : _pelangganC.text.trim();
    final nomorWA = _nomorWAC.text.trim();
    final idPelanggan = nomorWA.isEmpty ? namaPelanggan : nomorWA;
    final items = po.items.map((it) => PoItem(namaBarang: it.namaBarang, qty: it.qty, hargaSatuan: it.hargaSatuan, diskonItem: 0)).toList();
    return PoOrder(
      id: _nomorPO(),
      tanggal: DateTime.now(),
      customer: Customer(id: idPelanggan, namaOrang: namaPelanggan, nomorWA: nomorWA),
      items: items,
      diskonTotal: 0,
      ongkir: 0,
      dp: 0,
      catatan: '',
      status: PoStatus.values.first,
    );
  }
  Future<void> _kirimWA() async {
    final messenger = ScaffoldMessenger.of(context);
    final po = _poOrderAktif();
    if (po.items.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('PO kosong, isi dulu 1 baris.'))); return; }
    try {
      final dir = Directory.systemTemp;
      final file = await buatPDFNota(po, dir);
      await Share.shareXFiles([XFile(file.path)], text: 'Nota ${po.id} - ${po.customer.namaOrang}');
    } catch (e) {
      if (!mounted) { return; }
      messenger.showSnackBar(SnackBar(content: Text('Gagal buat nota: $e')));
    }
  }
  void _tampilNota() {
    final po = _poOrderAktif();
    if (po.items.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PO kosong, isi dulu 1 baris.'))); return; }
    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 4), child: Row(children: [const Text('Preview Nota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))])),
        Flexible(child: SingleChildScrollView(child: NotaPreview(po: po))),
      ]),
    ));
  }

  // ===== KEYBOARD BAWAH: Casio / QWERTY BlackBerry / Angka / Simbol =====
  void _resetKeyboard() { _modeKeyboard = 0; _ctrlKeyboard = null; _qwertyCaps = 1; _tagKeyboardAktif = null; }
  void _aktifkanField(TextEditingController c, int mode, {String? tag}) {
    // Pindah field: commit dulu baris lama supaya edit tidak hilang.
    if (_tagKeyboardAktif != null && _tagKeyboardAktif != tag) { _commitBaris(_tagKeyboardAktif!); }
    setState(() { _ctrlKeyboard = c; _modeKeyboard = mode; _tagKeyboardAktif = tag; if (mode == 1) { _qwertyCaps = 1; } });
  }
  void _ketikKeyboard(String s) {
    final c = _ctrlKeyboard;
    if (c == null) { return; }
    final sel = c.selection;
    final text = c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final baru = text.replaceRange(start, end, s);
    c.value = c.value.copyWith(text: baru, selection: TextSelection.collapsed(offset: start + s.length));
    // Shift 1x: habis ketik 1 huruf, balik kecil lagi. Caps Lock (tap lama) tetap besar semua.
    setState(() { if (identical(c, _lsCariC)) { queryLS = baru; } if (identical(c, _pelangganC)) { _sembunyiSaranPelanggan = false; } if (_modeKeyboard == 1 && _qwertyCaps == 1) { _qwertyCaps = 0; } });
  }
  void _hapusKeyboard() {
    final c = _ctrlKeyboard;
    if (c == null) { return; }
    final sel = c.selection;
    final text = c.text;
    String baru; int pos;
    if (sel.isValid && sel.start != sel.end) { baru = text.replaceRange(sel.start, sel.end, ''); pos = sel.start; }
    else if (sel.isValid && sel.start > 0) { baru = text.replaceRange(sel.start - 1, sel.start, ''); pos = sel.start - 1; }
    else if (text.isNotEmpty) { baru = text.substring(0, text.length - 1); pos = baru.length; }
    else { return; }
    c.value = c.value.copyWith(text: baru, selection: TextSelection.collapsed(offset: pos));
    setState(() { if (identical(c, _lsCariC)) { queryLS = baru; } if (identical(c, _pelangganC)) { _sembunyiSaranPelanggan = false; } });
  }
  // Huruf sesuai mode Caps: 0 = kecil, 1/2 = besar.
  String _huruf(String k) { return _qwertyCaps == 0 ? k.toLowerCase() : k.toUpperCase(); }
  Widget _tombolKeyboard(String label, {int flex = 1, Color? bg, Color? fg, VoidCallback? onTap, VoidCallback? onLongPress}) {
    return Expanded(flex: flex, child: Padding(padding: const EdgeInsets.all(3),
      child: GestureDetector(onTap: onTap, onLongPress: onLongPress,
        child: Container(height: 48, decoration: BoxDecoration(color: bg ?? Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black26), boxShadow: const [BoxShadow(color: Color(0xFFB8A888), offset: Offset(0, 3), blurRadius: 0)]),
          child: Center(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg ?? Colors.black)))))));
  }
  // Tombol BSKRO / garis / WCUN di keypad (ganti tombol CEK, tombol hitam).
  // CANGKANG SAMA PERSIS dengan tombol(): Padding 4.0, tinggi double.infinity (mengisi penuh tinggi baris),
  // radius 14, border 0.8, shadow sama. Bedanya cuma isi (BSKRO/garis/WCUN) + warna hitam.
  // Font 11 biar teksnya mengisi tombol, tetap aman karena FittedBox scaleDown = kalau kebesaran, otomatis mengecil sampai muat. ClipRRect = teks tidak bisa keluar tombol.
  // Tap: SELALU buka panel CEK. Balik ke QWERTY bukan tugas tombol ini, tapi baris biru BASKORO WINGCHUN di bawah keypad.
  void _onTapBaskoroKeypad() {
    _onTapTombolKuning('CEK');
  }
  Widget _tombolBaskoroKeypad() {
    return Expanded(child: Padding(padding: const EdgeInsets.all(4.0),
      child: GestureDetector(onTap: _onTapBaskoroKeypad,
        child: Container(height: double.infinity, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black26, width: 0.8),
            boxShadow: const [BoxShadow(color: Color(0xFFB8A888), offset: Offset(0, 4), blurRadius: 0), BoxShadow(color: Colors.white70, offset: Offset(0, -1), blurRadius: 0)],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(14),
            child: FittedBox(fit: BoxFit.scaleDown,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('BSKRO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1, letterSpacing: 0.3)),
                Container(width: 30, height: 1.5, color: Colors.white, margin: const EdgeInsets.symmetric(vertical: 3)),
                const Text('WCUN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1, letterSpacing: 0.3)),
              ])))))));
  }

  // Tombol BSKRO / garis / WCUN di keyboard QWERTY / simbol / angka (tombol biru pojok kanan bawah).
  // Cangkang SAMA dengan _tombolKeyboard: Padding 3, tinggi 48, radius 12, shadow sama. Bedanya cuma isi + warna biru.
  Widget _tombolBaskoro(VoidCallback onTap) {
    return Expanded(child: Padding(padding: const EdgeInsets.all(3),
      child: GestureDetector(onTap: onTap,
        child: Container(height: 48, decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black26), boxShadow: const [BoxShadow(color: Color(0xFFB8A888), offset: Offset(0, 3), blurRadius: 0)]),
          child: ClipRRect(borderRadius: BorderRadius.circular(12),
            child: FittedBox(fit: BoxFit.scaleDown,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('BSKRO', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                Container(width: 26, height: 1.5, color: Colors.white, margin: const EdgeInsets.symmetric(vertical: 2)),
                const Text('WCUN', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
              ])))))));
  }
  // Baris BASKORO WINGCHUN di bawah keypad kalkulator: muncul kalau lagi isi field (habis toggle dari QWERTY).
  // Tap baris ini = balik ke QWERTY di field yang sama. FittedBox = teks mengecil sendiri kalau layar sempit.
  Widget _barisBaskoro() {
    return Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: GestureDetector(onTap: () => setState(() { _modeKeyboard = 1; }),
        child: Container(height: 44, decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black26)),
          child: const Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text('BASKORO•WINGCHUN', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)))))));
  }
  Widget _barisQwerty(List<String> keys) {
    return Expanded(child: Row(children: [for (final k in keys) _tombolKeyboard(_huruf(k), onTap: () => _ketikKeyboard(_huruf(k)))]));
  }
  // Keyboard QWERTY ala BlackBerry: QWERTYUIOP / ASDFGHJKL / ⇧ ZXCVBNM ⌫ / 123 Spasi . ⏎ BASKORO WINGCHUN
  // ⇧: tap = besar 1x lalu balik kecil, tap lagi = kecil. Tap lama ⇧ = besar semua (Caps Lock, ikon jadi ⇪).
  Widget _keyboardQwerty() {
    return Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), child: Column(children: [
      _barisQwerty(['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P']),
      _barisQwerty(['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L']),
      Expanded(child: Row(children: [
        _tombolKeyboard(_qwertyCaps == 2 ? '⇪' : '⇧',
          bg: _qwertyCaps == 0 ? Colors.grey.shade300 : (_qwertyCaps == 1 ? Colors.blue.shade200 : Colors.blue),
          fg: _qwertyCaps == 2 ? Colors.white : Colors.black,
          onTap: () => setState(() { if (_qwertyCaps == 2) { _qwertyCaps = 0; } else { _qwertyCaps = _qwertyCaps == 0 ? 1 : 0; } }),
          onLongPress: () => setState(() { _qwertyCaps = 2; })),
        for (final k in ['Z', 'X', 'C', 'V', 'B', 'N', 'M']) _tombolKeyboard(_huruf(k), onTap: () => _ketikKeyboard(_huruf(k))),
        _tombolKeyboard('⌫', bg: Colors.grey.shade300, onTap: _hapusKeyboard),
      ])),
      Expanded(child: Row(children: [
        _tombolKeyboard('123', bg: Colors.grey.shade300, onTap: () => setState(() { _modeKeyboard = 3; })),
        _tombolKeyboard('Spasi', flex: 3, onTap: () => _ketikKeyboard(' ')),
        _tombolKeyboard('.', onTap: () => _ketikKeyboard('.')),
        _tombolKeyboard('⏎', onTap: () => _ketikKeyboard('\n')),
        _tombolBaskoro(() => setState(() { _modeKeyboard = 0; })),
      ])),
    ]));
  }
  // Keyboard SIMBOL karakter: !@#$%^&*() / -_=+/?:;'" / .,<>[]{} + ⌫ / 123 Spasi . ⏎ BASKORO WINGCHUN
  // Tombol 123 muter: QWERTY -> simbol -> angka -> QWERTY (ABC di angka balik ke QWERTY).
  Widget _keyboardSimbol() {
    return Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), child: Column(children: [
      Expanded(child: Row(children: [for (final k in ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')']) _tombolKeyboard(k, onTap: () => _ketikKeyboard(k))])),
      Expanded(child: Row(children: [for (final k in ['-', '_', '=', '+', '/', '?', ':', ';', "'", '"']) _tombolKeyboard(k, onTap: () => _ketikKeyboard(k))])),
      Expanded(child: Row(children: [
        for (final k in ['.', ',', '<', '>', '[', ']', '{', '}']) _tombolKeyboard(k, onTap: () => _ketikKeyboard(k)),
        _tombolKeyboard('⌫', bg: Colors.grey.shade300, onTap: _hapusKeyboard),
      ])),
      Expanded(child: Row(children: [
        _tombolKeyboard('123', bg: Colors.grey.shade300, onTap: () => setState(() { _modeKeyboard = 2; })),
        _tombolKeyboard('Spasi', flex: 3, onTap: () => _ketikKeyboard(' ')),
        _tombolKeyboard('.', onTap: () => _ketikKeyboard('.')),
        _tombolKeyboard('⏎', onTap: () => _ketikKeyboard('\n')),
        _tombolBaskoro(() => setState(() { _modeKeyboard = 0; })),
      ])),
    ]));
  }
  // Keypad angka untuk field angka di form (misal edit jumlah CEK): angka + titik + minus + hapus.
  Widget _keyboardAngka() {
    return Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), child: Column(children: [
      for (final baris in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
        Expanded(child: Row(children: [for (final k in baris) _tombolKeyboard(k, onTap: () => _ketikKeyboard(k))])),
      Expanded(child: Row(children: [
        _tombolKeyboard('−', onTap: () => _ketikKeyboard('-')),
        _tombolKeyboard('0', onTap: () => _ketikKeyboard('0')),
        _tombolKeyboard('⌫', bg: Colors.grey.shade300, onTap: _hapusKeyboard),
      ])),
      Expanded(child: Row(children: [
        _tombolKeyboard('ABC', bg: Colors.grey.shade300, onTap: () => setState(() { _modeKeyboard = 1; })),
        _tombolKeyboard('.', onTap: () => _ketikKeyboard('.')),
        _tombolBaskoro(() => setState(() { _modeKeyboard = 0; })),
      ])),
    ]));
  }
  // Area tombol bawah: Casio default, atau QWERTY / Angka / Simbol kalau lagi isi field form.
  Widget _areaTombolBawah() {
    if (_modeKeyboard == 1) { return _keyboardQwerty(); }
    if (_modeKeyboard == 2) { return _keyboardAngka(); }
    if (_modeKeyboard == 3) { return _keyboardSimbol(); }
    return Column(children: [
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(10, 18, 10, 10), child: Column(children: [
        Expanded(child: Row(children: [tombol('AC', bg: Colors.blue.shade400, fg: Colors.white), tombol('MRT', bg: Colors.grey.shade400), tombol('M-', bg: Colors.grey.shade400), tombol('M+', bg: Colors.green, fg: Colors.white, besar: true), tombol('LS', bg: Colors.orange.shade100, besar: true), _tombolBaskoroKeypad(), tombol('CPS', bg: Colors.amber, fg: Colors.black), tombol('BEP', bg: Colors.pink, fg: Colors.white)])),
        Expanded(child: Row(children: [tombol('OFF', bg: Colors.blue.shade400, fg: Colors.white), tombol('7'), tombol('8'), tombol('9'), tombol('RIW', bg: Colors.grey.shade300), tombol('MU', bg: Colors.grey.shade300), tombol('MC', bg: Colors.grey.shade300)])),
        Expanded(child: Row(children: [tombol('%', bg: Colors.grey.shade300), tombol('4'), tombol('5'), tombol('6'), tombol('-', bg: Colors.grey.shade300), tombol('÷', bg: Colors.grey.shade300), tombol('MR', bg: Colors.grey.shade300)])),
        Expanded(child: Row(children: [tombol('+/-', bg: Colors.grey.shade300), tombol('1'), tombol('2'), tombol('3'), tombol('+', bg: Colors.grey.shade300), tombol('x', bg: Colors.grey.shade300), tombol('PO', bg: Colors.teal, fg: Colors.white)])),
        Expanded(child: Row(children: [tombol('ON/C', bg: Colors.blue.shade400, fg: Colors.white), tombol('0'), tombol('00'), tombol('.'), tombol('=', bg: Colors.blue, fg: Colors.white, besar: true), tombol('M+', bg: Colors.green, fg: Colors.white), tombol('⌫', bg: Colors.grey.shade300)])),
      ]))),
      // Habis toggle BASKORO WINGCHUN dari QWERTY ke kalkulator, baris ini yang balikin ke QWERTY.
      if (_ctrlKeyboard != null) _barisBaskoro(),
    ]);
  }
  Map<String, dynamic> _parseSatuCPS(String mentah) {
    final teks = mentah.replaceAll('`', '').replaceAll(RegExp(r'[Rr][Pp]'), '');
    final nums = RegExp(r'[0-9]+(?:[.,][0-9]+)?').allMatches(teks).map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0).toList();
    var nama = teks.replaceAll(RegExp(r'[0-9]+(?:[.,][0-9]+)?'), ' ');
    nama = nama.replaceAll(RegExp(r'[xX]'), ' ');
    nama = nama.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ');
    nama = nama.replaceAll(RegExp(r' +'), ' ').trim();
    if (nama.isEmpty) nama = 'Barang';
    double qty = 1;
    double harga = 0;
    if (nums.length >= 2) { qty = nums[0]; harga = nums[1]; }
    else if (nums.length == 1 && nums[0] > 1000) { qty = 1; harga = nums[0]; }
    else if (nums.length == 1) { qty = nums[0]; }
    // Alias CPS: nama copasan yang pernah dicocokkan ke barang LS -> pakai harga barang itu (kalau harga di teks kosong).
    // Nama copasan yang persis sama dengan nama barang LS -> pelajari aliasnya, simpan ke DB.
    final kunci = nama.toLowerCase();
    Map<String, dynamic>? barangAlias;
    if (_aliasCopas.containsKey(kunci)) {
      final kode = _aliasCopas[kunci]!;
      for (final b in daftarBarang) { if ('${b['kode']}'.toLowerCase() == kode.toLowerCase()) { barangAlias = b; break; } }
    }
    if (barangAlias == null) {
      for (final b in daftarBarang) { if ('${b['nama']}'.toLowerCase() == kunci) { barangAlias = b; _aliasCopas[kunci] = '${b['kode']}'; _db.simpanAliasCopas(namaCopas: kunci, kodeBarang: '${b['kode']}'); break; } }
    }
    if (harga == 0) {
      if (barangAlias != null) { harga = double.tryParse('${barangAlias['harga1']}') ?? 0; }
      if (harga == 0) { harga = hargaAcuan; }
    }
    return {'nama': nama, 'qty': qty, 'harga': harga};
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
  String _stripBacktick(String s) => s.replaceAll('`', '').replaceAll('Rp', '').replaceAll(' ', '').replaceAll(',', '').trim();
  double _parseLayar() => double.tryParse(_stripBacktick(layar)) ?? 0;
  // misal ribuan `000: 1000->1`000, 20000->20`000, 1000000->1`000`000, 83333->83`333
  // FIX: grouping dari kanan, bukan kiri. Sesuai display Casio DJ-120 di foto
  String _groupBacktick(String s) {
    if (s == "E" || s.isEmpty) return s;
    var neg = false;
    if (s.startsWith('-')) { neg = true; s = s.substring(1); }
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
  String formatHasil(double v) {
    if (v.isNaN || v.isInfinite) return "E";
    String mentah;
    if (modeHitung == "ORIGINAL") { mentah = v.toStringAsFixed(desimal); }
    else if (modeRound == "CUT") { final p = desimal == 0 ? 1.0 : _pow10(desimal); final potong = (v * p).truncate() / p; mentah = desimal == 0 ? potong.round().toString() : potong.toStringAsFixed(desimal); }
    else if (modeRound == "F") { mentah = _buangNolBelakang(v.toStringAsFixed(6)); }
    else if (desimal == 0) { mentah = v.round().toString(); }
    else { mentah = v.toStringAsFixed(desimal); }
    return _groupBacktick(mentah);
  }
  double _pow10(int n) { double r = 1; for (int i = 0; i < n; i++) { r *= 10; } return r; }
  String _buangNolBelakang(String s) { if (!s.contains('.')) { return s; } while (s.endsWith('0')) { s = s.substring(0, s.length - 1); } if (s.endsWith('.')) { s = s.substring(0, s.length - 1); } return s.isEmpty ? "0" : s; }
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
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("BABE•INFO - Dialog Uni"),
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
    // CEK step: Nama Barang = nama barang terpilih (bukan step) kalau ada barang.
    // Harga Acuan = operand yang = harga barang (kalau ada), Angka Unit = operand satunya.
    // Qty M+ = Angka Unit, bukan hasil / angka sebelum operator.
    final hargaB = barangDipilih == null ? -1.0 : (double.tryParse('${barangDipilih!["harga1"]}') ?? -1);
    final hargaStep = (hargaB >= 0 && b == hargaB) ? b : (hargaB >= 0 && a == hargaB) ? a : a;
    final qtyStep = (hargaB >= 0 && b == hargaB) ? a : (hargaB >= 0 && a == hargaB) ? b : b;
    _qtyMPlus = qtyStep;
    final namaB = barangDipilih == null ? '' : '${barangDipilih!["nama"]} : ';
    steps.add({"item": "$namaB$ekspresi", "rumus": ekspresi, "harga": hargaStep, "qty": qtyStep, "jumlah": h, "chain": <Map<String, dynamic>>[]});
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
  void _pencetTaxPlus() { final v = _angkaLayar(); final pajak = v * tarifPajak / 100; layar = formatHasil(v + pajak); ekspresi = "${formatHasil(v)} TAX+ $tarifPajak% = ${formatHasil(v + pajak)}"; steps.add({"item": ekspresi, "rumus": ekspresi, "harga": v, "qty": tarifPajak, "jumlah": v + pajak}); entryBaru = true; }
  void _pencetTaxMin() { final v = _angkaLayar(); final bersih = v / (1 + tarifPajak / 100); layar = formatHasil(bersih); ekspresi = "${formatHasil(v)} TAX- $tarifPajak% = ${formatHasil(bersih)}"; steps.add({"item": ekspresi, "rumus": ekspresi, "harga": v, "qty": tarifPajak, "jumlah": bersih}); entryBaru = true; }
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
  // ignore: unused_element
  void _editStepCek(int i, double jumlahBaru) { if (i < 0 || i >= steps.length) return; steps[i]["jumlah"] = jumlahBaru; steps[i]["rumus"] = "${steps[i]["rumus"]} -> ${formatHasil(jumlahBaru)}"; layar = formatHasil(totalCek); ekspresi = "CEK total = ${formatHasil(totalCek)}"; }
  // ignore: unused_element
  void _hapusStepCek(int i) { if (i < 0 || i >= steps.length) return; steps.removeAt(i); layar = formatHasil(totalCek); ekspresi = "CEK total = ${formatHasil(totalCek)}"; }

  void pencet(String t) {
    // Keluar mode cek MR kalau pencet tombol lain (selain MR / M- / MC / MRT). Mode MR cuma buat cek cepat per baris.
    if (_mrIndex >= 0 && t != 'MR' && t != 'M-' && t != 'MC' && t != 'MRT') { _mrIndex = -1; }
    HapticFeedback.lightImpact();
    setState(() {
      if (t == "AC") {
        // Casio AC: hapus SEMUA - layar, akumulator, operator, ekspresi, error
        layar = "0"; ekspresi = ""; akumulator = 0; angka1 = 0; opPending = ""; op = ""; entryBaru = true; adaError = false; lastOp = ""; lastAngka2 = 0; adaQtyHitung = false; qtyHitung = 1; _qtyMPlus = null;
      }
      else if (t == "ON/C") {
        // Casio ON/C: hapus entry saja, akumulator + operator tetap
        layar = "0"; entryBaru = true; adaError = false;
      }
      else if (t == "OFF") { layar = "0"; ekspresi = ""; entryBaru = true; }
      else if (t == "PO") { _onTapTombolKuning('PO'); } // form tampil di panel bawah layar, bukan bottom sheet
      else if (t == "LS") { _onTapTombolKuning('LS'); } // form tampil di panel bawah layar, bukan bottom sheet
      else if (t == "CEK") { _onTapTombolKuning('CEK'); } // form tampil di panel bawah layar, bukan bottom sheet
      else if (t == "CPS") { _onTapTombolKuning('CPS'); } // form tampil di panel bawah layar, bukan bottom sheet
      else if (t == "RIW") { _onTapTombolKuning('RIW'); } // form tampil di panel bawah layar, bukan bottom sheet
      else if (t == "TAX+") { _pencetTaxPlus(); }
      else if (t == "TAX-") { _pencetTaxMin(); }
      else if (t == "SET TAX") { _setTax(); }
      else if (t == "COST") { _pencetCost(); }
      else if (t == "SELL") { _pencetSell(); }
      else if (t == "MARGIN") { _pencetMargin(); }
      else if (t == "CSM CLR") { _resetCSM(); }
      else if (t == "ROUND") { _gantiRound(); }
      else if (t == "ADD2") { _gantiAdd2(); }
      else if (t == "BEP") {
        if (hargaAcuan > 0) { layar = formatHasil(hargaAcuan * 1.1); ekspresi = "BEP = Acuan x 110%"; }
        else { layar = formatHasil((double.tryParse(_stripBacktick(layar)) ?? 0) + 120); }
        entryBaru = true;
      }
      else if (t == "M+") {
        // Qty M+ = qty yang diketik user, BUKAN hasil / angka sebelum operator (fix Qty 3750000.0 di CEK):
        // - Baru ketik angka (entryBaru false) -> qty = angka itu, kecuali angka = harga barang -> 1.
        // - Layar nunjukin hasil (=) -> qty = qty hitungan terakhir (_qtyMPlus, operand yang bukan harga barang).
        // - Habis pencet operator, belum (=) -> qty = angka sebelum operator, kecuali = harga barang -> 1.
        final hargaTerpilihM = barangDipilih == null ? -1 : (int.tryParse("${barangDipilih!["harga1"]}") ?? -1);
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
          final harga = int.tryParse("${barangDipilih!["harga1"]}") ?? 0;
          final jumlah = qtyAman * harga; // SUBTOTAL PER ITEM = qty x harga satuan. Bukan qty = subtotal.
          final it = parseInputCepat("$qtyAman x ${barangDipilih!["nama"]} $harga");
          if (it != null) { ref.read(poProvider.notifier).tambahItem(it); }
          steps.add({"item": "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}", "rumus": "${barangDipilih!["nama"]} : $qtyAman x ${formatRupiah(harga)} = ${formatRupiah(jumlah)}", "harga": harga, "qty": qtyAman, "jumlah": jumlah, "chain": <Map<String, dynamic>>[]});
        }
        // M+ barusan nambah barang ke PO -> langsung buka panel PO Daftar Item biar barangnya kelihatan.
        // M+ tanpa barang terpilih = cuma memori kalkulator, jangan buka PO.
        if (barangDipilih != null) { poTerbuka = true; _tombolKuningAktif = ''; }
        layar = "0"; entryBaru = true; adaQtyHitung = false;
      }
      else if (t == "M-") {
        // M- = NGURANGI BARIS.
        // Mode MR (lagi cek cepat per baris): hapus 1 baris yang SEDANG DIDISPLAY (step CEK + baris PO pasangannya di index yang sama). Habis hapus, tampilkan baris yang geser ke posisi itu.
        // Mode normal: hapus 1 baris terakhir PO recent + 1 step terakhir CEK recent. Satu tekan = satu baris hilang.
        if (_mrIndex >= 0 && _mrJumlahBaris() > 0) {
          final idx = _mrIndex.clamp(0, _mrJumlahBaris() - 1);
          final hapus = _mrBaris(idx);
          memori -= hapus['jumlah'] as double;
          if (steps.isNotEmpty && idx < steps.length) { steps.removeAt(idx); }
          final poItemsM = ref.read(poProvider).items;
          if (idx < poItemsM.length) { ref.read(poProvider.notifier).hapusItem(idx); }
          // Tetap di mode MR: tampilkan baris yang sekarang di posisi itu (atau baris sebelumnya kalau tadi baris terakhir).
          if (_mrJumlahBaris() == 0) {
            _mrIndex = -1;
            layar = "0"; ekspresi = "MR: semua baris sudah dihapus."; entryBaru = true;
          } else {
            if (_mrIndex >= _mrJumlahBaris()) { _mrIndex = _mrJumlahBaris() - 1; }
            final st = _mrBaris(_mrIndex);
            layar = formatHasil(st['jumlah'] as double);
            ekspresi = "MR ${_mrIndex + 1}/${_mrJumlahBaris()} • ${st['teks']}";
            entryBaru = true;
          }
          Future.microtask(() { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baris MR dihapus.'))); } });
        } else {
          memori -= double.tryParse(_stripBacktick(layar)) ?? 0;
          var pesanM = '';
          final poItemsM = ref.read(poProvider).items;
          if (poItemsM.isNotEmpty) { final namaHapus = poItemsM.last.namaBarang; ref.read(poProvider.notifier).hapusItem(poItemsM.length - 1); pesanM = 'Baris PO "$namaHapus" dihapus. '; }
          if (steps.isNotEmpty) { steps.removeLast(); pesanM += 'Step terakhir CEK dihapus.'; }
          if (pesanM.isEmpty) { pesanM = 'Tidak ada baris PO / step CEK.'; }
          layar = "0"; entryBaru = true;
          final pesanFinal = pesanM;
          Future.microtask(() { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesanFinal))); } });
        }
      }
      else if (t == "MRT") {
        // MRT = pengganti MRC. Ngecek TOTAL semua step CEK. Step-nya TIDAK mengganggu layar:
        // total tampil di layar, daftar step-nya tampil di strip 1 baris yang cuma bisa digeser kiri-kanan.
        // Tiap step ditandai "step; ". Pencet MRT lagi = tutup strip. Memori TIDAK ikut di-nol-kan (itu tugas MC).
        final totalStep = steps.fold<double>(0, (a, st) => a + (((st['jumlah'] as num?)?.toDouble() ?? 0)));
        _mrtTerbuka = !_mrtTerbuka;
        layar = formatHasil(totalStep);
        ekspresi = "MRT = total ${steps.length} step";
        entryBaru = true;
      }
      else if (t == "MR") {
        // MR = CEK CEPAT per baris (step CEK, atau baris PO kalau CEK kosong). Tiap pencet MR = baris berikutnya (muter balik ke baris 1 habis baris terakhir).
        // Sambil mode MR, selipkan M- untuk hapus baris yang sedang didisplay. Tombol lain keluar dari mode MR.
        // RIW TIDAK ikut sistem ini (RIW = log, bukan cek).
        final nMR = _mrJumlahBaris();
        if (nMR == 0) {
          _mrIndex = -1;
          layar = "0"; ekspresi = "MR: tidak ada baris M+."; entryBaru = true;
        } else {
          if (_mrIndex < 0) { _mrIndex = 0; }
          else { _mrIndex = (_mrIndex + 1) % nMR; }
          final bMR = _mrBaris(_mrIndex);
          layar = formatHasil(bMR['jumlah'] as double);
          ekspresi = "MR ${_mrIndex + 1}/$nMR • ${bMR['teks']}";
          entryBaru = true;
        }
      }
      else if (t == "MC") {
        // MC = CLEAR SEMUA M+: memori nol + semua baris PO + semua step CEK dibersihkan. RIW tidak ikut (RIW = log).
        final nPO = ref.read(poProvider).items.length;
        final nStep = steps.length;
        memori = 0;
        _mrIndex = -1;
        _mrtTerbuka = false;
        while (ref.read(poProvider).items.isNotEmpty) { ref.read(poProvider.notifier).hapusItem(0); }
        steps.clear();
        _stepTerpilih = {};
        _poTerpilih = {};
        layar = "0"; entryBaru = true;
        final pesanFinal = 'MC: semua M+ dibersihkan ($nPO baris PO + $nStep step CEK).';
        Future.microtask(() { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesanFinal))); } });
      }
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
      else { _inputAngka(t); }
    });
  }

  void bukaFormTambahBarang({Map<String, dynamic>? barangEdit}) {
    _diFormTambahBarang = true;
    final edit = barangEdit != null;
    final kodeLama = edit ? '${barangEdit["kode"] ?? ''}' : '';
    // Mode EDIT: isi form dari barang yang diedit. Mode TAMBAH: form kosong (default), biar tidak kebawa sisa edit sebelumnya.
    if (edit) {
      final b = barangEdit;
      kodeCtrl.text = '${b["kode"] ?? ''}';
      namaCtrl.text = '${b["nama"] ?? ''}';
      final kat = '${b["kategori"] ?? ''}';
      if (kat.isNotEmpty && !listKategori.contains(kat)) { listKategori.add(kat); }
      kategoriPilih = kat.isNotEmpty ? kat : listKategori.first;
      unitCtrl.text = '${b["satuan"] ?? 'sak'}';
      harga1Ctrl.text = '${b["harga1"] ?? ''}';
      kategoriBaruCtrl.clear();
      final varianTeks = '${b["varian"] ?? ''}';
      final varianList = varianTeks.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      varianCtrls.clear();
      varianCtrls.addAll(varianList.isEmpty ? [TextEditingController()] : varianList.map((v) => TextEditingController(text: v)).toList());
      final sl = (b["satuanList"] as List?) ?? [];
      if (sl.isNotEmpty) {
        satuanList = sl.map((x) {
          final m = Map<String, dynamic>.from(x as Map);
          return SatuanItem(satuan: '${m["satuan"] ?? ''}', dasar: m["dasar"] == true, qty: '${m["qty"] ?? '1'}', isi: '${m["isi"] ?? '1'}', op: '${m["op"] ?? 'x'}', nominal: '${m["nominal"] ?? ''}', satuanBaru: '${m["satuanBaru"] ?? ''}');
        }).toList();
      } else {
        satuanList = [SatuanItem(satuan: "sak", dasar: true, qty: "1", isi: "1", op: "x", nominal: "50000", satuanBaru: "sak"), SatuanItem(satuan: "sak", dasar: false, qty: "1", isi: "50", op: "÷", nominal: "1000", satuanBaru: "pcs")];
      }
    } else {
      kodeCtrl.clear();
      namaCtrl.clear();
      kategoriPilih = listKategori.first;
      unitCtrl.text = 'sak';
      harga1Ctrl.text = '50000';
      kategoriBaruCtrl.clear();
      varianCtrls.clear();
      varianCtrls.add(TextEditingController(text: 'Hitam'));
      satuanList = [SatuanItem(satuan: "sak", dasar: true, qty: "1", isi: "1", op: "x", nominal: "50000", satuanBaru: "sak"), SatuanItem(satuan: "sak", dasar: false, qty: "1", isi: "50", op: "÷", nominal: "1000", satuanBaru: "pcs")];
    }
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSheet) {
          return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 12, right: 12, top: 12),
            child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(edit ? "Edit Barang" : "Tambah Barang", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
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
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () { final varian = varianCtrls.map((c) => c.text).join(", "); for (var c in varianCtrls) { tambahKeDaftarSatuan(c.text); } for (var x in satuanList) { tambahKeDaftarSatuan(x.satuanBaruCtrl.text); } setState(() {
                  final barangBaru = {"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''), "satuan": unitCtrl.text, "varian": varian, "satuanList": satuanList.map((x) => x.toMap()).toList()};
                  if (edit) {
                    // UPDATE: ganti barang lama (cari pakai kode lama, karena kode bisa diubah di form).
                    final idx = daftarBarang.indexWhere((x) => x["kode"] == kodeLama);
                    if (idx >= 0) { daftarBarang[idx] = barangBaru; } else { daftarBarang.add(barangBaru); }
                    // Kalau barang yang diedit sedang dipilih, update pilihannya juga.
                    if (barangDipilih != null && barangDipilih!["kode"] == kodeLama) { barangDipilih = {"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')}; }
                  } else {
                    daftarBarang.add(barangBaru);
                    barangDipilih = {"kode": kodeCtrl.text, "nama": namaCtrl.text, "kategori": kategoriPilih, "harga1": harga1Ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')};
                  }
                }); _simpanSemuaKeDB(); Navigator.pop(ctx); }, child: Text(edit ? "Update Barang" : "Simpan Barang", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 20),
            ])));
        });
      },
    ).then((_) { _diFormTambahBarang = false; });
  }
  // ===== BENTUK FISIK CASIO DJ-120 =====
  // Body krem, display hijau LCD 2 baris, tombol 3D: atas datar, bawah bayangan.
  // Tombol angka putih, operator abu, AC/ON biru, M+ hijau, = biru, BEP pink.
  // ignore: unused_element
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
    final headerKalkulator = Container(color: const Color(0xFF1A1A1A), padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("BASKORO WINGCHUN", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), GestureDetector(onTap: dialogBabe, child: const Text("BABE•INFO - dialog kalkulasi", style: TextStyle(color: Colors.white70, fontSize: 9, decoration: TextDecoration.underline)))]),
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
          Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: _kirimWA, style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 10)), child: const Text("Kirim WA")))),
          const SizedBox(width: 4),
          Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: _tampilNota, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 9), backgroundColor: Colors.white), child: const Text("Nota")))),
        ]),
      ]),
    );
    return Scaffold(backgroundColor: const Color(0xFFE8E0C8),
      body: SafeArea(child: Column(children: [
        headerKalkulator,
        _panelForm(),
        if (poTerbuka) Expanded(child: _panelDaftarItemPO()),
        if (!poTerbuka) _stripTengah(),
        if (_mrtTerbuka) _stripMRT(),
        Expanded(child: _areaTombolBawah()),
      ])),
    );
  }
}
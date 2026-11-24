import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// PO + Log Step + Cache Pelanggan + Alias Copas, tersimpan di SQLite (sqflite, tanpa codegen).
//
// Modelnya:
//   - Log step (riwayat) = 1 step = 1 subtotal. Tiap step baru langsung tercatat.
//     Riwayat TIDAK nunggu PO.
//   - PO = kumpulan step (1 paragraf). Disimpan lewat tombol "Simpan PO".
//   - Pelanggan = nama yang pernah diinput sekali -> dipakai lagi untuk saran otomatis.
//   - Alias copas = pasangan nama copasan -> kode barang LS, dipelajari dari pilih
//     manual di CPS. Lain kali nama copasan yang sama langsung cocok otomatis.
//
// Tabel:
//   po_tersimpan      -> 1 baris = 1 PO (nomor, tanggal, pelanggan, total)
//   po_item_tersimpan -> step / item di dalam 1 PO
//   log_step          -> log tiap step (riwayat)
//   pelanggan         -> cache nama pelanggan
//   alias_copas       -> nama copasan -> kode barang LS
//   barang            -> daftar barang LS (kode, nama, kategori, harga1, satuan, varian, satuanList)
//   step_draf         -> step CEK yang sedang dikerjakan (draf). Disimpan tiap step berubah,
//                        dimuat lagi saat buka aplikasi — jadi tutup aplikasi tidak hilang.
class PoDatabase {
  static const _namaFile = 'po_kalkulator.sqlite';
  static const _versi = 7; // v4: + nama_barang | v5: + harga_acuan/satuan_angka/op_satuan | v6: + tabel barang & step_draf (draf CEK anti-hilang) | v7: + nomor_wa/dicek di po_tersimpan, + satuan di item/log/step_draf, + tabel po_draf (PO aktif anti-hilang)

  Future<Database>? _dbFuture;

  Future<Database> get _database {
    _dbFuture ??= _buka();
    return _dbFuture!;
  }

  Future<Database> _buka() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _namaFile);
    return openDatabase(path, version: _versi,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE po_tersimpan('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'nomor TEXT NOT NULL, '
            'tanggal TEXT NOT NULL, '
            'pelanggan TEXT NOT NULL DEFAULT \'\', '
            'total REAL NOT NULL, '
            'nomor_wa TEXT NOT NULL DEFAULT \'\', '
            'dicek INTEGER NOT NULL DEFAULT 0, '
            'dibuat_pada INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE po_item_tersimpan('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'po_id INTEGER NOT NULL, '
            'item TEXT NOT NULL, '
            'rumus TEXT NOT NULL, '
            'nama_barang TEXT NOT NULL DEFAULT \'\', '
            'harga_acuan REAL NOT NULL DEFAULT 0, '
            'satuan_angka REAL NOT NULL DEFAULT 1, '
            'op_satuan TEXT NOT NULL DEFAULT \'x\', '
            'harga REAL NOT NULL, '
            'qty REAL NOT NULL, '
            'jumlah REAL NOT NULL, '
            'satuan TEXT NOT NULL DEFAULT \'\', '
            'urutan INTEGER NOT NULL, '
            'FOREIGN KEY (po_id) REFERENCES po_tersimpan (id))',
          );
          await db.execute(
            'CREATE TABLE log_step('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'item TEXT NOT NULL, '
            'rumus TEXT NOT NULL, '
            'nama_barang TEXT NOT NULL DEFAULT \'\', '
            'harga_acuan REAL NOT NULL DEFAULT 0, '
            'satuan_angka REAL NOT NULL DEFAULT 1, '
            'op_satuan TEXT NOT NULL DEFAULT \'x\', '
            'harga REAL NOT NULL, '
            'qty REAL NOT NULL, '
            'jumlah REAL NOT NULL, '
            'satuan TEXT NOT NULL DEFAULT \'\', '
            'dibuat_pada INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE pelanggan('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'nama TEXT NOT NULL, '
            'terakhir_dipakai INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE alias_copas('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'nama_copas TEXT NOT NULL, '
            'kode_barang TEXT NOT NULL, '
            'terakhir_dipakai INTEGER NOT NULL)',
          );
          // v6: barang LS + draf step CEK (biar tutup aplikasi tidak hilang).
          await db.execute(
            'CREATE TABLE barang('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'kode TEXT NOT NULL, '
            'nama TEXT NOT NULL, '
            'kategori TEXT NOT NULL DEFAULT \'\', '
            'harga1 TEXT NOT NULL DEFAULT \'\', '
            'satuan TEXT NOT NULL DEFAULT \'sak\', '
            'varian TEXT NOT NULL DEFAULT \'\', '
            'satuan_list TEXT NOT NULL DEFAULT \'[]\')',
          );
          await db.execute(
            'CREATE TABLE step_draf('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'item TEXT NOT NULL, '
            'rumus TEXT NOT NULL, '
            'nama_barang TEXT NOT NULL DEFAULT \'\', '
            'harga_acuan REAL NOT NULL DEFAULT 0, '
            'satuan_angka REAL NOT NULL DEFAULT 1, '
            'op_satuan TEXT NOT NULL DEFAULT \'x\', '
            'harga REAL NOT NULL, '
            'qty REAL NOT NULL, '
            'jumlah REAL NOT NULL, '
            'satuan TEXT NOT NULL DEFAULT \'\', '
            'urutan INTEGER NOT NULL)',
          );
          // v7: draf PO aktif (PO Recent) — biar tutup aplikasi tidak hilang.
          await db.execute(
            'CREATE TABLE po_draf('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'nama TEXT NOT NULL, '
            'harga REAL NOT NULL, '
            'qty REAL NOT NULL, '
            'jumlah REAL NOT NULL, '
            'satuan TEXT NOT NULL DEFAULT \'\', '
            'step TEXT NOT NULL DEFAULT \'\', '
            'urutan INTEGER NOT NULL)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS log_step('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'item TEXT NOT NULL, '
              'rumus TEXT NOT NULL, '
              'harga REAL NOT NULL, '
              'qty REAL NOT NULL, '
              'jumlah REAL NOT NULL, '
              'dibuat_pada INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE IF NOT EXISTS pelanggan('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'nama TEXT NOT NULL, '
              'terakhir_dipakai INTEGER NOT NULL)',
            );
            try {
              await db.execute(
                  "ALTER TABLE po_tersimpan ADD COLUMN pelanggan TEXT NOT NULL DEFAULT ''");
            } catch (_) {
              // Kolom sudah ada (DB pernah dibuat versi 2) -> lewati.
            }
          }
          if (oldVersion < 3) {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS alias_copas('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'nama_copas TEXT NOT NULL, '
              'kode_barang TEXT NOT NULL, '
              'terakhir_dipakai INTEGER NOT NULL)',
            );
          }
          if (oldVersion < 4) {
            // v4: nama barang per step. DB lama tetap jalan — kolom baru default ''.
            try {
              await db.execute(
                  "ALTER TABLE log_step ADD COLUMN nama_barang TEXT NOT NULL DEFAULT ''");
            } catch (_) {}
            try {
              await db.execute(
                  "ALTER TABLE po_item_tersimpan ADD COLUMN nama_barang TEXT NOT NULL DEFAULT ''");
            } catch (_) {}
          }
          if (oldVersion < 5) {
            // v5: pecahan Harga step CEK (Harga Acuan x/÷ Satuan). DB lama tetap jalan.
            try {
              await db.execute(
                  'ALTER TABLE log_step ADD COLUMN harga_acuan REAL NOT NULL DEFAULT 0');
            } catch (_) {}
            try {
              await db.execute(
                  'ALTER TABLE log_step ADD COLUMN satuan_angka REAL NOT NULL DEFAULT 1');
            } catch (_) {}
            try {
              await db.execute(
                  "ALTER TABLE log_step ADD COLUMN op_satuan TEXT NOT NULL DEFAULT 'x'");
            } catch (_) {}
            try {
              await db.execute(
                  'ALTER TABLE po_item_tersimpan ADD COLUMN harga_acuan REAL NOT NULL DEFAULT 0');
            } catch (_) {}
            try {
              await db.execute(
                  'ALTER TABLE po_item_tersimpan ADD COLUMN satuan_angka REAL NOT NULL DEFAULT 1');
            } catch (_) {}
            try {
              await db.execute(
                  "ALTER TABLE po_item_tersimpan ADD COLUMN op_satuan TEXT NOT NULL DEFAULT 'x'");
            } catch (_) {}
            // Isi harga_acuan lama dari harga — biar step lama tidak jadi 0 di CEK.
            await db.execute('UPDATE log_step SET harga_acuan = harga WHERE harga_acuan = 0');
            await db.execute('UPDATE po_item_tersimpan SET harga_acuan = harga WHERE harga_acuan = 0');
          }
          if (oldVersion < 6) {
            // v6: tabel barang LS + draf step CEK. DB lama tetap jalan (IF NOT EXISTS).
            await db.execute(
              'CREATE TABLE IF NOT EXISTS barang('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'kode TEXT NOT NULL, '
              'nama TEXT NOT NULL, '
              'kategori TEXT NOT NULL DEFAULT \'\', '
              'harga1 TEXT NOT NULL DEFAULT \'\', '
              'satuan TEXT NOT NULL DEFAULT \'sak\', '
              'varian TEXT NOT NULL DEFAULT \'\', '
              'satuan_list TEXT NOT NULL DEFAULT \'[]\')',
            );
            await db.execute(
              'CREATE TABLE IF NOT EXISTS step_draf('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'item TEXT NOT NULL, '
              'rumus TEXT NOT NULL, '
              'nama_barang TEXT NOT NULL DEFAULT \'\', '
              'harga_acuan REAL NOT NULL DEFAULT 0, '
              'satuan_angka REAL NOT NULL DEFAULT 1, '
              'op_satuan TEXT NOT NULL DEFAULT \'x\', '
              'harga REAL NOT NULL, '
              'qty REAL NOT NULL, '
              'jumlah REAL NOT NULL, '
              'satuan TEXT NOT NULL DEFAULT \'\', '
              'urutan INTEGER NOT NULL)',
            );
          }
          if (oldVersion < 7) {
            // v7: nomor_wa + dicek di po_tersimpan, satuan di item/log/step_draf, tabel po_draf (PO aktif). DB lama tetap jalan (try/catch + IF NOT EXISTS).
            try { await db.execute("ALTER TABLE po_tersimpan ADD COLUMN nomor_wa TEXT NOT NULL DEFAULT ''"); } catch (_) {}
            try { await db.execute('ALTER TABLE po_tersimpan ADD COLUMN dicek INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
            try { await db.execute("ALTER TABLE po_item_tersimpan ADD COLUMN satuan TEXT NOT NULL DEFAULT ''"); } catch (_) {}
            try { await db.execute("ALTER TABLE log_step ADD COLUMN satuan TEXT NOT NULL DEFAULT ''"); } catch (_) {}
            try { await db.execute("ALTER TABLE step_draf ADD COLUMN satuan TEXT NOT NULL DEFAULT ''"); } catch (_) {}
            await db.execute(
              'CREATE TABLE IF NOT EXISTS po_draf('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'nama TEXT NOT NULL, '
              'harga REAL NOT NULL, '
              'qty REAL NOT NULL, '
              'jumlah REAL NOT NULL, '
              'satuan TEXT NOT NULL DEFAULT \'\', '
              'step TEXT NOT NULL DEFAULT \'\', '
              'urutan INTEGER NOT NULL)',
            );
          }
        });
  }

  // ===== PO =====
  Future<List<Map<String, dynamic>>> muatSemuaPo() async {
    final db = await _database;
    final rows = await db.query('po_tersimpan', orderBy: 'dibuat_pada DESC');
    final hasil = <Map<String, dynamic>>[];
    for (final r in rows) {
      final items = await db.query('po_item_tersimpan',
          where: 'po_id = ?', whereArgs: [r['id']], orderBy: 'urutan ASC');
      hasil.add({
        "id": r['id'],
        "nomor": r['nomor'],
        "tanggal": r['tanggal'],
        "pelanggan": r['pelanggan'] ?? '',
        "total": (r['total'] as num).toDouble(),
        "nomorWA": r['nomor_wa'] ?? '',
        "dicek": (r['dicek'] as num?)?.toInt() ?? 0,
        "items": items
            .map((e) => {
                  "item": e['item'],
                  "rumus": e['rumus'],
                  "namaBarang": e['nama_barang'] ?? '',
                  "hargaAcuan": (e['harga_acuan'] as num?)?.toDouble() ?? (e['harga'] as num?)?.toDouble() ?? 0,
                  "satuanAngka": (e['satuan_angka'] as num?)?.toDouble() ?? 1,
                  "opSatuan": e['op_satuan'] ?? 'x',
                  "harga": (e['harga'] as num).toDouble(),
                  "qty": (e['qty'] as num).toDouble(),
                  "jumlah": (e['jumlah'] as num).toDouble(),
                  "satuan": e['satuan'] ?? '',
                })
            .toList(),
      });
    }
    return hasil;
  }

  Future<int> simpanPoBaru({
    required String nomor,
    required String tanggal,
    required String pelanggan,
    required double total,
    required List<Map<String, dynamic>> items,
    String nomorWA = '',
    bool dicek = false,
  }) async {
    final db = await _database;
    final id = await db.insert('po_tersimpan', {
      'nomor': nomor,
      'tanggal': tanggal,
      'pelanggan': pelanggan,
      'total': total,
      'nomor_wa': nomorWA,
      'dicek': dicek ? 1 : 0,
      'dibuat_pada': DateTime.now().millisecondsSinceEpoch,
    });
    await _tulisItems(db, id, items);
    return id;
  }

  Future<void> updatePo({
    required int id,
    required String tanggal,
    required String pelanggan,
    required double total,
    required List<Map<String, dynamic>> items,
    String nomorWA = '',
    bool dicek = false,
  }) async {
    final db = await _database;
    await db.update(
        'po_tersimpan',
        {'tanggal': tanggal, 'pelanggan': pelanggan, 'total': total, 'nomor_wa': nomorWA, 'dicek': dicek ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await db.delete('po_item_tersimpan', where: 'po_id = ?', whereArgs: [id]);
    await _tulisItems(db, id, items);
  }

  Future<void> hapusPo(int id) async {
    final db = await _database;
    await db.delete('po_item_tersimpan', where: 'po_id = ?', whereArgs: [id]);
    await db.delete('po_tersimpan', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _tulisItems(
      Database db, int poId, List<Map<String, dynamic>> items) async {
    for (var k = 0; k < items.length; k++) {
      final e = items[k];
      await db.insert('po_item_tersimpan', {
        'po_id': poId,
        'item': "${e["item"]}",
        'rumus': "${e["rumus"] ?? ""}",
        'nama_barang': "${e["namaBarang"] ?? ""}",
        'harga_acuan': (e["hargaAcuan"] as num?)?.toDouble() ?? (e["harga"] as num?)?.toDouble() ?? 0,
        'satuan_angka': (e["satuanAngka"] as num?)?.toDouble() ?? 1,
        'op_satuan': "${e["opSatuan"] ?? "x"}",
        'harga': (e["harga"] as num?)?.toDouble() ?? 0,
        'qty': (e["qty"] as num?)?.toDouble() ?? 0,
        'jumlah': (e["jumlah"] as num?)?.toDouble() ?? 0,
        'satuan': "${e["satuan"] ?? ''}",
        'urutan': k,
      });
    }
  }

  // ===== LOG STEP (Riwayat) =====
  Future<int> tambahLogStep({
    required String item,
    required String rumus,
    String namaBarang = '',
    double hargaAcuan = 0,
    double satuanAngka = 1,
    String opSatuan = 'x',
    required double harga,
    required double qty,
    required double jumlah,
    String satuan = '',
  }) async {
    final db = await _database;
    return db.insert('log_step', {
      'item': item,
      'rumus': rumus,
      'nama_barang': namaBarang,
      'harga_acuan': hargaAcuan,
      'satuan_angka': satuanAngka,
      'op_satuan': opSatuan,
      'harga': harga,
      'qty': qty,
      'jumlah': jumlah,
      'satuan': satuan,
      'dibuat_pada': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> muatLogStep() async {
    final db = await _database;
    final rows = await db.query('log_step', orderBy: 'dibuat_pada DESC');
    return rows.map((r) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
          (r['dibuat_pada'] as num).toInt());
      return {
        "id": r['id'],
        "item": r['item'],
        "rumus": r['rumus'],
        "namaBarang": r['nama_barang'] ?? '',
        "hargaAcuan": (r['harga_acuan'] as num?)?.toDouble() ?? (r['harga'] as num?)?.toDouble() ?? 0,
        "satuanAngka": (r['satuan_angka'] as num?)?.toDouble() ?? 1,
        "opSatuan": r['op_satuan'] ?? 'x',
        "harga": (r['harga'] as num).toDouble(),
        "qty": (r['qty'] as num).toDouble(),
        "jumlah": (r['jumlah'] as num).toDouble(),
        "satuan": r['satuan'] ?? '',
        "tanggal":
            "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}",
      };
    }).toList();
  }

  Future<void> hapusLogStep(int id) async {
    final db = await _database;
    await db.delete('log_step', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> hapusSemuaLogStep() async {
    final db = await _database;
    await db.delete('log_step');
  }

  // ===== CACHE PELANGGAN (untuk saran otomatis) =====
  Future<List<String>> muatPelanggan() async {
    final db = await _database;
    final rows = await db.query('pelanggan',
        orderBy: 'terakhir_dipakai DESC', limit: 50);
    return rows.map((r) => "${r['nama']}").toList();
  }

  Future<void> simpanPelanggan(String nama) async {
    final v = nama.trim();
    if (v.isEmpty) return;
    final db = await _database;
    final skrg = DateTime.now().millisecondsSinceEpoch;
    final ada = await db.query('pelanggan',
        where: 'LOWER(nama) = ?', whereArgs: [v.toLowerCase()]);
    if (ada.isEmpty) {
      await db.insert('pelanggan', {'nama': v, 'terakhir_dipakai': skrg});
    } else {
      await db.update('pelanggan', {'terakhir_dipakai': skrg},
          where: 'id = ?', whereArgs: [ada.first['id']]);
    }
  }

  // ===== ALIAS COPAS (nama copasan -> kode barang LS) =====
  Future<Map<String, String>> muatAliasCopas() async {
    final db = await _database;
    final rows = await db.query('alias_copas', orderBy: 'terakhir_dipakai DESC');
    return {for (final r in rows) "${r['nama_copas']}": "${r['kode_barang']}"};
  }

  Future<void> simpanAliasCopas(
      {required String namaCopas, required String kodeBarang}) async {
    final kunci = namaCopas.trim().toLowerCase();
    if (kunci.isEmpty || kodeBarang.isEmpty) return;
    final db = await _database;
    final skrg = DateTime.now().millisecondsSinceEpoch;
    final ada = await db.query('alias_copas',
        where: 'nama_copas = ?', whereArgs: [kunci]);
    if (ada.isEmpty) {
      await db.insert('alias_copas',
          {'nama_copas': kunci, 'kode_barang': kodeBarang, 'terakhir_dipakai': skrg});
    } else {
      await db.update('alias_copas',
          {'kode_barang': kodeBarang, 'terakhir_dipakai': skrg},
          where: 'id = ?', whereArgs: [ada.first['id']]);
    }
  }

  // ===== BARANG LS (daftar barang — dulu cuma memori, sekarang tersimpan) =====
  Future<List<Map<String, dynamic>>> muatBarang() async {
    final db = await _database;
    final rows = await db.query('barang', orderBy: 'id ASC');
    return rows.map((r) {
      List satuanList = [];
      try {
        final dec = jsonDecode("${r['satuan_list'] ?? '[]'}");
        if (dec is List) satuanList = dec;
      } catch (_) {}
      return {
        "kode": "${r['kode'] ?? ''}",
        "nama": "${r['nama'] ?? ''}",
        "kategori": "${r['kategori'] ?? ''}",
        "harga1": "${r['harga1'] ?? ''}",
        "satuan": "${r['satuan'] ?? 'sak'}",
        "varian": "${r['varian'] ?? ''}",
        "satuanList": satuanList,
      };
    }).toList();
  }

  Future<void> simpanBarang(List<Map<String, dynamic>> items) async {
    final db = await _database;
    await db.delete('barang');
    for (final it in items) {
      await db.insert('barang', {
        'kode': "${it["kode"] ?? ''}",
        'nama': "${it["nama"] ?? ''}",
        'kategori': "${it["kategori"] ?? ''}",
        'harga1': "${it["harga1"] ?? ''}",
        'satuan': "${it["satuan"] ?? 'sak'}",
        'varian': "${it["varian"] ?? ''}",
        'satuan_list': jsonEncode(it["satuanList"] ?? []),
      });
    }
  }

  // ===== DRAF STEP CEK (step yang sedang dikerjakan — anti-hilang) =====
  Future<List<Map<String, dynamic>>> muatStepDraf() async {
    final db = await _database;
    final rows = await db.query('step_draf', orderBy: 'urutan ASC');
    return rows.map((r) => {
          "item": "${r['item'] ?? ''}",
          "rumus": "${r['rumus'] ?? ''}",
          "namaBarang": "${r['nama_barang'] ?? ''}",
          "hargaAcuan": (r['harga_acuan'] as num?)?.toDouble() ?? (r['harga'] as num?)?.toDouble() ?? 0,
          "satuanAngka": (r['satuan_angka'] as num?)?.toDouble() ?? 1,
          "opSatuan": "${r['op_satuan'] ?? 'x'}",
          "harga": (r['harga'] as num?)?.toDouble() ?? 0,
          "qty": (r['qty'] as num?)?.toDouble() ?? 0,
          "jumlah": (r['jumlah'] as num?)?.toDouble() ?? 0,
          "satuan": "${r['satuan'] ?? '' }",
        }).toList();
  }

  Future<void> simpanStepDraf(List<Map<String, dynamic>> items) async {
    final db = await _database;
    await db.delete('step_draf');
    var urutan = 0;
    for (final it in items) {
      await db.insert('step_draf', {
        'item': "${it["item"] ?? ''}",
        'rumus': "${it["rumus"] ?? ''}",
        'nama_barang': "${it["namaBarang"] ?? ''}",
        'harga_acuan': (it["hargaAcuan"] as num?)?.toDouble() ?? (it["harga"] as num?)?.toDouble() ?? 0,
        'satuan_angka': (it["satuanAngka"] as num?)?.toDouble() ?? 1,
        'op_satuan': "${it["opSatuan"] ?? 'x'}",
        'harga': (it["harga"] as num?)?.toDouble() ?? 0,
        'qty': (it["qty"] as num?)?.toDouble() ?? 0,
        'jumlah': (it["jumlah"] as num?)?.toDouble() ?? 0,
        'satuan': "${it["satuan"] ?? ''}",
        'urutan': urutan++,
      });
    }
  }

  // ===== PO DRAF (PO aktif / PO Recent, belum jadi PO tersimpan) =====
  // PO aktif disimpan terpisah dari step CEK, biar tutup/buka kalkulator tidak hilang.
  Future<List<Map<String, dynamic>>> muatPoDraf() async {
    final db = await _database;
    final rows = await db.query('po_draf', orderBy: 'urutan ASC');
    return rows.map((r) => {
      'nama': r['nama'] ?? '',
      'harga': (r['harga'] as num?)?.toDouble() ?? 0,
      'qty': (r['qty'] as num?)?.toDouble() ?? 0,
      'jumlah': (r['jumlah'] as num?)?.toDouble() ?? 0,
      'satuan': r['satuan'] ?? '',
      'step': r['step'] ?? '',
    }).toList();
  }
  Future<void> simpanPoDraf(List<Map<String, dynamic>> items) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('po_draf');
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        await txn.insert('po_draf', {
          'nama': it['nama'] ?? '',
          'harga': (it['harga'] as num?)?.toDouble() ?? 0,
          'qty': (it['qty'] as num?)?.toDouble() ?? 0,
          'jumlah': (it['jumlah'] as num?)?.toDouble() ?? 0,
          'satuan': it['satuan'] ?? '',
          'step': it['step'] ?? '',
          'urutan': i,
        });
      }
    });
  }

  Future<void> close() async {
    final f = _dbFuture;
    _dbFuture = null;
    if (f == null) return;
    final db = await f;
    if (db.isOpen) await db.close();
  }
}

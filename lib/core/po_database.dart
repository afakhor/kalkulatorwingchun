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
class PoDatabase {
  static const _namaFile = 'po_kalkulator.sqlite';
  static const _versi = 3;

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
            'dibuat_pada INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE po_item_tersimpan('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'po_id INTEGER NOT NULL, '
            'item TEXT NOT NULL, '
            'rumus TEXT NOT NULL, '
            'harga REAL NOT NULL, '
            'qty REAL NOT NULL, '
            'jumlah REAL NOT NULL, '
            'urutan INTEGER NOT NULL, '
            'FOREIGN KEY (po_id) REFERENCES po_tersimpan (id))',
          );
          await db.execute(
            'CREATE TABLE log_step('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'item TEXT NOT NULL, '
            'rumus TEXT NOT NULL, '
            'harga REAL NOT NULL, '
            'qty REAL NOT NULL, '
            'jumlah REAL NOT NULL, '
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
        "items": items
            .map((e) => {
                  "item": e['item'],
                  "rumus": e['rumus'],
                  "harga": (e['harga'] as num).toDouble(),
                  "qty": (e['qty'] as num).toDouble(),
                  "jumlah": (e['jumlah'] as num).toDouble(),
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
  }) async {
    final db = await _database;
    final id = await db.insert('po_tersimpan', {
      'nomor': nomor,
      'tanggal': tanggal,
      'pelanggan': pelanggan,
      'total': total,
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
  }) async {
    final db = await _database;
    await db.update(
        'po_tersimpan',
        {'tanggal': tanggal, 'pelanggan': pelanggan, 'total': total},
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
        'harga': (e["harga"] as num?)?.toDouble() ?? 0,
        'qty': (e["qty"] as num?)?.toDouble() ?? 0,
        'jumlah': (e["jumlah"] as num?)?.toDouble() ?? 0,
        'urutan': k,
      });
    }
  }

  // ===== LOG STEP (Riwayat) =====
  Future<int> tambahLogStep({
    required String item,
    required String rumus,
    required double harga,
    required double qty,
    required double jumlah,
  }) async {
    final db = await _database;
    return db.insert('log_step', {
      'item': item,
      'rumus': rumus,
      'harga': harga,
      'qty': qty,
      'jumlah': jumlah,
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
        "harga": (r['harga'] as num).toDouble(),
        "qty": (r['qty'] as num).toDouble(),
        "jumlah": (r['jumlah'] as num).toDouble(),
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

  Future<void> close() async {
    final f = _dbFuture;
    _dbFuture = null;
    if (f == null) return;
    final db = await f;
    if (db.isOpen) await db.close();
  }
}

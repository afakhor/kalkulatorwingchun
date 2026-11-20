import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// PO + Riwayat tersimpan di SQLite (sqflite, tanpa codegen).
// API kelas ini SENGAJA dibuat sama persis dengan versi Drift sebelumnya,
// jadi home_daftar_po.dart tidak perlu diubah sama sekali.
//
// Tabel:
//   po_tersimpan      -> 1 baris = 1 PO (nomor, tanggal, total)
//   po_item_tersimpan -> step / item di dalam 1 PO
//   riwayat_po        -> Simpan / Revisi
class PoDatabase {
  static const _namaFile = 'po_kalkulator.sqlite';
  static const _versi = 1;

  Future<Database>? _dbFuture;

  Future<Database> get _database {
    _dbFuture ??= _buka();
    return _dbFuture!;
  }

  Future<Database> _buka() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _namaFile);
    return openDatabase(path, version: _versi, onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE po_tersimpan('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'nomor TEXT NOT NULL, '
        'tanggal TEXT NOT NULL, '
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
        'CREATE TABLE riwayat_po('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'nomor TEXT NOT NULL, '
        'tanggal TEXT NOT NULL, '
        'aksi TEXT NOT NULL, '
        'total REAL NOT NULL, '
        'ringkasan TEXT NOT NULL, '
        'dibuat_pada INTEGER NOT NULL)',
      );
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
    required double total,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await _database;
    final id = await db.insert('po_tersimpan', {
      'nomor': nomor,
      'tanggal': tanggal,
      'total': total,
      'dibuat_pada': DateTime.now().millisecondsSinceEpoch,
    });
    await _tulisItems(db, id, items);
    return id;
  }

  Future<void> updatePo({
    required int id,
    required String tanggal,
    required double total,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await _database;
    await db.update('po_tersimpan', {'tanggal': tanggal, 'total': total},
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

  // ===== RIWAYAT =====
  Future<int> tambahRiwayat({
    required String nomor,
    required String tanggal,
    required String aksi,
    required double total,
    required String ringkasan,
  }) async {
    final db = await _database;
    return db.insert('riwayat_po', {
      'nomor': nomor,
      'tanggal': tanggal,
      'aksi': aksi,
      'total': total,
      'ringkasan': ringkasan,
      'dibuat_pada': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> muatSemuaRiwayat() async {
    final db = await _database;
    final rows = await db.query('riwayat_po', orderBy: 'dibuat_pada DESC');
    return rows
        .map((r) => {
              "id": r['id'],
              "nomor": r['nomor'],
              "tanggal": r['tanggal'],
              "aksi": r['aksi'],
              "total": (r['total'] as num).toDouble(),
              "ringkasan": r['ringkasan'],
            })
        .toList();
  }

  Future<void> hapusRiwayat(int id) async {
    final db = await _database;
    await db.delete('riwayat_po', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> hapusSemuaRiwayat() async {
    final db = await _database;
    await db.delete('riwayat_po');
  }

  Future<void> close() async {
    final f = _dbFuture;
    _dbFuture = null;
    if (f == null) return;
    final db = await f;
    if (db.isOpen) await db.close();
  }
}

import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class PoDatabase {
  PoDatabase._internal();
  static final PoDatabase _instance = PoDatabase._internal();
  factory PoDatabase() => _instance;

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'babe_po_kalkulator.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE barang (
            kode TEXT PRIMARY KEY,
            data_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE step_draf (
            id INTEGER PRIMARY KEY,
            data_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE po_draf (
            id INTEGER PRIMARY KEY,
            data_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE po_tersimpan (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nomor TEXT NOT NULL,
            tanggal TEXT NOT NULL,
            pelanggan TEXT NOT NULL,
            nomor_wa TEXT NOT NULL DEFAULT '',
            dicek INTEGER NOT NULL DEFAULT 0,
            total REAL NOT NULL DEFAULT 0,
            items_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE alias_copas (
            nama_copas TEXT PRIMARY KEY,
            kode_barang TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // --- BARANG ---

  Future<void> simpanBarang(List> barang) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('barang');
      for (var i = 0; i < barang.length; i++) {
        final item = Map<String, dynamic>.from(barang[i]);
        final kodeRaw = '${item['kode'] ?? ''}'.trim();
        final kode = kodeRaw.isEmpty ? 'BRG-$i' : kodeRaw;
        item['kode'] = kode;
        await txn.insert(
          'barang',
          {
            'kode': kode,
            'data_json': jsonEncode(item),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List>> muatBarang() async {
    final db = await database;
    final rows = await db.query('barang');
    final hasil = >[];
    for (final r in rows) {
      try {
        final decoded = jsonDecode('${r['data_json']}');
        if (decoded is Map) {
          hasil.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return hasil;
  }

  // --- STEP DRAF ---

  Future<void> simpanStepDraf(List> steps) async {
    final db = await database;
    await db.insert(
      'step_draf',
      {
        'id': 1,
        'data_json': jsonEncode(steps),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List>> muatStepDraf() async {
    final db = await database;
    final rows = await db.query('step_draf', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return [];
    try {
      final decoded = jsonDecode('${rows.first['data_json']}');
      if (decoded is List) {
        return decoded
            .whereType()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // --- PO DRAF ---

  Future<void> simpanPoDraf(List> poDraf) async {
    final db = await database;
    await db.insert(
      'po_draf',
      {
        'id': 1,
        'data_json': jsonEncode(poDraf),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List>> muatPoDraf() async {
    final db = await database;
    final rows = await db.query('po_draf', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return [];
    try {
      final decoded = jsonDecode('${rows.first['data_json']}');
      if (decoded is List) {
        return decoded
            .whereType()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // --- PO TERSIMPAN ---

  Future<int> simpanPoBaru({
    required String nomor,
    required String tanggal,
    required String pelanggan,
    required String nomorWA,
    required bool dicek,
    required double total,
    required List> items,
  }) async {
    final db = await database;
    return db.insert('po_tersimpan', {
      'nomor': nomor,
      'tanggal': tanggal,
      'pelanggan': pelanggan,
      'nomor_wa': nomorWA,
      'dicek': dicek ? 1 : 0,
      'total': total,
      'items_json': jsonEncode(items),
    });
  }

  Future<int> updatePo({
    required int id,
    required String tanggal,
    required String pelanggan,
    required String nomorWA,
    required bool dicek,
    required double total,
    required List> items,
  }) async {
    final db = await database;
    return db.update(
      'po_tersimpan',
      {
        'tanggal': tanggal,
        'pelanggan': pelanggan,
        'nomor_wa': nomorWA,
        'dicek': dicek ? 1 : 0,
        'total': total,
        'items_json': jsonEncode(items),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List>> muatSemuaPo() async {
    final db = await database;
    final rows = await db.query('po_tersimpan', orderBy: 'id ASC');
    final hasil = >[];
    for (final r in rows) {
      List> items = [];
      try {
        final decoded = jsonDecode('${r['items_json']}');
        if (decoded is List) {
          items = decoded
              .whereType()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
      hasil.add({
        'id': r['id'],
        'nomor': r['nomor'] ?? '',
        'tanggal': r['tanggal'] ?? '',
        'pelanggan': r['pelanggan'] ?? '',
        'nomorWA': r['nomor_wa'] ?? '',
        'dicek': r['dicek'] ?? 0,
        'total': (r['total'] as num?)?.toDouble() ?? 0.0,
        'items': items,
      });
    }
    return hasil;
  }

  Future<int> hapusPo(int id) async {
    final db = await database;
    return db.delete('po_tersimpan', where: 'id = ?', whereArgs: [id]);
  }

  // --- ALIAS COPAS ---

  Future<void> simpanAliasCopas({
    required String namaCopas,
    required String kodeBarang,
  }) async {
    final db = await database;
    await db.insert(
      'alias_copas',
      {
        'nama_copas': namaCopas.trim().toLowerCase(),
        'kode_barang': kodeBarang.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future> muatAliasCopas() async {
    final db = await database;
    final rows = await db.query('alias_copas');
    final map = <String, String>{};
    for (final r in rows) {
      final k = '${r['nama_copas'] ?? ''}'.trim();
      final v = '${r['kode_barang'] ?? ''}'.trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        map[k] = v;
      }
    }
    return map;
  }
}

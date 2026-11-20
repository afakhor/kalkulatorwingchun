import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'po_database.g.dart';

// ===== TABEL 1: PO tersimpan (1 baris = 1 PO) =====
class PoTersimpan extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nomor => text()();
  TextColumn get tanggal => text()();
  RealColumn get total => real()();
  IntColumn get dibuatPada => integer()(); // millisSinceEpoch, untuk urut terbaru dulu
}

// ===== TABEL 2: step / item di dalam 1 PO =====
class PoItemTersimpan extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get poId => integer().references(PoTersimpan, #id)();
  TextColumn get item => text()();
  TextColumn get rumus => text()();
  RealColumn get harga => real()();
  RealColumn get qty => real()();
  RealColumn get jumlah => real()();
  IntColumn get urutan => integer()();
}

// ===== TABEL 3: riwayat PO (Simpan / Revisi) =====
class RiwayatPo extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nomor => text()();
  TextColumn get tanggal => text()();
  TextColumn get aksi => text()();
  RealColumn get total => real()();
  TextColumn get ringkasan => text()();
  IntColumn get dibuatPada => integer()();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'po_kalkulator.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

@DriftDatabase(tables: [PoTersimpan, PoItemTersimpan, RiwayatPo])
class PoDatabase extends _$PoDatabase {
  PoDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ===== PO =====
  Future<List<Map<String, dynamic>>> muatSemuaPo() async {
    final rows = await (select(poTersimpan)
          ..orderBy([(t) => OrderingTerm(expression: t.dibuatPada, mode: OrderingMode.desc)]))
        .get();
    final hasil = <Map<String, dynamic>>[];
    for (final r in rows) {
      final items = await (select(poItemTersimpan)
            ..where((t) => t.poId.equals(r.id))
            ..orderBy([(t) => OrderingTerm(expression: t.urutan)]))
          .get();
      hasil.add({
        "id": r.id,
        "nomor": r.nomor,
        "tanggal": r.tanggal,
        "total": r.total,
        "items": items
            .map((e) => {
                  "item": e.item,
                  "rumus": e.rumus,
                  "harga": e.harga,
                  "qty": e.qty,
                  "jumlah": e.jumlah,
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
    final id = await into(poTersimpan).insert(PoTersimpanCompanion(
      nomor: Value(nomor),
      tanggal: Value(tanggal),
      total: Value(total),
      dibuatPada: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    await _tulisItems(id, items);
    return id;
  }

  Future<void> updatePo({
    required int id,
    required String tanggal,
    required double total,
    required List<Map<String, dynamic>> items,
  }) async {
    await (update(poTersimpan)..where((t) => t.id.equals(id)))
        .write(PoTersimpanCompanion(tanggal: Value(tanggal), total: Value(total)));
    await (delete(poItemTersimpan)..where((t) => t.poId.equals(id))).go();
    await _tulisItems(id, items);
  }

  Future<void> hapusPo(int id) async {
    await (delete(poItemTersimpan)..where((t) => t.poId.equals(id))).go();
    await (delete(poTersimpan)..where((t) => t.id.equals(id))).go();
  }

  Future<void> _tulisItems(int poId, List<Map<String, dynamic>> items) async {
    for (var k = 0; k < items.length; k++) {
      final e = items[k];
      await into(poItemTersimpan).insert(PoItemTersimpanCompanion(
        poId: Value(poId),
        item: Value("${e["item"]}"),
        rumus: Value("${e["rumus"] ?? ""}"),
        harga: Value((e["harga"] as num?)?.toDouble() ?? 0),
        qty: Value((e["qty"] as num?)?.toDouble() ?? 0),
        jumlah: Value((e["jumlah"] as num?)?.toDouble() ?? 0),
        urutan: Value(k),
      ));
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
    return into(riwayatPo).insert(RiwayatPoCompanion(
      nomor: Value(nomor),
      tanggal: Value(tanggal),
      aksi: Value(aksi),
      total: Value(total),
      ringkasan: Value(ringkasan),
      dibuatPada: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<List<Map<String, dynamic>>> muatSemuaRiwayat() async {
    final rows = await (select(riwayatPo)
          ..orderBy([(t) => OrderingTerm(expression: t.dibuatPada, mode: OrderingMode.desc)]))
        .get();
    return rows
        .map((r) => {
              "id": r.id,
              "nomor": r.nomor,
              "tanggal": r.tanggal,
              "aksi": r.aksi,
              "total": r.total,
              "ringkasan": r.ringkasan,
            })
        .toList();
  }

  Future<void> hapusRiwayat(int id) async {
    await (delete(riwayatPo)..where((t) => t.id.equals(id))).go();
  }

  Future<void> hapusSemuaRiwayat() async {
    await delete(riwayatPo).go();
  }
}

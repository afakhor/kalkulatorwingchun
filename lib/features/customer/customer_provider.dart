import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/po_database.dart';
import '../po/po_models.dart';

// Daftar Orang - cari by namaOrang, bukan ID, karena P2P ingatnya nama orang
// Tersimpan persisten di PoDatabase (SQLite)
class CustomerNotifier extends Notifier<List<Customer>> {
  final PoDatabase _db = PoDatabase();

  @override
  List<Customer> build() {
    Future.microtask(_muatDariDb);
    return [];
  }

  Future<void> _muatDariDb() async {
    try {
      final rows = await _db.muatDataPelanggan();
      final daftar = rows
          .map(
            (r) => Customer(
              id: r['id'] ?? '',
              namaOrang: r['namaOrang'] ?? '',
              nomorWA: r['nomorWA'] ?? '',
            ),
          )
          .toList();
      if (ref.mounted) {
        state = daftar;
      }
    } catch (_) {}
  }

  Future<void> tambah(Customer c) async {
    final namaTrim = c.namaOrang.trim();
    if (namaTrim.isEmpty) return;
    final item = Customer(
      id: c.id.trim().isEmpty
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : c.id.trim(),
      namaOrang: namaTrim,
      nomorWA: c.nomorWA.trim(),
    );

    final idxLama = state.indexWhere(
      (e) => e.id == item.id || e.namaOrang.toLowerCase() == namaTrim.toLowerCase(),
    );
    if (idxLama >= 0) {
      final salinan = [...state];
      salinan[idxLama] = item;
      state = salinan;
    } else {
      state = [...state, item];
    }

    try {
      await _db.simpanDataPelanggan(
        id: item.id,
        namaOrang: item.namaOrang,
        nomorWA: item.nomorWA,
      );
    } catch (_) {}
  }

  Future<void> hapus(String id) async {
    Customer? target;
    for (final e in state) {
      if (e.id == id) {
        target = e;
        break;
      }
    }
    state = state.where((e) => e.id != id).toList();

    if (target != null) {
      try {
        await _db.hapusDataPelanggan(
          id: target.id,
          namaOrang: target.namaOrang,
        );
      } catch (_) {}
    }
  }

  List<Customer> cariPO(String keyword) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return state;
    return state.where((c) => c.namaOrang.toLowerCase().contains(k)).toList();
  }
}

final customerProvider =
    NotifierProvider<CustomerNotifier, List<Customer>>(CustomerNotifier.new);

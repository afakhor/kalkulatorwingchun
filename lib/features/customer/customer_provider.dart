import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'po_models.dart';

// Daftar Orang - cari by namaOrang, bukan ID, karena P2P ingatnya nama orang
// TANPA DUMMY - list kosong sampai user tambah orang beneran
class CustomerNotifier extends Notifier<List<Customer>> {
  @override
  List<Customer> build() => [];

  void tambah(Customer c) => state = [...state, c];

  void hapus(String id) => state = state.where((e) => e.id != id).toList();

  List<Customer> cariPO(String keyword) {
    final k = keyword.toLowerCase();
    return state.where((c) => c.namaOrang.toLowerCase().contains(k)).toList();
  }
}

final customerProvider = NotifierProvider<CustomerNotifier, List<Customer>>(CustomerNotifier.new);

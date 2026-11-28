import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../calculator/po_calculator.dart';
import 'po_models.dart';

// DILARANG setState untuk logika PO - hanya Riverpod
class PoNotifier extends Notifier<PoOrder> {
  @override
  PoOrder build() => PoOrder(
        id: 'PO-2026-001',
        customer: const Customer(id: 'c1', namaOrang: '', nomorWA: ''),
        tanggal: DateTime.now(),
      );

  void tambahItem(PoItem i) =>
      state = state.copyWith(items: [...state.items, i]);

  void hapusItem(int idx) {
    if (idx < 0 || idx >= state.items.length) return;
    final l = [...state.items]..removeAt(idx);
    state = state.copyWith(items: l);
  }

  void updateQty(int idx, int q) {
    if (idx < 0 || idx >= state.items.length) return;
    final l = [...state.items];
    l[idx] = l[idx].copyWith(qty: q);
    state = state.copyWith(items: l);
  }

  void bersihkan() {
    state = state.copyWith(items: []);
  }

  HasilHitung hitungTotal() => hitungPO(state);

  void ubahStatus(PoStatus s) {
    state = state.copyWith(status: s);
  }
}

final poProvider = NotifierProvider<PoNotifier, PoOrder>(PoNotifier.new);

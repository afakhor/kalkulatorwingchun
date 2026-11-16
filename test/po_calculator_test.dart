import 'package:flutter_test/flutter_test.dart';
import 'package:po_kalkulator_p2p/features/calculator/po_calculator.dart';
import 'package:po_kalkulator_p2p/features/po/po_models.dart';

void main() {
  test('hitungPO', () {
    final po = PoOrder(
      id: 'PO-2026-001',
      customer: const Customer(id: '1', namaOrang: 'Budi', nomorWA: '081'),
      tanggal: DateTime(2026, 11, 16),
      items: const [PoItem(namaBarang: 'semen', qty: 2, hargaSatuan: 50000)],
      ongkir: 5000,
      dp: 20000,
    );
    final h = hitungPO(po);
    expect(h.subtotal, 100000);
    expect(h.sisaBayar, h.totalAkhir - 20000);
  });
}

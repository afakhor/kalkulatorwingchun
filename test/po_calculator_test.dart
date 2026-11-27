import 'package:flutter_test/flutter_test.dart';
import 'package:po_kalkulator_p2p/core/formatter.dart';
import 'package:po_kalkulator_p2p/features/calculator/parse_cepat.dart';
import 'package:po_kalkulator_p2p/features/calculator/po_calculator.dart';
import 'package:po_kalkulator_p2p/features/po/po_models.dart';

void main() {
  test('hitungPO menghitung subtotal, diskon, ongkir, totalAkhir, sisaBayar',
      () {
    final po = PoOrder(
      id: 'PO-001',
      tanggal: DateTime(2026, 1, 1),
      customer: const Customer(id: '1', namaOrang: 'Budi', nomorWA: '08123'),
      items: const [
        PoItem(namaBarang: 'Semen', qty: 10, hargaSatuan: 50000, satuan: 'sak'),
        PoItem(namaBarang: 'Besi', qty: 5, hargaSatuan: 80000, satuan: 'btg'),
      ],
      diskonTotal: 50000,
      ongkir: 20000,
      dp: 200000,
    );
    final h = hitungPO(po);
    expect(h.subtotal, 900000);
    expect(h.totalAkhir, 870000);
    expect(h.sisaBayar, 670000);
  });

  test('parseInputCepat mengurai format umum', () {
    final it = parseInputCepat('2 x Semen 50000');
    expect(it, isNotNull);
    expect(it!.qty, 2);
    expect(it.namaBarang, 'Semen');
    expect(it.hargaSatuan, 50000);
  });

  test('formatRupiah memformat ribuan dengan benar', () {
    expect(formatRupiah(150000), 'Rp 150.000');
  });
}

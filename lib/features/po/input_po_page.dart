import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'po_provider.dart';
import 'parse_cepat.dart';
import '../../core/formatter.dart';
import '../../core/theme.dart';

class HalamanInputPO extends ConsumerStatefulWidget {
  const HalamanInputPO({super.key});
  @override
  ConsumerState<HalamanInputPO> createState() => _S();
}

class _S extends ConsumerState<HalamanInputPO> {
  final _ctrl = TextEditingController();
  // setState HANYA untuk animasi keyboard / fokus - bukan logika PO
  bool _fokus = false;

  @override
  Widget build(BuildContext context) {
    final po = ref.watch(poProvider);
    final hasil = ref.read(poProvider.notifier).hitungTotal();
    return Scaffold(
      appBar: AppBar(title: Text('PO Baru', style: AppTheme.judulTangan(28))),
      body: LayoutBuilder(
        builder: (c, cons) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tulis cepat: 2x semen 50kg 50rb', style: AppTheme.judulTangan(22)),
              TextField(
                controller: _ctrl,
                onTap: () => setState(() => _fokus = true),
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(hintText: '2x kaos 50rb', border: OutlineInputBorder()),
                onSubmitted: (v) {
                  final item = parseInputCepat(v);
                  if (item != null) {
                    ref.read(poProvider.notifier).tambahItem(item);
                    HapticFeedback.lightImpact();
                    _ctrl.clear();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pakai form manual: qty, nama, harga')),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              ...po.items.asMap().entries.map((e) => ListTile(
                    title: Text(e.value.namaBarang),
                    subtitle: Text('${e.value.qty} x ${formatRupiah(e.value.hargaSatuan)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () => ref.read(poProvider.notifier).updateQty(e.key, (e.value.qty - 1).clamp(0, 999)),
                        ),
                        Text('${e.value.qty}'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => ref.read(poProvider.notifier).updateQty(e.key, e.value.qty + 1),
                        ),
                      ],
                    ),
                  )),
              const Divider(),
              Text('Subtotal: ${formatRupiah(hasil.subtotal)}'),
              Text('Total: ${formatRupiah(hasil.totalAkhir)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Sisa Bayar: ${formatRupiah(hasil.sisaBayar)}'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => debugPrint('kirimPO -> buatPDF + share_plus + status=Dikirim'),
                child: const Text('Kirim ke WA'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

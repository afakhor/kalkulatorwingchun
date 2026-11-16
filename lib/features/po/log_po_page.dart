import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'po_models.dart';

// Log PO: Last PO, Hari Ini, Sebulan, Checklist Pending / Belum Dikirim / Sudah Dikirim + Catatan
// TANPA DUMMY - list kosong sampai user simpan PO beneran
class LogPOPage extends ConsumerStatefulWidget {
  const LogPOPage({super.key});
  @override
  ConsumerState<LogPOPage> createState() => _S();
}

class _S extends ConsumerState<LogPOPage> {
  String filter = 'Semua'; // Semua / Pending / Belum Dikirim / Sudah Dikirim
  String tab = 'Hari Ini'; // Last PO / Hari Ini / Sebulan
  final List<PoOrder> semuaPO = []; // diisi dari Hive, bukan dummy

  @override
  Widget build(BuildContext context) {
    final tampil = semuaPO.where((p) {
      if (filter == 'Semua') return true;
      if (filter == 'Pending') return p.status == PoStatus.draft;
      if (filter == 'Belum Dikirim') return p.status == PoStatus.dikirim;
      return p.status == PoStatus.lunas;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Log PO')),
      body: Column(
        children: [
          Row(
            children: ['Last PO', 'Hari Ini', 'Sebulan']
                .map((t) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(label: Text(t), selected: tab == t, onSelected: (_) => setState(() => tab = t)),
                    ))
                .toList(),
          ),
          Row(
            children: ['Semua', 'Pending', 'Belum Dikirim', 'Sudah Dikirim']
                .map((f) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: FilterChip(label: Text(f), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
                    ))
                .toList(),
          ),
          Expanded(
            child: tampil.isEmpty
                ? const Center(child: Text('Belum ada PO'))
                : ListView.builder(
                    itemCount: tampil.length,
                    itemBuilder: (_, i) {
                      final po = tampil[i];
                      return ListTile(
                        title: Text('${po.id} - ${po.customer.namaOrang}'),
                        subtitle: Text('Catatan: ${po.catatan}\nStatus: ${po.status.name}'),
                        trailing: DropdownButton<PoStatus>(
                          value: po.status,
                          items: PoStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
                          onChanged: (s) {
                            if (s != null) setState(() => semuaPO[i] = po.copyWith(status: s));
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class HomeDaftarPO extends StatelessWidget {
  const HomeDaftarPO({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('PoKalkulator P2P', style: AppTheme.judulTangan(28))),
        body: const Center(child: Text('Belum ada PO - klik PO Baru')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go('/po/baru'),
          label: const Text('PO Baru'),
          icon: const Icon(Icons.add),
        ),
      );
}

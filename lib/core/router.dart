import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/po/home_daftar_po.dart';
import '../features/po/input_po_page.dart';
import '../features/po/detail_po_page.dart';
import '../features/customer/daftar_orang_page.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeDaftarPO()),
      GoRoute(path: '/po/baru', builder: (_, __) => const HalamanInputPO()),
      GoRoute(path: '/po/:id', builder: (_, s) => DetailPO(id: s.pathParameters['id']!)),
      GoRoute(path: '/customer', builder: (_, __) => const DaftarOrangPage()),
    ]));

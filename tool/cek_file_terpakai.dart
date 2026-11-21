// ignore_for_file: avoid_print
// tool/cek_file_terpakai.dart
// IKHTISAR FILE TERPAKAI — jalan di CI (GitHub Actions) & di laptop.
// Cara jalan: dart tool/cek_file_terpakai.dart
//
// Cara kerja: baca semua file .dart di lib/ dan test/, lalu telusuri
// import / export / part dari titik masuk (lib/main.dart + semua file test).
// File yang terjangkau dari titik masuk = TERPAKAI.
// File yang tidak terjangkau = TIDAK TERPAKAI (kandidat hapus).
//
// Script ini HANYA menampilkan ikhtisar, TIDAK menghapus file apa-apa,
// dan TIDAK membuat CI gagal (exit 0 walau ada file tidak terpakai).
// Kalau mau CI gagal bila ada file tidak terpakai, ubah
// _gagalBilaAdaSampah di bawah jadi true.

import 'dart:io';

const _gagalBilaAdaSampah = false;

// Normalisasi path jadi bentuk folder/file.dart (buang ./ dan ../).
String _norm(String p) {
  final parts = <String>[];
  for (final seg in p.replaceAll('\\', '/').split('/')) {
    if (seg == '.' || seg.isEmpty) continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

// Baca nama package dari pubspec.yaml (misal po_kalkulator_p2p).
String _namaPackage() {
  final pub = File('pubspec.yaml');
  if (!pub.existsSync()) return 'po_kalkulator_p2p';
  for (final line in pub.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('name:')) return t.substring('name:'.length).trim();
  }
  return 'po_kalkulator_p2p';
}

// Buang komentar // dan /* */ supaya import yang dikomentari tidak kehitung.
String _buangKomentar(String text) {
  text = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  text = text.replaceAll(RegExp(r'//.*'), '');
  return text;
}

// Ubah sebuah import jadi path file. null = bukan file project (dart: / package luar).
String? _resolve(String dari, String uri, String namaPkg) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final pkg = rest.substring(0, slash);
    if (pkg != namaPkg) return null; // package luar (flutter, riverpod, dst) -> abaikan
    return _norm('lib/${rest.substring(slash + 1)}');
  }
  // Import relatif: gabung dengan folder file yang meng-import.
  final dir = dari.contains('/') ? dari.substring(0, dari.lastIndexOf('/') + 1) : '';
  return _norm('$dir$uri');
}

void main() {
  final namaPkg = _namaPackage();

  // 1. Kumpulkan semua file .dart di lib/ dan test/.
  final files = <String>{};
  for (final dirName in ['lib', 'test']) {
    final dir = Directory(dirName);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) files.add(_norm(f.path));
    }
  }

  // 2. Bangun graf: file -> file yang di-import-nya, dan sebaliknya.
  final importsOf = <String, Set<String>>{};
  final importedBy = <String, Set<String>>{};
  final takKetemu = <String, Set<String>>{};
  for (final f in files) {
    importsOf[f] = {};
    importedBy[f] = {};
  }
  final pola = RegExp(r'''(?:import|export|part)\s+['"]([^'"]+)['"]''');
  for (final f in files) {
    final text = _buangKomentar(File(f).readAsStringSync());
    for (final m in pola.allMatches(text)) {
      final target = _resolve(f, m.group(1)!, namaPkg);
      if (target == null) continue;
      if (files.contains(target)) {
        importsOf[f]!.add(target);
        importedBy[target]!.add(f);
      } else {
        takKetemu.putIfAbsent(f, () => {}).add(m.group(1)!);
      }
    }
  }

  // 3. Titik masuk: lib/main.dart + semua file test.
  final entry = files.where((f) => f == 'lib/main.dart' || f.startsWith('test/')).toSet();

  // 4. Telusuri dari titik masuk.
  final terpakai = <String>{};
  final antri = [...entry];
  while (antri.isNotEmpty) {
    final cur = antri.removeLast();
    if (!terpakai.add(cur)) continue;
    for (final dep in importsOf[cur] ?? {}) {
      if (!terpakai.contains(dep)) antri.add(dep);
    }
  }
  final tidakTerpakai = files.difference(terpakai).toList()..sort();
  final terpakaiUrut = terpakai.toList()..sort();

  // 5. Cetak ikhtisar.
  print('==================================================');
  print('IKHTISAR FILE TERPAKAI (dari lib/main.dart + test)');
  print('Package: $namaPkg | Total file .dart: ${files.length}');
  print('==================================================');
  print('');
  print('--- TERPAKAI (${terpakaiUrut.length} file) ---');
  for (final f in terpakaiUrut) {
    print('  ✅ $f');
  }
  print('');
  print('--- TIDAK TERPAKAI (${tidakTerpakai.length} file) ---');
  print('    (tidak terjangkau dari main.dart / test = kandidat hapus,');
  print('     TAPI cek dulu dengan Ctrl+Shift+F sebelum menghapus!)');
  for (final f in tidakTerpakai) {
    print('  ❌ $f');
    final pengimport = importedBy[f]!;
    if (pengimport.isNotEmpty) {
      print('       diimport oleh: ${pengimport.join(", ")}');
    } else {
      print('       tidak diimport siapa-siapa');
    }
  }
  print('');
  if (takKetemu.isNotEmpty) {
    print('--- IMPORT PUTUS (${takKetemu.length} file meng-import file yang tidak ada) ---');
    for (final e in takKetemu.entries) {
      print('  ⚠️ ${e.key} -> ${e.value.join(", ")}');
    }
    print('');
  }
  if (tidakTerpakai.isNotEmpty && _gagalBilaAdaSampah) exit(1);
}
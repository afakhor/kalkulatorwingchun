import 'dart:convert';
import 'dart:io';

Future<File> backup(List<Map<String, dynamic>> semuaPO, Directory dir) async {
  final f = File('${dir.path}/backup_po.json');
  await f.writeAsString(jsonEncode(semuaPO));
  return f; // share ke Drive / WA manual
}

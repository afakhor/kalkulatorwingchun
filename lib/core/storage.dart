import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Hive: semua PoOrder, Customer, produkFavorit
// SecureStorage: namaToko, nomorWA_Toko, tandaTangan
// SharedPreferences: mataUang = Rp, formatTanggal
class AppStorage {
  static const _secure = FlutterSecureStorage();
  static Future<void> simpanNamaToko(String v) => _secure.write(key: 'namaToko', value: v);
  static Future<String?> bacaNamaToko() => _secure.read(key: 'namaToko');
  static Future<void> simpanWAToko(String v) => _secure.write(key: 'nomorWA_Toko', value: v);
  static Future<String?> bacaWAToko() => _secure.read(key: 'nomorWA_Toko');
  static Future<void> simpanMataUang(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('mataUang', v);
  }
  static Future<Box> bukaBox(String nama) => Hive.openBox(nama);
}

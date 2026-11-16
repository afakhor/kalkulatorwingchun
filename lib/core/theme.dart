import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF8E7),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A1A1A)),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
      );
  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.dark),
      );
  static TextStyle judulTangan(double s) => GoogleFonts.caveat(fontSize: s, fontWeight: FontWeight.bold);
}

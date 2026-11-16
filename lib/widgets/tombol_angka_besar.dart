import 'package:flutter/material.dart';

// Keyboard angka besar - tombol gede gampang dipencet, rasa kalkulator
class TombolAngkaBesar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? warna;
  const TombolAngkaBesar({super.key, required this.label, required this.onTap, this.warna});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: warna, textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}

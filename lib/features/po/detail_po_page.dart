import 'package:flutter/material.dart';

class DetailPO extends StatelessWidget {
  final String id;
  const DetailPO({super.key, required this.id});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(id)),
        body: Center(child: Text('Detail $id - template Nota / Chat / Kalkulator')),
      );
}

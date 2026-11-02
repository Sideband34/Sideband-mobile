import 'package:flutter/material.dart';

void main() => runApp(const SidebandApp());

class SidebandApp extends StatelessWidget {
  const SidebandApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: Center(child: Text('Sideband'))));
}

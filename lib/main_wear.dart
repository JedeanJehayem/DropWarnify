// lib/main_wear.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 necessário para travar orientação
import 'screens/home/home_screen_wear.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔒 TRAVA O APP DO RELÓGIO EM PORTRAIT (em pé)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const DropWarnifyWearApp());
}

class DropWarnifyWearApp extends StatelessWidget {
  const DropWarnifyWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DropWarnify (Wear)',
      theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.dark),
      home: const HomeScreenWear(),
    );
  }
}

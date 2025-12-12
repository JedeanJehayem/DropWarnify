// lib/main_mobile.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 necessário para travar orientação
import 'screens/home/home_screen_mobile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔒 TRAVA O CELULAR EM MODO PORTRAIT (em pé)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const DropWarnifyMobileApp());
}

class DropWarnifyMobileApp extends StatelessWidget {
  const DropWarnifyMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DropWarnify (Mobile)',
      theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.dark),
      home: const HomeScreenMobile(),
    );
  }
}

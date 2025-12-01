import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dropwarnify/screens/home/home_screen.dart';
import 'package:dropwarnify/services/wear_contacts_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔵 inicializa o bridge para registrar o MethodCallHandler
  WearContactsBridge.instance;

  // 🔵 Permite que o app ocupe toda a tela (incluindo área da câmera/notch)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 🔵 Deixa a status bar transparente e os ícones brancos
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const DropWarnifyApp());
}

class DropWarnifyApp extends StatelessWidget {
  const DropWarnifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DropWarnify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

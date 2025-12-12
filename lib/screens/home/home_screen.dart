// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:dropwarnify/utils/responsive.dart';

import 'home_screen_mobile.dart';
import 'home_screen_wear.dart';

/// Wrapper simples que decide qual Home mostrar:
/// - Celular: HomeScreenMobile
/// - Relógio (Wear): HomeScreenWear
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (isWearDevice(context)) {
      return const HomeScreenWear();
    } else {
      return const HomeScreenMobile();
    }
  }
}

// lib/utils/responsive.dart
import 'package:flutter/widgets.dart';

/// Considera "wearable" quando a menor dimensão da tela é < 300.
/// Único lugar onde esse número mágico aparece.
bool isWearDevice(BuildContext context) {
  final shortestSide = MediaQuery.of(context).size.shortestSide;
  return shortestSide < 300;
}

/// Se quiser, já deixa esse helper também:
bool isPhoneOrTablet(BuildContext context) => !isWearDevice(context);

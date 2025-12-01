import 'package:flutter/services.dart';

class WearFallServiceBridge {
  static const MethodChannel _channel = MethodChannel(
    'br.com.dropwarnify/wear_fall_service',
  );

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startService');
    } catch (e) {
      // loga se quiser
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopService');
    } catch (e) {
      // loga se quiser
    }
  }
}

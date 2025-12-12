import 'package:flutter/services.dart';

class WearFallServiceBridge {
  static const MethodChannel _channel = MethodChannel(
    'br.com.dropwarnify/wear_service', // mesmo nome do SERVICE_CHANNEL
  );

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('start_fall_service'); // mesmo nome do método
    } catch (e) {
      // opcional: print(e);
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop_fall_service');
    } catch (e) {
      // opcional: print(e);
    }
  }
}

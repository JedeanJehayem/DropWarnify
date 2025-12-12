import 'package:flutter/services.dart';

class MHubBridge {
  static const MethodChannel _channel = MethodChannel('plugin');

  Future<void> start({required String ipAddress, required int port}) async {
    await _channel.invokeMethod('startMobileHub', {
      'ipAddress': ipAddress,
      'port': port,
    });
  }

  Future<bool> isStarted() async {
    final result = await _channel.invokeMethod<bool>('isMobileHubStarted');
    return result ?? false;
  }

  Future<void> stop() async {
    await _channel.invokeMethod('stopMobileHub');
  }
}

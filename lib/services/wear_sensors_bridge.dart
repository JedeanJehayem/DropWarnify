import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'package:dropwarnify/models/watch_sensor_snapshot.dart';

class WearSensorsBridge {
  WearSensorsBridge._() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final WearSensorsBridge instance = WearSensorsBridge._();

  static const MethodChannel _channel = MethodChannel(
    'br.com.dropwarnify/wear_sensors',
  );

  final StreamController<WatchSensorSnapshot> _sensorStreamController =
      StreamController<WatchSensorSnapshot>.broadcast();

  Stream<WatchSensorSnapshot> get sensorStream =>
      _sensorStreamController.stream;

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'onWatchSensorSnapshot') {
      final jsonStr = call.arguments as String?;
      if (jsonStr == null || jsonStr.isEmpty) return null;

      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final snapshot = WatchSensorSnapshot.fromJson(map);
        _sensorStreamController.add(snapshot);
      } catch (e, st) {
        debugPrint('WearSensorsBridge: erro ao parsear snapshot: $e\n$st');
      }
    }

    return null;
  }
}

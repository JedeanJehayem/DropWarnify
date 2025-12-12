import 'dart:convert';

class WatchSensorSnapshot {
  final DateTime timestamp;
  final String origin;
  final double magnitudeG;
  final double accelX;
  final double accelY;
  final double accelZ;

  // Giroscópio (opcionais – nem sempre virão preenchidos)
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;

  /// Velocidade angular total |ω| (rad/s) enviada pelo relógio
  final double? gyroTotal;

  WatchSensorSnapshot({
    required this.timestamp,
    required this.origin,
    required this.magnitudeG,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.gyroTotal,
  });

  factory WatchSensorSnapshot.fromJson(Map<String, dynamic> json) {
    return WatchSensorSnapshot(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      origin: json['origin'] as String? ?? 'watch-sensor',
      magnitudeG: (json['magnitudeG'] as num).toDouble(),
      accelX: (json['accelX'] as num).toDouble(),
      accelY: (json['accelY'] as num).toDouble(),
      accelZ: (json['accelZ'] as num).toDouble(),
      gyroX: (json['gyroX'] as num?)?.toDouble(),
      gyroY: (json['gyroY'] as num?)?.toDouble(),
      gyroZ: (json['gyroZ'] as num?)?.toDouble(),
      gyroTotal: (json['gyroTotal'] as num?)?.toDouble(),
    );
  }

  /// Helper se você tiver a string JSON crua (opcional, só se quiser)
  factory WatchSensorSnapshot.fromJsonString(String jsonStr) {
    final map = json.decode(jsonStr) as Map<String, dynamic>;
    return WatchSensorSnapshot.fromJson(map);
  }
}

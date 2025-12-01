import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Mesmo enum usado em toda a app
enum MovementType { normal, nearFall, fall }

/// Serviço que:
///  - escuta acelerômetro + giroscópio;
///  - calcula |a| e |ω|;
///  - aplica os limiares do TCC;
///  - dispara callbacks (fall / nearFall / onMovementChanged).
class WearSensorMonitor {
  // Subscrições dos sensores
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Leituras atuais
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;

  // Info derivada pública (para UI)
  double accelTotal = 0;
  double gyroTotal = 0;

  MovementType lastMovement = MovementType.normal;

  final void Function(MovementType movement)? onMovementChanged;
  final Future<void> Function()? onFall;
  final Future<void> Function()? onNearFall;

  DateTime _lastTriggerTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration cooldown;

  WearSensorMonitor({
    this.onMovementChanged,
    this.onFall,
    this.onNearFall,
    this.cooldown = const Duration(seconds: 3),
  });

  // ========= LÓGICA DE CÁLCULO =========

  double _calcularAceleracaoTotal(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  double _calcularVelocidadeAngularTotal(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  MovementType _detectarMovimento({
    required double accelTotal,
    required double gyroTotal,
  }) {
    const double g = 9.81;

    final double limiarQuedaAccel = 3 * g; // ~29.4
    const double limiarQuedaGyro = 150.0;

    final double limiarNearAccel = 2 * g; // ~19.6
    const double limiarNearGyro = 50.0;

    if (accelTotal >= limiarQuedaAccel && gyroTotal >= limiarQuedaGyro) {
      return MovementType.fall;
    }

    if (accelTotal >= limiarNearAccel && gyroTotal >= limiarNearGyro) {
      return MovementType.nearFall;
    }

    return MovementType.normal;
  }

  // ========= CONTROLE =========

  void start() {
    _accelSub = accelerometerEvents.listen((event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;
      _processNewSample();
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;
      _processNewSample();
    });
  }

  void _processNewSample() {
    accelTotal = _calcularAceleracaoTotal(_accelX, _accelY, _accelZ);
    gyroTotal = _calcularVelocidadeAngularTotal(_gyroX, _gyroY, _gyroZ);

    final movement = _detectarMovimento(
      accelTotal: accelTotal,
      gyroTotal: gyroTotal,
    );

    lastMovement = movement;
    onMovementChanged?.call(movement);

    _maybeTriggerCallbacks(movement);
  }

  void _maybeTriggerCallbacks(MovementType movement) {
    final now = DateTime.now();
    if (now.difference(_lastTriggerTime) < cooldown) return;

    if (movement == MovementType.fall && onFall != null) {
      _lastTriggerTime = now;
      onFall!();
    } else if (movement == MovementType.nearFall && onNearFall != null) {
      _lastTriggerTime = now;
      onNearFall!();
    }
  }

  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
  }
}

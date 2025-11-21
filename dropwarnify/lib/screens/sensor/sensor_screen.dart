import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum MovementType { normal, nearFall, fall }

class SensorScreen extends StatefulWidget {
  /// Callback chamado quando for detectada uma QUEDA real
  final Future<void> Function()? onFall;

  /// Callback chamado quando for detectada uma QUASE QUEDA
  final Future<void> Function()? onNearFall;

  const SensorScreen({super.key, this.onFall, this.onNearFall});

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  // Subscrições dos sensores
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Leituras atuais
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;

  // Info derivada
  double _accelTotal = 0;
  double _gyroTotal = 0;

  // Estado da detecção
  MovementType _lastMovement = MovementType.normal;
  String _statusTexto = 'Monitorando sensores em tempo real...';
  Color _statusColor = Colors.green.shade600;

  DateTime _lastTriggerTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cooldown = const Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _startListeningSensors();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    super.dispose();
  }

  // ========= LÓGICA DE CÁLCULO =========

  double _calcularAceleracaoTotal(double x, double y, double z) {
    // magnitude do vetor de aceleração
    return sqrt(x * x + y * y + z * z);
  }

  double _calcularVelocidadeAngularTotal(double x, double y, double z) {
    // magnitude do vetor de rotação
    return sqrt(x * x + y * y + z * z);
  }

  MovementType _detectarMovimento({
    required double accelTotal,
    required double gyroTotal,
  }) {
    // Limiar de QUEDA (baseado no que você colocou no TCC)
    // Queda: aceleração > 3g e giro > 150°/s
    // Quase queda: aceleração > 2g e giro > 50°/s (mas abaixo de queda)
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

  // ========= LISTENERS DOS SENSORES =========

  void _startListeningSensors() {
    _accelSub = accelerometerEvents.listen((AccelerometerEvent event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;
      _processNewSample();
    });

    _gyroSub = gyroscopeEvents.listen((GyroscopeEvent event) {
      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;
      _processNewSample();
    });
  }

  void _processNewSample() {
    // Recalcula as magnitudes
    final accelTotal = _calcularAceleracaoTotal(_accelX, _accelY, _accelZ);
    final gyroTotal = _calcularVelocidadeAngularTotal(_gyroX, _gyroY, _gyroZ);

    final movement = _detectarMovimento(
      accelTotal: accelTotal,
      gyroTotal: gyroTotal,
    );

    setState(() {
      _accelTotal = accelTotal;
      _gyroTotal = gyroTotal;
      _lastMovement = movement;

      switch (movement) {
        case MovementType.normal:
          _statusTexto = 'Movimento normal detectado.';
          _statusColor = Colors.green.shade600;
          break;
        case MovementType.nearFall:
          _statusTexto =
              'Quase queda detectada (desequilíbrio forte, mas sem impacto completo).';
          _statusColor = Colors.orange.shade600;
          break;
        case MovementType.fall:
          _statusTexto =
              'Possível QUEDA detectada! Verificando necessidade de alerta.';
          _statusColor = Colors.red.shade700;
          break;
      }
    });

    _maybeTriggerCallbacks(movement);
  }

  void _maybeTriggerCallbacks(MovementType movement) {
    final now = DateTime.now();
    if (now.difference(_lastTriggerTime) < _cooldown) {
      // ainda dentro do cooldown, ignora para não disparar vários eventos
      return;
    }

    if (movement == MovementType.fall && widget.onFall != null) {
      _lastTriggerTime = now;
      widget.onFall!();
    } else if (movement == MovementType.nearFall && widget.onNearFall != null) {
      _lastTriggerTime = now;
      widget.onNearFall!();
    }
  }

  // ========= UI =========

  @override
  Widget build(BuildContext context) {
    final themeBlue = Colors.blue.shade700;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sensores em tempo real',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: themeBlue,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _statusColor.withOpacity(0.15),
                        child: Icon(
                          _lastMovement == MovementType.fall
                              ? Icons.warning_amber_rounded
                              : (_lastMovement == MovementType.nearFall
                                    ? Icons.report_problem_rounded
                                    : Icons.check_circle),
                          color: _statusColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusTexto,
                          style: TextStyle(
                            fontSize: 14,
                            color: _statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Leituras numéricas só pra debug / estudo
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Leituras atuais dos sensores',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Acelerômetro (x, y, z): '
                        '${_accelX.toStringAsFixed(2)}, '
                        '${_accelY.toStringAsFixed(2)}, '
                        '${_accelZ.toStringAsFixed(2)}  m/s²',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aceleração total: ${_accelTotal.toStringAsFixed(2)} m/s²',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Giroscópio (x, y, z): '
                        '${_gyroX.toStringAsFixed(2)}, '
                        '${_gyroY.toStringAsFixed(2)}, '
                        '${_gyroZ.toStringAsFixed(2)}  °/s',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Velocidade angular total: ${_gyroTotal.toStringAsFixed(2)} °/s',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Os dados são analisados continuamente.\n'
                'Quedas e quase quedas disparam alertas no Home.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

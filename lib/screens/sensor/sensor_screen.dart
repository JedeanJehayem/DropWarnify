import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:dropwarnify/services/wear_sensor_monitor.dart';
import 'package:dropwarnify/utils/responsive.dart';
import 'package:dropwarnify/widgets/sensor/sensor_widgets.dart';

import 'package:dropwarnify/models/watch_sensor_snapshot.dart';
import 'package:dropwarnify/services/wear_sensors_bridge.dart';

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
  late WearSensorMonitor _monitor;

  // Leituras derivadas para exibir na UI
  double _accelTotal = 0;
  double _gyroTotal = 0;

  // Estado da detecção
  MovementType _lastMovement = MovementType.normal;
  String _statusTexto = 'Monitorando sensores em tempo real...';
  Color _statusColor = Colors.green;

  // Estamos usando dados do relógio?
  bool _usingWatchData = false;

  StreamSubscription<WatchSensorSnapshot>? _watchSensorSub;

  @override
  void initState() {
    super.initState();

    // Monitor local (funciona no relógio e no celular).
    _monitor = WearSensorMonitor(
      onMovementChanged: (movement) {
        // Se já estamos usando dados do relógio, não sobrescreve com o local.
        if (_usingWatchData) return;

        setState(() {
          _lastMovement = movement;
          _accelTotal = _monitor.accelTotal;
          _gyroTotal = _monitor.gyroTotal;

          switch (movement) {
            case MovementType.normal:
              _statusTexto =
                  'Movimento normal detectado.\nFonte: este dispositivo.';
              _statusColor = Colors.green.shade600;
              break;
            case MovementType.nearFall:
              _statusTexto =
                  'Quase queda detectada (desequilíbrio forte, mas sem impacto completo).\nFonte: este dispositivo.';
              _statusColor = Colors.orange.shade600;
              break;
            case MovementType.fall:
              _statusTexto =
                  'Possível QUEDA detectada! Verificando necessidade de alerta.\nFonte: este dispositivo.';
              _statusColor = Colors.red.shade700;
              break;
          }
        });
      },
      onFall: widget.onFall,
      onNearFall: widget.onNearFall,
      cooldown: const Duration(seconds: 3),
    );

    _monitor.start();

    // Stream de sensores do relógio (lado CELULAR).
    _watchSensorSub = WearSensorsBridge.instance.sensorStream.listen((
      snapshot,
    ) {
      setState(() {
        _usingWatchData = true;

        // magnitude em m/s² aproximado
        _accelTotal = snapshot.magnitudeG * 9.81;

        // gyroTotal vem do relógio em rad/s -> convertemos para °/s
        const radToDeg = 180 / pi;
        if (snapshot.gyroTotal != null) {
          _gyroTotal = snapshot.gyroTotal! * radToDeg;
        } else {
          // fallback: mantém valor do monitor local, se existir
          _gyroTotal = _monitor.gyroTotal;
        }

        _statusTexto =
            'Leituras em tempo real do relógio (Wear OS).\n'
            'magnitude ≈ ${snapshot.magnitudeG.toStringAsFixed(2)} g\n'
            'vel. angular ≈ ${_gyroTotal.toStringAsFixed(2)} °/s\n'
            'Fonte: relógio Wear OS.';
        _statusColor = Colors.blue.shade700;

        debugPrint(
          'SensorScreen: snapshot mag=${snapshot.magnitudeG}, '
          'gyroTotal(rad/s)=${snapshot.gyroTotal}, '
          'gyroTotal(°/s)=$_gyroTotal',
        );
        // Movimento lógico (queda/quase queda) continua vindo do lado nativo.
      });
    });
  }

  @override
  void dispose() {
    _watchSensorSub?.cancel();
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No relógio → layout redondinho
    if (isWearDevice(context)) {
      return SensorWatchLayout(
        lastMovement: _lastMovement,
        accelTotal: _accelTotal,
        gyroTotal: _gyroTotal,
        statusTexto: _statusTexto,
        statusColor: _statusColor,
      );
    }

    // No celular → layout de telefone
    return SensorPhoneLayout(
      lastMovement: _lastMovement,
      accelTotal: _accelTotal,
      gyroTotal: _gyroTotal,
      statusTexto: _statusTexto,
      statusColor: _statusColor,
    );
  }
}

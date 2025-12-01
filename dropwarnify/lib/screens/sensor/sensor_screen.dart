import 'package:flutter/material.dart';
import 'package:dropwarnify/services/wear_sensor_monitor.dart';

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
  Color _statusColor = Colors.green.shade600;

  @override
  void initState() {
    super.initState();

    _monitor = WearSensorMonitor(
      // callbacks de detecção de movimento
      onMovementChanged: (movement) {
        setState(() {
          _lastMovement = movement;
          _accelTotal = _monitor.accelTotal;
          _gyroTotal = _monitor.gyroTotal;

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
      },
      // repassa os callbacks externos (Home) para o serviço
      onFall: widget.onFall,
      onNearFall: widget.onNearFall,
      cooldown: const Duration(seconds: 3),
    );

    _monitor.start();
  }

  @override
  void dispose() {
    _monitor.dispose();
    super.dispose();
  }

  // ========= UI PARA CELULAR =========

  Widget _buildPhoneLayout(BuildContext context) {
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
                        'Aceleração total (|a|): '
                        '${_accelTotal.toStringAsFixed(2)} m/s²',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Velocidade angular total (|ω|): '
                        '${_gyroTotal.toStringAsFixed(2)} °/s',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Último tipo de movimento: '
                        '${_lastMovement == MovementType.fall
                            ? 'QUEDA'
                            : _lastMovement == MovementType.nearFall
                            ? 'QUASE QUEDA'
                            : 'normal'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Os dados são analisados continuamente.\n'
                'Quedas e quase quedas podem disparar callbacks para a tela inicial.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========= UI PARA RELÓGIO =========

  Widget _buildWatchLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;
    final double scale = (shortestSide / 320).clamp(0.75, 1.0).toDouble();

    final bgColor = Colors.black;
    final textColor = Colors.white70;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 10 * scale,
              vertical: 8 * scale,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status compacto
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8 * scale,
                    vertical: 6 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14 * scale),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18 * scale,
                        backgroundColor: _statusColor.withOpacity(0.2),
                        child: Icon(
                          _lastMovement == MovementType.fall
                              ? Icons.warning_amber_rounded
                              : (_lastMovement == MovementType.nearFall
                                    ? Icons.report_problem_rounded
                                    : Icons.check_circle),
                          color: _statusColor,
                          size: 18 * scale,
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Text(
                          _statusTexto,
                          style: TextStyle(
                            fontSize: 9 * scale,
                            color: _statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 10 * scale),

                // Leituras resumidas
                Container(
                  padding: EdgeInsets.all(8 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12 * scale),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accel: ${_accelTotal.toStringAsFixed(1)} m/s²',
                        style: TextStyle(fontSize: 9 * scale, color: textColor),
                      ),
                      SizedBox(height: 3 * scale),
                      Text(
                        'Gyro: ${_gyroTotal.toStringAsFixed(1)} °/s',
                        style: TextStyle(fontSize: 9 * scale, color: textColor),
                      ),
                      SizedBox(height: 6 * scale),
                      Text(
                        'Tela de debug dos sensores\n'
                        'para testes no emulador.',
                        style: TextStyle(
                          fontSize: 8 * scale,
                          color: textColor.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 12 * scale),

                // Botão de voltar
                SizedBox(
                  width: 110 * scale,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      padding: EdgeInsets.symmetric(
                        vertical: 6 * scale,
                        horizontal: 8 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20 * scale),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Voltar',
                      style: TextStyle(
                        fontSize: 10 * scale,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========= ROOT BUILD =========

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;

    if (isWatch) {
      return _buildWatchLayout(context);
    } else {
      return _buildPhoneLayout(context);
    }
  }
}

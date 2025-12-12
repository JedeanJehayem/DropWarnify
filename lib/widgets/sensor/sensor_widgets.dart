// lib/widgets/sensor/sensor_widgets.dart
import 'package:flutter/material.dart';
import 'package:dropwarnify/services/wear_sensor_monitor.dart';

/// Layout da tela de sensores para CELULAR
class SensorPhoneLayout extends StatelessWidget {
  const SensorPhoneLayout({
    super.key,
    required this.lastMovement,
    required this.accelTotal,
    required this.gyroTotal,
    required this.statusTexto,
    required this.statusColor,
  });

  final MovementType lastMovement;
  final double accelTotal;
  final double gyroTotal;
  final String statusTexto;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final themeBlue = Colors.blue.shade700;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: themeBlue,
        iconTheme: const IconThemeData(color: Colors.white), // 👈 seta branca
        title: const Text(
          'Sensores em tempo real',
          style: TextStyle(color: Colors.white),
        ),
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
                        backgroundColor: statusColor.withOpacity(0.15),
                        child: Icon(
                          lastMovement == MovementType.fall
                              ? Icons.warning_amber_rounded
                              : (lastMovement == MovementType.nearFall
                                    ? Icons.report_problem_rounded
                                    : Icons.check_circle),
                          color: statusColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusTexto,
                          style: TextStyle(
                            fontSize: 14,
                            color: statusColor,
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
                        '${accelTotal.toStringAsFixed(2)} m/s²',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Velocidade angular total (|ω|): '
                        '${gyroTotal.toStringAsFixed(2)} °/s',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Último tipo de movimento: '
                        '${lastMovement == MovementType.fall
                            ? 'QUEDA'
                            : lastMovement == MovementType.nearFall
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
}

/// Layout da tela de sensores para RELÓGIO (Wear)
class SensorWatchLayout extends StatelessWidget {
  const SensorWatchLayout({
    super.key,
    required this.lastMovement,
    required this.accelTotal,
    required this.gyroTotal,
    required this.statusTexto,
    required this.statusColor,
  });

  final MovementType lastMovement;
  final double accelTotal;
  final double gyroTotal;
  final String statusTexto;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
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
                    color: statusColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14 * scale),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18 * scale,
                        backgroundColor: statusColor.withOpacity(0.2),
                        child: Icon(
                          lastMovement == MovementType.fall
                              ? Icons.warning_amber_rounded
                              : (lastMovement == MovementType.nearFall
                                    ? Icons.report_problem_rounded
                                    : Icons.check_circle),
                          color: statusColor,
                          size: 18 * scale,
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Text(
                          statusTexto,
                          style: TextStyle(
                            fontSize: 9 * scale,
                            color: statusColor,
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
                        'Accel: ${accelTotal.toStringAsFixed(1)} m/s²',
                        style: TextStyle(fontSize: 9 * scale, color: textColor),
                      ),
                      SizedBox(height: 3 * scale),
                      Text(
                        'Gyro: ${gyroTotal.toStringAsFixed(1)} °/s',
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
}

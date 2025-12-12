// lib/widgets/home/home_wear_widgets.dart
import 'package:flutter/material.dart';
import 'package:dropwarnify/screens/home/home_shared.dart';

class HomeWearLayout extends StatelessWidget {
  const HomeWearLayout({
    super.key,
    required this.statusType,
    required this.statusTitulo,
    required this.statusDescricao,
    required this.pulse,
    required this.watchDarkMode,
    required this.isSendingFromWatch,
    required this.statusColor,
    required this.onSendSOS,
    required this.onToggleDarkMode,
    required this.onOpenSensorDebug,
  });

  final StatusAlertType statusType;
  final String statusTitulo;
  final String statusDescricao;
  final bool pulse;
  final bool watchDarkMode;
  final bool isSendingFromWatch;
  final Color statusColor;

  final VoidCallback onSendSOS;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onOpenSensorDebug;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;
    final double scale = (shortestSide / 320).clamp(0.75, 1.0).toDouble();

    final bgColor = watchDarkMode ? Colors.black : Colors.blue.shade50;
    final textColor = watchDarkMode ? Colors.white70 : Colors.grey.shade700;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double contentWidth = constraints.maxWidth * 0.80;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 6 * scale),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSendingFromWatch) ...[
                        SizedBox(height: 8 * scale),
                        Container(
                          width: 110 * scale,
                          height: 110 * scale,
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(16 * scale),
                          ),
                          child: Icon(
                            Icons.sos,
                            size: 54 * scale,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        const CircularProgressIndicator(strokeWidth: 3),
                        SizedBox(height: 10 * scale),
                        Text(
                          "Enviando alerta...",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: 4 * scale),
                        Text(
                          "Aguarde, o celular\nestá notificando seus contatos.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10 * scale,
                            color: textColor,
                          ),
                        ),
                      ] else ...[
                        if (statusType != StatusAlertType.none) ...[
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8 * scale,
                              vertical: 6 * scale,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14 * scale),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  statusTitulo,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                                SizedBox(height: 3 * scale),
                                Text(
                                  statusDescricao,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9 * scale,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10 * scale),
                        ] else ...[
                          Text(
                            "Monitorando quedas...",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10 * scale,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: 8 * scale),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: onSendSOS,
                              child: AnimatedScale(
                                scale: pulse ? 1.04 : 1.0,
                                duration: const Duration(milliseconds: 180),
                                child: Container(
                                  width: 60 * scale,
                                  height: 60 * scale,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade600,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.shade300.withOpacity(
                                          0.5,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      "SOS",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18 * scale,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12 * scale),
                            GestureDetector(
                              onTap: onToggleDarkMode,
                              child: Container(
                                width: 48 * scale,
                                height: 48 * scale,
                                decoration: BoxDecoration(
                                  color: watchDarkMode
                                      ? Colors.white10
                                      : Colors.grey.shade800,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.4),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  watchDarkMode
                                      ? Icons.light_mode
                                      : Icons.dark_mode,
                                  size: 22 * scale,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6 * scale),
                        Text(
                          "Toque para enviar alerta",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10 * scale,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: 4 * scale),
                        // Botão de debug para abrir tela de sensores
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10 * scale,
                            vertical: 6 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade600,
                            borderRadius: BorderRadius.circular(10 * scale),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 4 * scale,
                                offset: Offset(0, 2 * scale),
                              ),
                            ],
                          ),
                          child: TextButton(
                            onPressed: onOpenSensorDebug,
                            child: Text(
                              "DEBUG SENSORES",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9 * scale,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

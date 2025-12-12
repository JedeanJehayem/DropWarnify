// lib/widgets/home/home_status_card_mobile.dart
import 'package:flutter/material.dart';
import 'package:dropwarnify/screens/home/home_shared.dart';

class HomeStatusCardMobile extends StatelessWidget {
  final StatusAlertType statusType;
  final String titulo;
  final String descricao;
  final bool pulse;

  const HomeStatusCardMobile({
    super.key,
    required this.statusType,
    required this.titulo,
    required this.descricao,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final color = statusColorFor(statusType);

    return AnimatedScale(
      scale: pulse ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Card(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 4,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.white, color.withOpacity(0.07)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(
                  statusType == StatusAlertType.fallReal
                      ? Icons.warning_amber_rounded
                      : statusType == StatusAlertType.fallSimulated
                      ? Icons.science_outlined
                      : statusType == StatusAlertType.nearFall
                      ? Icons.report_problem_rounded
                      : Icons.health_and_safety,
                  color: color,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        if (statusType != StatusAlertType.none)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusType == StatusAlertType.fallReal
                                  ? 'Queda real'
                                  : statusType == StatusAlertType.fallSimulated
                                  ? 'Simulação'
                                  : 'Quase queda',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      descricao,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

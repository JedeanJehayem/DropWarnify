// lib/widgets/home/home_alerts_summary_card.dart
import 'package:flutter/material.dart';
import 'package:dropwarnify/screens/home/home_shared.dart';

class HomeAlertsSummaryCard extends StatelessWidget {
  final List<EmergencyContact> contacts;
  final bool resumoSms;
  final bool resumoWhats;

  const HomeAlertsSummaryCard({
    super.key,
    required this.contacts,
    required this.resumoSms,
    required this.resumoWhats,
  });

  bool _isValidPhone(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  Widget _canalChip({
    required Widget icon,
    required String label,
    Color? bg,
    Color? fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: fg ?? Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _whatsIcon() {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF25D366),
      ),
      child: const Icon(
        Icons.chat_bubble_outline,
        size: 12,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contatosValidos = contacts
        .where((c) => c.phone.isNotEmpty && _isValidPhone(c.phone))
        .toList();
    final temContatoValido = contatosValidos.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              temContatoValido
                  ? Icons.notifications_active
                  : Icons.info_outline,
              color: temContatoValido
                  ? Colors.blue.shade700
                  : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: temContatoValido
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alertas configurados para ${contatosValidos.length} contato(s):',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Column(
                          children: [
                            for (final c in contatosValidos)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3.0,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.person, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.name.isNotEmpty
                                                ? c.name
                                                : 'Contato sem nome',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            c.phone,
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
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (resumoSms)
                              _canalChip(
                                icon: const Icon(
                                  Icons.sms,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: 'SMS',
                                bg: Colors.blue.shade600,
                                fg: Colors.white,
                              ),
                            if (resumoWhats)
                              _canalChip(
                                icon: _whatsIcon(),
                                label: 'WhatsApp',
                                bg: const Color(0xFFDCF8C6),
                                fg: const Color(0xFF075E54),
                              ),
                            if (!resumoSms && !resumoWhats)
                              Text(
                                'Nenhum canal de envio selecionado. Ajuste em Configurações.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nenhum contato configurado',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Acesse a tela de Configurações para definir um ou mais contatos de emergência e os canais de envio.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

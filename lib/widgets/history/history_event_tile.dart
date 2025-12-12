import 'package:flutter/material.dart';
import 'package:dropwarnify/models/fall_event.dart';

class HistoryEventTile extends StatelessWidget {
  final FallEvent event;

  const HistoryEventTile({super.key, required this.event});

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final dia = _twoDigits(local.day);
    final mes = _twoDigits(local.month);
    final ano = local.year;
    final hora = _twoDigits(local.hour);
    final min = _twoDigits(local.minute);
    return '$dia/$mes/$ano às $hora:$min';
  }

  String _originLabel(FallEvent e) {
    switch (e.origin) {
      case 'watch':
        return 'Relógio';
      case 'phone':
        return 'Celular';
      default:
        return 'Não informado';
    }
  }

  Color _statusColor(FallEvent e) {
    switch (e.statusEnvio) {
      case 'ok':
        return Colors.green.shade700;
      case 'offline':
        return Colors.orange.shade700;
      case 'falha':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _statusLabel(FallEvent e) {
    switch (e.statusEnvio) {
      case 'ok':
        return 'Avisos enviados com sucesso';
      case 'offline':
        return 'Registrado sem conexão';
      case 'falha':
        return 'Falha ao enviar avisos';
      default:
        return 'Status de envio não informado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = event;
    final isSimulado = e.simulated;

    // ===== título / ícone / cor levando em conta QUASE QUEDA =====
    late final String title;
    late final IconData icon;
    late final Color color;

    if (e.nearFall) {
      title = 'QUASE QUEDA detectada';
      icon = Icons.directions_walk;
      color = Colors.orange.shade700;
    } else {
      title = isSimulado ? 'Queda SIMULADA' : 'Queda REAL detectada';
      icon = isSimulado ? Icons.science_outlined : Icons.warning_amber_rounded;
      color = isSimulado ? Colors.orange.shade700 : Colors.red.shade700;
    }
    // ===========================================================

    final destinosText = e.destinos.isEmpty
        ? 'Nenhum destino registrado.'
        : e.destinos.join(', ');

    final origemText = _originLabel(e);
    final statusText = _statusLabel(e);
    final statusColor = _statusColor(e);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // data/hora
              Text(
                _formatDateTime(e.timestamp),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 4),

              // origem + status em linha
              Row(
                children: [
                  Icon(
                    e.origin == 'watch' ? Icons.watch : Icons.phone_iphone,
                    size: 14,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Origem: $origemText',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.outgoing_mail, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(fontSize: 12, color: statusColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Text(
                'Enviado para:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destinosText,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

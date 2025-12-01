import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropwarnify/models/fall_event.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FallEvent> _events = [];
  bool _loading = true;

  static const _fallEventsKeyRaw = 'flutter.fall_events';
  static const _fallEventsPrefix = 'This is the prefix for a list.';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();

    // Lê SOMENTE o valor bruto salvo pelo serviço nativo (ou por nós)
    final raw = prefs.getString(_fallEventsKeyRaw);

    List<String> list = <String>[];

    if (raw != null && raw.startsWith(_fallEventsPrefix)) {
      final arrStr = raw.substring(_fallEventsPrefix.length);
      try {
        final decoded = jsonDecode(arrStr);
        if (decoded is List) {
          list = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        list = <String>[];
      }
    }

    final List<FallEvent> loaded = [];
    for (final s in list) {
      try {
        final jsonMap = jsonDecode(s) as Map<String, dynamic>;
        loaded.add(FallEvent.fromJson(jsonMap));
      } catch (_) {
        // ignora entradas corrompidas
      }
    }

    // Ordena do mais recente para o mais antigo
    loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (!mounted) return;
    setState(() {
      _events = loaded;
      _loading = false;
    });
  }

  /// Apaga todo o histórico
  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar histórico'),
        content: const Text(
          'Tem certeza que deseja apagar todo o histórico de quedas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apagar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    // Remove a chave bruta
    await prefs.remove(_fallEventsKeyRaw);
    // Garanta que qualquer resquício antigo seja apagado
    await prefs.remove('fall_events');

    setState(() {
      _events = [];
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Histórico apagado.')));
  }

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
    final themeBlue = Colors.blue.shade700;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: themeBlue,
        title: const Text(
          'Histórico de quedas',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_events.isNotEmpty)
            IconButton(
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Limpar histórico',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Nenhum evento de queda registrado ainda.\n\n'
                  'Quando um alerta for disparado pelo DropWarnify, '
                  'ele aparecerá aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final e = _events[index];
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
                  title = isSimulado
                      ? 'Queda SIMULADA'
                      : 'Queda REAL detectada';
                  icon = isSimulado
                      ? Icons.science_outlined
                      : Icons.warning_amber_rounded;
                  color = isSimulado
                      ? Colors.orange.shade700
                      : Colors.red.shade700;
                }
                // ===========================================================

                final destinosText = e.destinos.isEmpty
                    ? 'Nenhum destino registrado.'
                    : e.destinos.join(', ');

                final origemText = _originLabel(e);
                final statusText = _statusLabel(e);
                final statusColor = _statusColor(e);

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // origem + status em linha
                          Row(
                            children: [
                              Icon(
                                e.origin == 'watch'
                                    ? Icons.watch
                                    : Icons.phone_iphone,
                                size: 14,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Origem: $origemText',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.outgoing_mail,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: statusColor,
                                  ),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mesmo modelo usado no HomeScreen para registrar eventos de queda
class FallEvent {
  final DateTime timestamp;
  final bool simulated;
  final bool nearFall; // se é QUASE QUEDA
  final List<String> destinos; // ex: ["Lolo (SMS)", "Ana (WhatsApp)"]

  FallEvent({
    required this.timestamp,
    required this.simulated,
    required this.nearFall,
    required this.destinos,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'simulated': simulated,
    'nearFall': nearFall,
    'destinos': destinos,
  };

  factory FallEvent.fromJson(Map<String, dynamic> json) {
    return FallEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      simulated: json['simulated'] as bool? ?? false,
      nearFall:
          json['nearFall'] as bool? ??
          false, // eventos antigos (sem nearFall) viram false
      destinos: (json['destinos'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FallEvent> _events = [];
  bool _loading = true;

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
    final list = prefs.getStringList('fall_events') ?? [];

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
                          Text(
                            _formatDateTime(e.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
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

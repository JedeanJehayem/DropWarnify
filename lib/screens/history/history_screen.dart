import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropwarnify/models/fall_event.dart';
import 'package:dropwarnify/widgets/history/history_empty_state.dart';
import 'package:dropwarnify/widgets/history/history_event_tile.dart';

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
          ? const HistoryEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final e = _events[index];
                return HistoryEventTile(event: e);
              },
            ),
    );
  }
}

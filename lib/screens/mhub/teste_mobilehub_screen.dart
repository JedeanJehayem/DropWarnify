import 'package:flutter/material.dart';
import 'package:dropwarnify/services/mhub_bridge.dart';

/// 🔹 TELA (StatefulWidget)
class TesteMobileHubScreen extends StatefulWidget {
  const TesteMobileHubScreen({super.key});

  @override
  State<TesteMobileHubScreen> createState() => _TesteMobileHubScreenState();
}

/// 🔹 STATE da tela
class _TesteMobileHubScreenState extends State<TesteMobileHubScreen> {
  final MHubBridge mhub = MHubBridge();

  String status = 'Desconectado';
  List<String> logs = [];

  void _log(String msg) {
    setState(() => logs.add(msg));
    // também loga no console
    // ignore: avoid_print
    print('[MHub] $msg');
  }

  Future<void> _conectar() async {
    try {
      _log('Conectando ao servidor...');

      await mhub.start(
        ipAddress: 'SEU_IP_AQUI', // ⚠️ coloca o IP real do M-Hub
        port: 12345, // ⚠️ e a porta real
      );

      final started = await mhub.isStarted();
      _log('MobileHub isStarted = $started');

      setState(() => status = started ? 'Conectado' : 'Desconhecido');
    } catch (e) {
      _log('Erro ao conectar: $e');
      setState(() => status = 'Erro');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teste MobileHub')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $status'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _conectar,
              child: const Text('Conectar ao M-Hub'),
            ),
            const SizedBox(height: 16),
            const Text('Logs:'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: logs.map((l) => Text(l)).toList()),
            ),
          ],
        ),
      ),
    );
  }
}

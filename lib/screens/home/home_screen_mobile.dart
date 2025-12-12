// lib/screens/home/home_screen_mobile.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dropwarnify/screens/mhub/teste_mobilehub_screen.dart';

import 'package:dropwarnify/widgets/home/home_status_card_mobile.dart';
import 'package:dropwarnify/widgets/home/home_alerts_summary_card.dart';
import 'package:dropwarnify/models/fall_event.dart';
import 'package:dropwarnify/services/fall_history_repository.dart';
import 'package:dropwarnify/services/wear_contacts_bridge.dart';
import 'package:dropwarnify/screens/history/history_screen.dart';
import 'package:dropwarnify/screens/settings/settings_screen.dart';
import 'package:dropwarnify/screens/location/current_location_screen.dart';
import 'package:dropwarnify/screens/sensor/sensor_screen.dart'; // 🔹 NOVO

import 'home_shared.dart';

class HomeScreenMobile extends StatefulWidget {
  const HomeScreenMobile({super.key});

  @override
  State<HomeScreenMobile> createState() => _HomeScreenMobileState();
}

class _HomeScreenMobileState extends State<HomeScreenMobile> {
  String _statusTitulo = 'Nenhuma queda detectada';
  String _statusDescricao = 'O sistema está monitorando normalmente.';
  StatusAlertType _statusType = StatusAlertType.none;
  bool _pulse = false;

  List<EmergencyContact> _contacts = <EmergencyContact>[];
  bool _resumoSms = false;
  bool _resumoWhats = false;

  StreamSubscription<FallEvent>? _watchEventsSub;

  @override
  void initState() {
    super.initState();
    _carregarResumoContato();

    // Escuta eventos vindos do relógio → celular dispara SMS/WhatsApp
    _watchEventsSub = WearContactsBridge.instance.watchEventsStream.listen((
      event,
    ) {
      _handleFallEventFromWatch(event);
    });
  }

  @override
  void dispose() {
    _watchEventsSub?.cancel();
    super.dispose();
  }

  // ========= Helpers telefone =========

  bool _isValidPhone(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  String _normalizePhone(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('55')) return '+$digits';
    return '+55$digits';
  }

  Uri _buildSmsUri(String phone, String message) {
    final normalized = _normalizePhone(phone);
    return Uri(
      scheme: 'sms',
      path: normalized,
      queryParameters: {'body': message},
    );
  }

  Uri _buildWhatsAppUri(String phone, String message) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final normalized = '55$digits';
    final encodedMsg = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$normalized?text=$encodedMsg');
  }

  // ========= Localização (para mensagem) =========

  Future<String?> _reverseGeocode(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;

      final endereco = [
        p.street,
        p.subLocality,
        p.locality,
      ].where((e) => (e ?? '').trim().isNotEmpty).join(', ');

      final linha2 = [
        p.administrativeArea,
        p.postalCode,
        p.country,
      ].where((e) => (e ?? '').trim().isNotEmpty).join(' • ');

      final completo = [
        endereco,
        linha2,
      ].where((e) => e.trim().isNotEmpty).join('\n');

      return completo.trim().isEmpty ? null : completo.trim();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _buildLocationSnippetForAlert() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;

      final endereco = await _reverseGeocode(pos);
      if (endereco != null) {
        return 'Endereço aproximado:\n$endereco';
      }

      final lat = pos.latitude.toStringAsFixed(5);
      final lng = pos.longitude.toStringAsFixed(5);
      return 'Localização aproximada:\nLat: $lat  |  Lng: $lng';
    } catch (_) {
      return null;
    }
  }

  // ========= Contatos e resumo =========

  Future<void> _carregarResumoContato() async {
    final prefs = await SharedPreferences.getInstance();

    final listStr = prefs.getStringList('emergency_contacts') ?? [];
    final List<EmergencyContact> loaded = [];

    if (listStr.isNotEmpty) {
      for (final s in listStr) {
        try {
          final json = jsonDecode(s) as Map<String, dynamic>;
          loaded.add(EmergencyContact.fromJson(json));
        } catch (_) {
          // ignora registro quebrado
        }
      }
    } else {
      // fallback antigo
      final oldName = prefs.getString('contato_nome') ?? '';
      final oldPhone = prefs.getString('contato_telefone') ?? '';
      if (oldPhone.isNotEmpty) {
        loaded.add(EmergencyContact(name: oldName, phone: oldPhone));
      }
    }

    setState(() {
      _contacts = loaded;
      _resumoSms = prefs.getBool('enviar_sms') ?? false;
      _resumoWhats = prefs.getBool('enviar_whatsapp') ?? false;
    });
  }

  // ========= Histórico =========

  Future<void> _registrarEventoQueda({
    required bool simulado,
    required bool nearFall,
    required List<String> destinos,
    required String origin,
    required String statusEnvio,
  }) async {
    final event = FallEvent(
      timestamp: DateTime.now(),
      simulated: simulado,
      nearFall: nearFall,
      destinos: destinos,
      origin: origin,
      statusEnvio: statusEnvio,
    );
    await FallHistoryRepository.instance.registrarEvento(event);
  }

  // ========= Fluxo de envio de alerta (celular) =========

  Future<bool> _enviarAlertaComConfigsSalvas({
    required bool simulado,
    bool nearFall = false,
    bool registrarHistorico = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final nomeIdoso = prefs.getString('nome_idoso') ?? 'Paciente';
      final enviarSMS = prefs.getBool('enviar_sms') ?? false;
      final enviarWhatsApp = prefs.getBool('enviar_whatsapp') ?? false;

      final contatosValidos = _contacts
          .where((c) => c.phone.isNotEmpty && _isValidPhone(c.phone))
          .toList();

      if (contatosValidos.isEmpty) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Center(
              child: Text(
                'Nenhum contato válido cadastrado.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return false;
      }

      if (!enviarSMS && !enviarWhatsApp) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ative SMS ou WhatsApp na tela de Configurações para enviar o alerta.',
            ),
          ),
        );
        return false;
      }

      final msgBase = simulado
          ? 'ALERTA DE TESTE do DropWarnify. Possível queda envolvendo $nomeIdoso.'
          : (nearFall
                ? 'ALERTA PREVENTIVO do DropWarnify. Possível QUASE queda envolvendo $nomeIdoso.'
                : 'ALERTA REAL do DropWarnify. Possível queda envolvendo $nomeIdoso.');

      final locationSnippet = await _buildLocationSnippetForAlert();
      final mensagemFinal = locationSnippet == null
          ? msgBase
          : '$msgBase\n\n$locationSnippet';

      final enviados = <String>[];
      bool algumAppDisponivel = false;

      for (final c in contatosValidos) {
        final nome = c.name.isNotEmpty ? c.name : 'Contato';
        final telefone = c.phone;

        if (enviarSMS) {
          enviados.add('$nome (SMS)');
          final smsUri = _buildSmsUri(telefone, mensagemFinal);
          try {
            if (await canLaunchUrl(smsUri)) {
              algumAppDisponivel = true;
              await launchUrl(smsUri, mode: LaunchMode.externalApplication);
            }
          } catch (e) {
            debugPrint('Erro ao abrir SMS: $e');
          }
          await Future.delayed(const Duration(seconds: 1));
        }

        if (enviarWhatsApp) {
          enviados.add('$nome (WhatsApp)');
          final waUri = _buildWhatsAppUri(telefone, mensagemFinal);
          try {
            if (await canLaunchUrl(waUri)) {
              algumAppDisponivel = true;
              await launchUrl(waUri, mode: LaunchMode.externalApplication);
            }
          } catch (e) {
            debugPrint('Erro ao abrir WhatsApp: $e');
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      final List<String> destinosParaLog = enviados.isNotEmpty
          ? List<String>.from(enviados)
          : contatosValidos.map((c) {
              final nome = c.name.isNotEmpty ? c.name : 'Contato';
              return '$nome (sem app de SMS/WhatsApp disponível)';
            }).toList();

      const origin = 'phone';
      String statusEnvio;
      if (algumAppDisponivel) {
        statusEnvio = 'ok';
      } else if (contatosValidos.isNotEmpty && (enviarSMS || enviarWhatsApp)) {
        statusEnvio = 'falha';
      } else {
        statusEnvio = 'desconhecido';
      }

      if (registrarHistorico) {
        await _registrarEventoQueda(
          simulado: simulado,
          nearFall: nearFall,
          destinos: destinosParaLog,
          origin: origin,
          statusEnvio: statusEnvio,
        );
      }
      if (!mounted) return true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            'Alertas executadas para:\n'
            '${(enviados.isEmpty ? ['(sem app de SMS/WhatsApp disponível)'] : enviados).join(", ")}',
          ),
        ),
      );

      return true;
    } catch (e, st) {
      debugPrint('Erro inesperado ao enviar alerta: $e\n$st');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro inesperado ao enviar alerta.')),
      );
      return false;
    }
  }

  // ========= Eventos vindos do relógio =========

  Future<void> _handleFallEventFromWatch(FallEvent event) async {
    setState(() {
      _statusType = event.nearFall
          ? StatusAlertType.nearFall
          : StatusAlertType.fallReal;
      _statusTitulo = event.nearFall
          ? 'Quase queda detectada pelo relógio'
          : 'Queda detectada pelo relógio';
      _statusDescricao = event.nearFall
          ? 'O relógio identificou um desequilíbrio forte. Enviando alerta preventivo.'
          : 'O relógio identificou uma possível queda. Enviando alerta aos contatos.';
      _pulse = true;
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _pulse = false);
    });

    await _enviarAlertaComConfigsSalvas(
      simulado: false,
      nearFall: event.nearFall,
      registrarHistorico: false,
    );
  }

  // ========= Ações de UI =========

  Future<void> _simularQueda() async {
    setState(() {
      _statusType = StatusAlertType.fallSimulated;
      _statusTitulo = 'Queda detectada (simulação)';
      _statusDescricao =
          'Uma queda foi simulada para testes. As rotinas de alerta foram disparadas.';
      _pulse = true;
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _pulse = false);
    });

    await _enviarAlertaComConfigsSalvas(simulado: true, nearFall: false);
  }

  Future<void> _abrirConfiguracoes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await _carregarResumoContato();
  }

  Future<void> _abrirLocalizacaoAtual() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CurrentLocationScreen()),
    );
  }

  // 🔹 NOVO: abrir tela de sensores
  Future<void> _abrirSensorScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SensorScreen()),
    );
  }

  // ========= Layout =========

  // ========= Layout =========

  @override
  Widget build(BuildContext context) {
    final themeBlue = Colors.blue.shade700;
    final themeLightBlue = Colors.blue.shade50;

    return Scaffold(
      backgroundColor: themeLightBlue,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: themeBlue,
        centerTitle: true,
        title: const Text(
          'DropWarnify',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: 'Histórico de quedas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [themeLightBlue, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ====== HEADER / STATUS ======
                Text(
                  'Monitoramento de quedas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Veja o estado atual do sistema e dos alertas.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),

                HomeStatusCardMobile(
                  statusType: _statusType,
                  titulo: _statusTitulo,
                  descricao: _statusDescricao,
                  pulse: _pulse,
                ),

                const SizedBox(height: 16),

                // ====== CONTATOS / RESUMO ======
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.contacts, color: themeBlue, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Contatos de emergência',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        HomeAlertsSummaryCard(
                          contacts: _contacts,
                          resumoSms: _resumoSms,
                          resumoWhats: _resumoWhats,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ====== AÇÕES RÁPIDAS ======
                Text(
                  'Ações rápidas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 8),

                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _simularQueda,
                            icon: const Icon(Icons.sensors_rounded),
                            label: const Text(
                              'Simular queda agora',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 🔹 BOTÃO: SENSOR SCREEN
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _abrirSensorScreen,
                            icon: const Icon(Icons.show_chart),
                            label: const Text(
                              'Ver sensores em tempo real',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: themeBlue),
                              foregroundColor: themeBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 🔹 BOTÃO: TESTE M-HUB
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TesteMobileHubScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.cloud_sync),
                            label: const Text(
                              'Testar M-Hub (Plugin)',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.deepPurple),
                              foregroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _abrirLocalizacaoAtual,
                            icon: const Icon(Icons.my_location),
                            label: const Text(
                              'Ver localização atual',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.green),
                              foregroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ====== CONFIGURAÇÕES / RODAPÉ ======
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _abrirConfiguracoes,
                    icon: const Icon(Icons.settings),
                    label: const Text('Configurações'),
                    style: TextButton.styleFrom(
                      foregroundColor: themeBlue,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Protótipo DropWarnify • TCC\nMonitoramento e alerta de quedas',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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

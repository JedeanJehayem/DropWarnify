import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/wear_contacts_bridge.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
import '../sensor/sensor_screen.dart';
import '../location/current_location_screen.dart';

/// Mesmo modelo usado na SettingsScreen
class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

/// Evento de queda (para histórico)
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
      nearFall: json['nearFall'] as bool? ?? false,
      destinos: (json['destinos'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Tipo de status atual mostrado no card principal
enum StatusAlertType { none, fallReal, fallSimulated, nearFall }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _statusTitulo = 'Nenhuma queda detectada';
  String _statusDescricao = 'O sistema está monitorando normalmente.';
  Color _statusColor = Colors.green.shade600;

  StatusAlertType _statusType = StatusAlertType.none;

  List<EmergencyContact> _contacts = [];

  bool _resumoSms = false;
  bool _resumoWhats = false;

  bool _pulse = false;

  /// modo escuro só para o layout do relógio
  bool _watchDarkMode = false;

  /// indica se o relógio está na tela de "enviando alerta"
  bool _isSendingFromWatch = false;

  @override
  void initState() {
    super.initState();
    _carregarResumoContato();

    // depois que a árvore montar, verificamos se é relógio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tentarSincronizarContatosDoCelularSeWatch();
    });
  }

  // ========= HELPERS TELEFONE =========

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

  // ========= LOCALIZAÇÃO PARA ALERTA (ENDEREÇO) =========

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

  // ========= CARREGA RESUMO DAS CONFIGS =========

  Future<void> _tentarSincronizarContatosDoCelularSeWatch() async {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;

    if (!isWatch) return;

    print('WATCH: pedindo contatos ao celular...');
    final lista = await WearContactsBridge.instance.getContactsFromPhone();
    print('WATCH: resposta = ${lista?.length ?? -1} contatos (null = -1)');

    if (!mounted) return;

    if (lista == null) {
      // não conseguiu falar com o nativo / celular
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'Não foi possível sincronizar contatos com o celular.',
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    if (lista.isEmpty) {
      // falou com o celular mas ele devolveu 0
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'Nenhum contato recebido do celular.',
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    setState(() {
      _contacts = lista;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          'Sincronizados ${lista.length} contato(s) do celular.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

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

  // ========= CHIP CUSTOMIZADO =========

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

  // ========= CARD RESUMO ALERTAS =========

  Widget _buildResumoAlertasCard() {
    final List<EmergencyContact> contatosValidos = [];
    for (final c in _contacts) {
      if (c.phone.isNotEmpty && _isValidPhone(c.phone)) {
        contatosValidos.add(c);
      }
    }

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
                            if (_resumoSms)
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
                            if (_resumoWhats)
                              _canalChip(
                                icon: _whatsIcon(),
                                label: 'WhatsApp',
                                bg: const Color(0xFFDCF8C6),
                                fg: const Color(0xFF075E54),
                              ),
                            if (!_resumoSms && !_resumoWhats)
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

  // ========= ENVIO DO ALERTA =========
  /// Agora retorna bool para indicar se realmente enviou algum alerta.
  Future<bool> _enviarAlertaComConfigsSalvas({
    required bool simulado,
    bool nearFall = false, // se é QUASE QUEDA
  }) async {
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
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
          content: Center(
            child: Text(
              'Nenhum contato válido cadastrado.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          duration: const Duration(seconds: 3),
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

    for (final c in contatosValidos) {
      final nome = c.name.isNotEmpty ? c.name : 'Contato';
      final telefone = c.phone;

      if (enviarSMS) {
        final smsUri = _buildSmsUri(telefone, mensagemFinal);
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
          enviados.add('$nome (SMS)');
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      if (enviarWhatsApp) {
        final waUri = _buildWhatsAppUri(telefone, mensagemFinal);
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
          enviados.add('$nome (WhatsApp)');
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (enviados.isEmpty) {
      // Nenhum canal conseguiu ser aberto de fato.
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível abrir SMS/WhatsApp para enviar o alerta.',
          ),
        ),
      );
      return false;
    }

    await _registrarEventoQueda(
      simulado: simulado,
      nearFall: nearFall,
      destinos: enviados,
    );

    if (!mounted) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          'Alertas enviados para:\n${enviados.join(", ")}\n'
          'No WhatsApp Web, apenas o último chat pode ficar visível, mas todos foram disparados.',
        ),
      ),
    );

    return true;
  }

  /// Registra um evento de queda no histórico (SharedPreferences)
  Future<void> _registrarEventoQueda({
    required bool simulado,
    required bool nearFall,
    required List<String> destinos,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('fall_events') ?? [];

    final event = FallEvent(
      timestamp: DateTime.now(),
      simulated: simulado,
      nearFall: nearFall,
      destinos: destinos,
    );

    list.add(jsonEncode(event.toJson()));
    await prefs.setStringList('fall_events', list);
  }

  // ========= AÇÕES =========

  Future<void> _abrirSensorScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SensorScreen(
          onFall: () async {
            setState(() {
              _statusTitulo = 'Queda detectada!';
              _statusDescricao =
                  'O sistema detectou uma queda real pelos sensores.';
              _statusColor = Colors.red.shade700;
              _pulse = true;
              _statusType = StatusAlertType.fallReal;
            });

            Future.delayed(const Duration(milliseconds: 150), () {
              if (!mounted) return;
              setState(() => _pulse = false);
            });

            await _enviarAlertaComConfigsSalvas(
              simulado: false,
              nearFall: false,
            );
          },
          onNearFall: () async {
            setState(() {
              _statusTitulo = 'Quase queda detectada';
              _statusDescricao =
                  'O sistema detectou um desequilíbrio forte. Os contatos foram avisados como medida preventiva.';
              _statusColor = Colors.orange.shade600;
              _pulse = true;
              _statusType = StatusAlertType.nearFall;
            });

            Future.delayed(const Duration(milliseconds: 150), () {
              if (!mounted) return;
              setState(() => _pulse = false);
            });

            await _enviarAlertaComConfigsSalvas(
              simulado: false,
              nearFall: true,
            );
          },
        ),
      ),
    );
  }

  Future<void> _simularQueda() async {
    setState(() {
      _statusTitulo = 'Queda detectada (simulação)';
      _statusDescricao =
          'Uma queda foi simulada para testes. As rotinas de alerta foram disparadas.';
      _statusColor = Colors.orange.shade700;
      _pulse = true;
      _statusType = StatusAlertType.fallSimulated;
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

  /// Alerta manual acionado pelo relógio (botão SOS)
  /// Mostra uma tela de "enviando notificação" no smartwatch
  /// e depois volta para a tela normal.
  Future<void> _enviarAlertaManualFromWatch() async {
    setState(() {
      _isSendingFromWatch = true;
    });

    final sucesso = await _enviarAlertaComConfigsSalvas(
      simulado: false,
      nearFall: false,
    );

    if (!mounted) return;

    if (sucesso) {
      setState(() {
        _statusTitulo = 'Alerta manual enviado';
        _statusDescricao =
            'Você acionou manualmente o alerta pelo relógio. Os contatos foram avisados.';
        _statusColor = Colors.red.shade700;
        _pulse = true;
        _statusType = StatusAlertType.fallReal;
      });

      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _pulse = false);
      });
    }

    // Aguarda alguns segundos e volta para a tela normal do relógio
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _isSendingFromWatch = false;
      });
    });
  }

  // ========= STATUS CARD (reutilizado: phone + watch) =========

  Widget _buildStatusCard({required bool compact, bool dark = false}) {
    final double avatarRadius = compact ? 22 : 28;
    final double iconSize = compact ? 24 : 30;
    final double titleSize = compact ? 14 : 18;
    final double descSize = compact ? 11 : 13;
    final EdgeInsets padding = compact
        ? const EdgeInsets.all(14)
        : const EdgeInsets.all(20);

    final Color bgStart = dark ? const Color(0xFF181818) : Colors.white;
    final Color bgEnd = dark
        ? _statusColor.withOpacity(0.25)
        : _statusColor.withOpacity(0.07);
    final Color textColor = dark ? Colors.white70 : Colors.grey.shade800;
    final Color avatarBg = dark
        ? Colors.black.withOpacity(0.4)
        : _statusColor.withOpacity(0.15);

    return AnimatedScale(
      scale: _pulse ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Card(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: dark ? 6 : 4,
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [bgStart, bgEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: avatarBg,
                child: Icon(
                  _statusType == StatusAlertType.fallReal
                      ? Icons.warning_amber_rounded
                      : _statusType == StatusAlertType.fallSimulated
                      ? Icons.science_outlined
                      : _statusType == StatusAlertType.nearFall
                      ? Icons.report_problem_rounded
                      : Icons.health_and_safety,
                  color: _statusColor,
                  size: iconSize,
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
                            _statusTitulo,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              color: _statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_statusType != StatusAlertType.none)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _statusType == StatusAlertType.fallReal
                                  ? 'Queda real'
                                  : _statusType == StatusAlertType.fallSimulated
                                  ? 'Simulação'
                                  : 'Quase queda',
                              style: TextStyle(
                                fontSize: compact ? 10 : 11,
                                fontWeight: FontWeight.w600,
                                color: _statusColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusDescricao,
                      style: TextStyle(fontSize: descSize, color: textColor),
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

  // ========= LAYOUT: CELULAR =========

  Widget _buildPhoneLayout(BuildContext context) {
    final themeBlue = Colors.blue.shade700;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        flexibleSpace: Container(decoration: BoxDecoration(color: themeBlue)),
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
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.white.withOpacity(0.0),
                  BlendMode.srcATop,
                ),
                child: Opacity(
                  opacity: 0.22,
                  child: Image.asset(
                    'assets/images/logo_dropwarnify.png',
                    width: 650,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              16,
              16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(compact: false),
                  const SizedBox(height: 12),
                  _buildResumoAlertasCard(),
                  const SizedBox(height: 24),
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _abrirSensorScreen,
                      icon: const Icon(Icons.sensors),
                      label: const Text('Monitorar sensores em tempo real'),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _abrirLocalizacaoAtual,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Ver localização atual'),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _abrirConfiguracoes,
                      icon: const Icon(Icons.settings),
                      label: const Text('Configurações'),
                      style: TextButton.styleFrom(
                        foregroundColor: themeBlue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Protótipo DropWarnify • TCC\nMonitoramento e alerta de quedas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ========= LAYOUT: SMARTWATCH =========

  Widget _buildWatchLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;

    final double scale = (shortestSide / 320).clamp(0.75, 1.0).toDouble();

    final bgColor = _watchDarkMode ? Colors.black : Colors.blue.shade50;
    final textColor = _watchDarkMode ? Colors.white70 : Colors.grey.shade700;

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
                      if (_isSendingFromWatch) ...[
                        SizedBox(height: 8 * scale),
                        // IMAGEM DE ENVIO DE NOTIFICAÇÃO
                        Container(
                          width: 110 * scale,
                          height: 110 * scale,
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(16 * scale),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(10 * scale),
                            child: Image.asset(
                              'assets/images/sending_alert.png',
                              fit: BoxFit.contain,
                              color: Colors
                                  .white, // opcional: deixa a imagem branca
                            ),
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
                          "Aguarde, seus contatos\nestão sendo notificados.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10 * scale,
                            color: textColor,
                          ),
                        ),
                      ] else ...[
                        Transform.scale(
                          scale: scale * 0.9,
                          child: _buildStatusCard(
                            compact: true,
                            dark: _watchDarkMode,
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: _enviarAlertaManualFromWatch,
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
                            SizedBox(width: 12 * scale),
                            GestureDetector(
                              onTap: () {
                                setState(
                                  () => _watchDarkMode = !_watchDarkMode,
                                );
                              },
                              child: Container(
                                width: 48 * scale,
                                height: 48 * scale,
                                decoration: BoxDecoration(
                                  color: _watchDarkMode
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
                                  _watchDarkMode
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

  // ========= UI ROOT =========

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;

    if (isWatch) {
      return _buildWatchLayout(context);
    } else {
      return _buildPhoneLayout(context);
    }
  }
}

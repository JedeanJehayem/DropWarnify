import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dropwarnify/services/fall_history_repository.dart';
import 'package:dropwarnify/services/wear_sensor_monitor.dart'; // ⬅️ PLUG DOS SENSORES

import 'package:dropwarnify/models/fall_event.dart';
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

  /// Monitor de sensores no relógio
  WearSensorMonitor? _sensorMonitor;

  /// Inscrição de eventos de queda vindos do relógio (no CELULAR)
  StreamSubscription<FallEvent>? _watchEventsSub;

  /// Canal para controlar o serviço nativo de detecção contínua no relógio
  static const MethodChannel _wearServiceChannel = MethodChannel(
    'br.com.dropwarnify/wear_service',
  );

  @override
  void initState() {
    super.initState();
    _carregarResumoContato();

    // ouvir eventos de queda vindos do relógio (no CELULAR)
    _watchEventsSub = WearContactsBridge.instance.watchEventsStream.listen((
      event,
    ) {
      _handleFallEventFromWatch(event);
    });

    // depois que a árvore montar, verificamos se é relógio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tentarSincronizarContatosDoCelularSeWatch();
      _iniciarSensoresNoRelogioSeNecessario(); // debug em Dart
      _ativarMonitoramentoContinuoNoRelogio(); // serviço nativo em foreground
    });
  }

  @override
  void dispose() {
    _watchEventsSub?.cancel();
    _sensorMonitor?.dispose();
    super.dispose();
  }

  /// Liga o serviço nativo de detecção contínua de quedas **apenas no relógio**.
  Future<void> _ativarMonitoramentoContinuoNoRelogio() async {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;
    if (!isWatch) return;

    try {
      await _wearServiceChannel.invokeMethod('start_fall_service');
      debugPrint('WATCH: serviço de detecção contínua iniciado.');
    } catch (e, st) {
      debugPrint('WATCH: erro ao iniciar serviço de quedas: $e\n$st');
    }
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

  /// Trata evento de queda vindo do relógio (recebido no CELULAR)
  Future<void> _handleFallEventFromWatch(FallEvent event) async {
    await _enviarAlertaComConfigsSalvas(
      simulado: false,
      nearFall: event.nearFall,
    );
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

  // ========= CARREGA RESUMO DAS CONFIGS / SYNC WEAR =========

  Future<void> _tentarSincronizarContatosDoCelularSeWatch() async {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;

    if (!isWatch) return;

    try {
      debugPrint('WATCH: pedindo contatos ao celular...');
      final lista = await WearContactsBridge.instance.getContactsFromPhone();
      debugPrint('WATCH: resposta = ${lista?.length ?? -1} contatos');

      if (!mounted) return;

      if (lista == null || lista.isEmpty) {
        // Falha de comunicação ou celular respondeu vazio.
        // Fica silencioso para não encher o usuário de erro à toa.
        return;
      }

      // Salvar contatos recebidos também no relógio
      final prefs = await SharedPreferences.getInstance();
      final listStr = lista.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList('emergency_contacts', listStr);

      // Recarrega resumo (contatos + flags) a partir do armazenamento local
      await _carregarResumoContato();

      // Snack de sucesso (esse pode aparecer)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'Sincronizados ${lista.length} contato(s) do celular.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('WATCH: erro ao sincronizar contatos: $e\n$st');
      // Não mostra snackbar de erro aqui para não assustar logo na abertura.
    }
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

  /// Registra um evento de queda no histórico usando o repositório central
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

  /// Agora retorna bool para indicar se realmente enviou algum alerta.
  Future<bool> _enviarAlertaComConfigsSalvas({
    required bool simulado,
    bool nearFall = false, // se é QUASE QUEDA
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final nomeIdoso = prefs.getString('nome_idoso') ?? 'Paciente';
      final enviarSMS = prefs.getBool('enviar_sms') ?? false;
      final enviarWhatsApp = prefs.getBool('enviar_whatsapp') ?? false;

      // Descobre se é relógio
      final shortestSide = MediaQuery.of(context).size.shortestSide;
      final bool isWatch = shortestSide < 300;

      // No relógio, se as flags não existirem (false/false), não vamos bloquear:
      bool smsAtivo = enviarSMS;
      bool whatsAtivo = enviarWhatsApp;
      if (isWatch && !smsAtivo && !whatsAtivo) {
        smsAtivo = true;
        whatsAtivo = true;
      }

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

      if (!smsAtivo && !whatsAtivo) {
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

        if (smsAtivo) {
          enviados.add('$nome (SMS)');
          final smsUri = _buildSmsUri(telefone, mensagemFinal);
          try {
            if (await canLaunchUrl(smsUri)) {
              algumAppDisponivel = true;
              await launchUrl(smsUri, mode: LaunchMode.externalApplication);
            } else {
              debugPrint('Nenhum app de SMS disponível para $telefone');
            }
          } catch (e) {
            debugPrint('Erro ao abrir SMS: $e');
          }
          await Future.delayed(const Duration(seconds: 1));
        }

        if (whatsAtivo) {
          enviados.add('$nome (WhatsApp)');
          final waUri = _buildWhatsAppUri(telefone, mensagemFinal);
          try {
            if (await canLaunchUrl(waUri)) {
              algumAppDisponivel = true;
              await launchUrl(waUri, mode: LaunchMode.externalApplication);
            } else {
              debugPrint('Nenhum app de WhatsApp disponível para $telefone');
            }
          } catch (e) {
            debugPrint('Erro ao abrir WhatsApp: $e');
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      // Mesmo que o emulador não tenha apps, se tinha contato + canal,
      // vamos registrar o evento no histórico.
      final destinosParaLog = enviados.isEmpty
          ? contatosValidos
                .map(
                  (c) =>
                      (c.name.isNotEmpty ? c.name : 'Contato') +
                      ' (sem app de SMS/WhatsApp disponível)',
                )
                .toList()
          : List<String>.from(enviados);

      // origem: phone ou watch
      final origin = isWatch ? 'watch' : 'phone';

      // status de envio: tenta qualificar o que aconteceu
      String statusEnvio;
      if (algumAppDisponivel) {
        statusEnvio = 'ok';
      } else if (contatosValidos.isNotEmpty && (smsAtivo || whatsAtivo)) {
        // havia contato + canal, mas nenhum app disponível (caso típico em emulador)
        statusEnvio = 'falha';
      } else {
        statusEnvio = 'desconhecido';
      }

      await _registrarEventoQueda(
        simulado: simulado,
        nearFall: nearFall,
        destinos: destinosParaLog,
        origin: origin,
        statusEnvio: statusEnvio,
      );

      if (!mounted) return true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            'Rotinas de alerta executadas para:\n'
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

  // ========= AÇÕES =========

  /// Inicializa o monitor de sensores **apenas no relógio**.
  void _iniciarSensoresNoRelogioSeNecessario() {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;
    if (!isWatch) return;
    if (_sensorMonitor != null) return;

    _sensorMonitor = WearSensorMonitor(
      onFall: () async {
        await _handleWatchAutoFall(nearFall: false);
      },
      onNearFall: () async {
        await _handleWatchAutoFall(nearFall: true);
      },
    );
    _sensorMonitor!.start();
  }

  /// Tratamento de QUEDA/QUASE QUEDA detectada automaticamente no relógio
  Future<void> _handleWatchAutoFall({required bool nearFall}) async {
    if (!mounted) return;

    // Atualiza o status visual
    setState(() {
      if (nearFall) {
        _statusTitulo = 'Quase queda detectada (sensores)';
        _statusDescricao =
            'O relógio detectou um desequilíbrio forte. Os contatos podem ser avisados preventivamente.';
        _statusColor = Colors.orange.shade600;
        _statusType = StatusAlertType.nearFall;
      } else {
        _statusTitulo = 'Queda detectada pelo relógio!';
        _statusDescricao =
            'Os sensores identificaram uma possível queda real. As rotinas de alerta serão disparadas.';
        _statusColor = Colors.red.shade700;
        _statusType = StatusAlertType.fallReal;
      }
      _pulse = true;
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _pulse = false);
    });

    // Garante que temos contatos sincronizados (se ainda estiver vazio)
    if (_contacts.isEmpty) {
      await _tentarSincronizarContatosDoCelularSeWatch();
      await _carregarResumoContato();
    }

    // 👉 Novo fluxo: só monta o evento e envia para o CELULAR
    try {
      final destinos = _contacts
          .where((c) => c.phone.isNotEmpty && _isValidPhone(c.phone))
          .map((c) {
            final nome = c.name.isNotEmpty ? c.name : 'Contato';
            return nearFall
                ? '$nome (quase queda automática relógio)'
                : '$nome (queda automática relógio)';
          })
          .toList();

      final evento = FallEvent(
        timestamp: DateTime.now(),
        simulated: false,
        nearFall: nearFall,
        destinos: destinos,
        origin: 'watch',
        statusEnvio: 'desconhecido',
      );

      await WearContactsBridge.instance.sendFallEventToPhone(evento);
    } catch (_) {
      // falha aqui não deve quebrar a experiência no relógio
    }
  }

  Future<void> _abrirSensorScreen() async {
    // Se for relógio, podemos pausar o monitor da Home enquanto estamos no debug
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isWatch = shortestSide < 300;

    if (isWatch) {
      _sensorMonitor?.dispose();
      _sensorMonitor = null;
    }

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

    // Ao voltar, se for relógio, reativa o monitor da Home
    if (isWatch && mounted) {
      _iniciarSensoresNoRelogioSeNecessario();
    }
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
    try {
      // Se o relógio ainda não tem contatos em memória, tenta sincronizar agora
      if (_contacts.isEmpty) {
        await _tentarSincronizarContatosDoCelularSeWatch();
        // Recarrega contatos do storage, se a sync tiver salvo algo
        await _carregarResumoContato();
      }

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

        // ➕ continua mandando o evento para o celular (fluxo Wear → Phone)
        try {
          final destinos = _contacts
              .where((c) => c.phone.isNotEmpty && _isValidPhone(c.phone))
              .map((c) {
                final nome = c.name.isNotEmpty ? c.name : 'Contato';
                return '$nome (SOS relógio)';
              })
              .toList();

          final evento = FallEvent(
            timestamp: DateTime.now(),
            simulated: false,
            nearFall: false,
            destinos: destinos,
            origin: 'watch',
            statusEnvio: 'desconhecido',
          );

          await WearContactsBridge.instance.sendFallEventToPhone(evento);
        } catch (_) {
          // se der erro, não quebra a UX do SOS
        }
      }
    } catch (e, st) {
      debugPrint('Erro no fluxo SOS do relógio: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao processar SOS no relógio.')),
        );
      }
    } finally {
      // Aguarda alguns segundos e volta para a tela normal do relógio
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _isSendingFromWatch = false;
        });
      });
    }
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
                              color: Colors.white,
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
                        if (_statusType != StatusAlertType.none) ...[
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8 * scale,
                              vertical: 6 * scale,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14 * scale),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _statusType == StatusAlertType.fallReal
                                      ? 'SOS enviado'
                                      : _statusType ==
                                            StatusAlertType.fallSimulated
                                      ? 'Queda simulada'
                                      : 'Quase queda detectada',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: _statusColor,
                                  ),
                                ),
                                SizedBox(height: 3 * scale),
                                Text(
                                  _statusDescricao,
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
                                setState(() {
                                  _watchDarkMode = !_watchDarkMode;
                                });
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
                        SizedBox(height: 4 * scale),

                        // 🔧 Botão temporário de debug para abrir a tela de sensores
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
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SensorScreen(),
                                ),
                              );
                            },
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

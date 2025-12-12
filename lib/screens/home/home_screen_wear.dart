// lib/screens/home/home_screen_wear.dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dropwarnify/models/fall_event.dart';
import 'package:dropwarnify/services/wear_sensor_monitor.dart';
import 'package:dropwarnify/services/wear_contacts_bridge.dart';
import 'package:dropwarnify/screens/sensor/sensor_screen.dart';
import 'package:dropwarnify/screens/home/home_shared.dart';
import 'package:dropwarnify/widgets/home/home_wear_widgets.dart';
import 'package:dropwarnify/wear/fall_service_bridge.dart';

class HomeScreenWear extends StatefulWidget {
  const HomeScreenWear({super.key});

  @override
  State<HomeScreenWear> createState() => _HomeScreenWearState();
}

class _HomeScreenWearState extends State<HomeScreenWear> {
  StatusAlertType _statusType = StatusAlertType.none;
  String _statusTitulo = 'Monitorando quedas...';
  String _statusDescricao = 'O relógio está monitorando seus movimentos.';
  bool _pulse = false;

  bool _watchDarkMode = false;
  bool _isSendingFromWatch = false;

  WearSensorMonitor? _sensorMonitor;
  StreamSubscription? _dummySub; // reservado se precisar ouvir algo depois

  Color get _statusColor => statusColorFor(_statusType);

  @override
  void initState() {
    super.initState();
    _iniciarSensores();
  }

  @override
  void dispose() {
    _sensorMonitor?.dispose();
    _dummySub?.cancel();

    // 🔻 Para o serviço nativo de detecção de quedas em background
    WearFallServiceBridge.stop();

    super.dispose();
  }

  /// Inicia o monitor de sensores em Flutter + serviço nativo em background.
  void _iniciarSensores() async {
    if (_sensorMonitor != null) return;

    _sensorMonitor = WearSensorMonitor(
      onFall: () async {
        await _handleAutoFall(nearFall: false);
      },
      onNearFall: () async {
        await _handleAutoFall(nearFall: true);
      },
    );

    _sensorMonitor!.start();

    // 🔹 Liga também o serviço nativo de queda (Foreground Service em Kotlin)
    try {
      await WearFallServiceBridge.start();
      // Opcional: feedback visual no relógio
      _mostrarDebug(
        'Serviço de quedas (Kotlin) iniciado ✓',
        color: Colors.greenAccent,
      );
    } catch (e) {
      debugPrint('Erro ao iniciar serviço nativo de quedas: $e');
      _mostrarDebug(
        'Falha ao iniciar serviço nativo ✗',
        color: Colors.redAccent,
      );
    }
  }

  /// Pequeno helper para debug visual no relógio (para o TCC)
  void _mostrarDebug(String msg, {Color color = Colors.white}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey.shade800,
        duration: const Duration(seconds: 2),
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 11),
        ),
      ),
    );
  }

  Future<void> _handleAutoFall({required bool nearFall}) async {
    if (!mounted) return;

    setState(() {
      _statusType = nearFall
          ? StatusAlertType.nearFall
          : StatusAlertType.fallReal;
      _statusTitulo = nearFall
          ? 'Quase queda detectada'
          : 'Queda detectada pelos sensores';
      _statusDescricao = nearFall
          ? 'O relógio identificou um desequilíbrio forte.'
          : 'O relógio identificou uma possível queda.';
      _pulse = true;
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _pulse = false);
    });

    final evento = FallEvent(
      timestamp: DateTime.now(),
      simulated: false,
      nearFall: nearFall,
      destinos: const [], // celular decide os destinos reais
      origin: 'watch',
      statusEnvio: 'desconhecido',
    );

    try {
      await WearContactsBridge.instance.sendFallEventToPhone(evento);
      _mostrarDebug(
        nearFall
            ? 'Evento de QUASE QUEDA enviado ao celular ✓'
            : 'Evento de QUEDA enviado ao celular ✓',
        color: Colors.greenAccent,
      );
    } catch (e) {
      debugPrint('Erro ao enviar evento de queda pro celular: $e');
      _mostrarDebug(
        'Falha ao enviar evento ao celular ✗',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> _enviarAlertaManualFromWatch() async {
    setState(() {
      _isSendingFromWatch = true;
    });

    final evento = FallEvent(
      timestamp: DateTime.now(),
      simulated: false,
      nearFall: false,
      destinos: const [],
      origin: 'watch',
      statusEnvio: 'desconhecido',
    );

    try {
      await WearContactsBridge.instance.sendFallEventToPhone(evento);

      _mostrarDebug('SOS enviado ao celular ✓', color: Colors.greenAccent);

      if (!mounted) return;
      setState(() {
        _statusType = StatusAlertType.fallReal;
        _statusTitulo = 'SOS enviado';
        _statusDescricao =
            'O alerta manual foi enviado. O celular está notificando os contatos.';
        _pulse = true;
      });

      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _pulse = false);
      });
    } catch (e) {
      debugPrint('Erro ao enviar SOS pro celular: $e');
      _mostrarDebug('Erro ao enviar SOS ✗', color: Colors.redAccent);
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _isSendingFromWatch = false;
        });
      });
    }
  }

  void _toggleDarkMode() {
    setState(() {
      _watchDarkMode = !_watchDarkMode;
    });
  }

  void _openSensorDebug() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SensorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HomeWearLayout(
      statusType: _statusType,
      statusTitulo: _statusTitulo,
      statusDescricao: _statusDescricao,
      pulse: _pulse,
      watchDarkMode: _watchDarkMode,
      isSendingFromWatch: _isSendingFromWatch,
      statusColor: _statusColor,
      onSendSOS: _enviarAlertaManualFromWatch,
      onToggleDarkMode: _toggleDarkMode,
      onOpenSensorDebug: _openSensorDebug,
    );
  }
}

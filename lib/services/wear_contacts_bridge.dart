// lib/services/wear_contacts_bridge.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:dropwarnify/models/watch_location.dart';
import 'package:dropwarnify/models/fall_event.dart';
import 'package:dropwarnify/services/fall_history_repository.dart';
import 'package:dropwarnify/screens/home/home_shared.dart'
    show EmergencyContact;

/// Bridge para sincronizar contatos, eventos e localização entre celular e relógio.
///
/// No relógio:
///   - pede contatos para o celular via MethodChannel/Data Layer;
///   - envia evento de queda (SOS / auto-quedas) para o celular registrar no histórico
///     e disparar os canais de alerta (SMS/Whats) do lado do telefone.
///
/// No celular:
///   - implementa o canal para responder com os contatos;
///   - recebe eventos de queda vindos do relógio e:
///       1) registra no histórico unificado;
///       2) emite no stream [watchEventsStream] para a Home reagir (enviar SMS/Whats);
///   - recebe também atualizações de localização do relógio
///       e emite no stream [watchLocationStream].
class WearContactsBridge {
  WearContactsBridge._() {
    // Registra o handler para receber callbacks do nativo (Kotlin)
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final WearContactsBridge instance = WearContactsBridge._();

  static const MethodChannel _channel = MethodChannel(
    'br.com.dropwarnify/wear_contacts',
  );

  /// Completer usado apenas durante a requisição de contatos (lado do relógio).
  Completer<List<EmergencyContact>?>? _pendingContactsRequest;

  /// Stream de eventos de queda vindos do relógio (no CELULAR).
  ///
  /// Somente o app rodando no telefone deve se inscrever aqui
  /// (por exemplo, a HomeScreen) para disparar as rotinas de alerta.
  final StreamController<FallEvent> _watchEventsController =
      StreamController<FallEvent>.broadcast();

  Stream<FallEvent> get watchEventsStream => _watchEventsController.stream;

  /// 🔹 NOVO: stream de localização enviada pelo relógio.
  ///
  /// O lado Flutter no CELULAR pode ouvir esse stream para:
  ///   - atualizar a tela de localização com a posição do relógio;
  ///   - exibir “Fonte: relógio” em vez de “este dispositivo”, etc.
  final StreamController<WatchLocation> _watchLocationController =
      StreamController<WatchLocation>.broadcast();

  Stream<WatchLocation> get watchLocationStream =>
      _watchLocationController.stream;

  /// Tenta buscar a lista de contatos do CELULAR.
  ///
  /// No relógio:
  ///   - envia "requestContactsFromPhone" para o Kotlin;
  ///   - aguarda "onContactsReceived" com um JSON de lista.
  ///
  /// No celular (ou se não houver integração):
  ///   - simplesmente retorna null (cai no catch / MissingPluginException).
  Future<List<EmergencyContact>?> getContactsFromPhone() async {
    // Se já houver uma requisição pendente, reaproveita a mesma Future.
    if (_pendingContactsRequest != null) {
      return _pendingContactsRequest!.future;
    }

    final completer = Completer<List<EmergencyContact>?>();
    _pendingContactsRequest = completer;

    try {
      // Dispara para o nativo do relógio, que por sua vez chama o celular.
      await _channel.invokeMethod<void>('requestContactsFromPhone');

      // Aguarda a resposta vinda de _handleNativeCallback (onContactsReceived).
      final result = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );

      _pendingContactsRequest = null;
      return result;
    } on MissingPluginException {
      // Canal não implementado (por ex., rodando no celular) -> sem problema.
      _pendingContactsRequest = null;
      return null;
    } catch (e, st) {
      debugPrint('WearContactsBridge.getContactsFromPhone erro: $e\n$st');
      _pendingContactsRequest = null;
      return null;
    }
  }

  /// Envia um evento de queda (FallEvent) do RELÓGIO para o CELULAR,
  /// para que o telefone registre no histórico (SharedPreferences) e,
  /// a partir daí, o app do CELULAR possa disparar SMS/Whats.
  ///
  /// No celular (ou se o canal não existir), isso simplesmente não faz nada.
  Future<void> sendFallEventToPhone(FallEvent event) async {
    try {
      // garantindo origin = "watch" ao enviar
      final map = event.toJson();
      if (!map.containsKey('origin') || map['origin'] == 'desconhecido') {
        map['origin'] = 'watch';
      }

      await _channel.invokeMethod<void>(
        'send_fall_event_to_phone',
        map, // enviado como Map<String, dynamic> para o nativo
      );
    } on MissingPluginException {
      // Canal não existe (provavelmente rodando no celular) -> ignora.
    } catch (e, st) {
      debugPrint('WearContactsBridge.sendFallEventToPhone erro: $e\n$st');
      // qualquer erro aqui não deve quebrar o fluxo do SOS no relógio.
    }
  }

  /// Handler chamado pelo código nativo (Kotlin) via MethodChannel.
  ///
  /// - "onContactsReceived": JSON de lista de contatos.
  /// - "onFallEventFromWatch": JSON de um FallEvent vindo do relógio.
  /// - "onWatchLocationUpdated": JSON com a localização do relógio.
  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    // ==========================
    // 1) CONTATOS
    // ==========================
    if (call.method == 'onContactsReceived') {
      final jsonStr = call.arguments as String?;

      if (_pendingContactsRequest == null) {
        // Não tem ninguém esperando, só ignora.
        return null;
      }

      if (jsonStr == null || jsonStr.trim().isEmpty) {
        _pendingContactsRequest!.complete(null);
        _pendingContactsRequest = null;
        return null;
      }

      try {
        final decoded = jsonDecode(jsonStr) as List<dynamic>;
        final contatos = decoded
            .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
            .toList();
        _pendingContactsRequest!.complete(contatos);
      } catch (e, st) {
        debugPrint('WearContactsBridge.onContactsReceived erro: $e\n$st');
        _pendingContactsRequest!.complete(null);
      } finally {
        _pendingContactsRequest = null;
      }

      return null;
    }

    // ==========================
    // 2) EVENTO DE QUEDA (WATCH → PHONE)
    // ==========================
    if (call.method == 'onFallEventFromWatch') {
      final jsonStr = call.arguments as String?;
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return null;
      }

      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;

        // reforça origin = "watch" (caso venha sem ou errado)
        map['origin'] = 'watch';

        final event = FallEvent.fromJson(map);

        // grava no histórico local do CELULAR
        await FallHistoryRepository.instance.registrarEvento(event);

        // notifica listeners (por exemplo, HomeScreen no CELULAR)
        _watchEventsController.add(event);
      } catch (e, st) {
        debugPrint('WearContactsBridge.onFallEventFromWatch erro: $e\n$st');
      }

      return null;
    }

    // ==========================
    // 3) LOCALIZAÇÃO DO RELÓGIO (WATCH → PHONE)
    // ==========================
    if (call.method == 'onWatchLocationUpdated') {
      final jsonStr = call.arguments as String?;
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return null;
      }

      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final loc = WatchLocation.fromJson(map);
        _watchLocationController.add(loc);
      } catch (e, st) {
        debugPrint('WearContactsBridge.onWatchLocationUpdated erro: $e\n$st');
      }

      return null;
    }

    return null;
  }
}

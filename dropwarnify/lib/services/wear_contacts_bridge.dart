import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../screens/home/home_screen.dart' show EmergencyContact;

/// Bridge para sincronizar contatos entre celular e relógio.
/// No relógio, ele pede contatos para o celular via MethodChannel/Data Layer.
/// No celular, esse canal pode simplesmente não estar implementado (e tudo bem).
class WearContactsBridge {
  WearContactsBridge._() {
    // Registra o handler para receber callbacks do nativo
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final WearContactsBridge instance = WearContactsBridge._();

  static const MethodChannel _channel = MethodChannel(
    'br.com.dropwarnify/wear_contacts',
  );

  Completer<List<EmergencyContact>?>? _pendingContactsRequest;

  /// Tenta buscar a lista de contatos do CELULAR.
  /// No relógio:
  ///   - envia "requestContactsFromPhone" para o Kotlin
  ///   - aguarda "onContactsReceived" com um JSON de lista
  ///
  /// No celular (ou se não houver integração):
  ///   - simplesmente retorna null (cai no catch / MissingPluginException).
  Future<List<EmergencyContact>?> getContactsFromPhone() async {
    // Se já houver uma requisição pendente, reaproveita a mesma Future
    if (_pendingContactsRequest != null) {
      return _pendingContactsRequest!.future;
    }

    final completer = Completer<List<EmergencyContact>?>();
    _pendingContactsRequest = completer;

    try {
      // Dispara para o nativo do relógio, que por sua vez chama o celular
      await _channel.invokeMethod<void>('requestContactsFromPhone');

      // Aguarda a resposta vinda de _handleNativeCallback (onContactsReceived)
      final result = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );

      _pendingContactsRequest = null;
      return result;
    } on MissingPluginException {
      // Canal não implementado (por ex., rodando no celular) -> sem problema
      _pendingContactsRequest = null;
      return null;
    } catch (_) {
      _pendingContactsRequest = null;
      return null;
    }
  }

  /// Handler chamado pelo código nativo (Kotlin) via MethodChannel.
  /// Espera o método "onContactsReceived" com um JSON de lista de contatos:
  /// [ { "name": "...", "phone": "..." }, ... ]
  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'onContactsReceived') {
      final jsonStr = call.arguments as String?;

      if (_pendingContactsRequest == null) {
        // Não tem ninguém esperando, só ignora
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
      } catch (_) {
        _pendingContactsRequest!.complete(null);
      } finally {
        _pendingContactsRequest = null;
      }
    }

    return null;
  }
}

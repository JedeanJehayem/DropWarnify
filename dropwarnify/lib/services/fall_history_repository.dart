import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropwarnify/models/fall_event.dart';

class FallHistoryRepository {
  FallHistoryRepository._();
  static final FallHistoryRepository instance = FallHistoryRepository._();

  static const _fallEventsKeyRaw = 'flutter.fall_events';
  static const _fallEventsPrefix = 'This is the prefix for a list.';

  Future<void> registrarEvento(FallEvent event) async {
    final prefs = await SharedPreferences.getInstance();

    // lê string bruta atual
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

    // adiciona o novo evento
    list.add(jsonEncode(event.toJson()));

    // salva no mesmo formato do Android
    final newRaw = _fallEventsPrefix + jsonEncode(list);
    await prefs.setString(_fallEventsKeyRaw, newRaw);

    // limpa chave antiga, se existir
    await prefs.remove('fall_events');
  }
}

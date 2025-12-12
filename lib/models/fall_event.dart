import 'dart:convert';

class FallEvent {
  final DateTime timestamp;
  final bool simulated;
  final bool nearFall; // se é QUASE QUEDA
  final List<String> destinos; // ex: ["Lolo (SMS)", "Ana (WhatsApp)"]

  /// "phone" ou "watch" (ou outro no futuro)
  final String origin;

  /// "ok", "falha", "offline", "desconhecido"
  final String statusEnvio;

  FallEvent({
    required this.timestamp,
    required this.simulated,
    required this.nearFall,
    required this.destinos,
    this.origin = 'unknown',
    this.statusEnvio = 'desconhecido',
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'simulated': simulated,
    'nearFall': nearFall,
    'destinos': destinos,
    'origin': origin,
    'statusEnvio': statusEnvio,
  };

  factory FallEvent.fromJson(Map<String, dynamic> json) {
    return FallEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      simulated: json['simulated'] as bool? ?? false,
      nearFall: json['nearFall'] as bool? ?? false,
      destinos: (json['destinos'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      origin: json['origin'] as String? ?? 'unknown',
      statusEnvio: json['statusEnvio'] as String? ?? 'desconhecido',
    );
  }

  /// Helper opcional se quiser salvar direto como String
  String toJsonString() => jsonEncode(toJson());

  factory FallEvent.fromJsonString(String s) =>
      FallEvent.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

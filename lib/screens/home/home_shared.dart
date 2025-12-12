// lib/screens/home/home_shared.dart

import 'package:flutter/material.dart';

/// Enum unificado para os status de alerta
enum StatusAlertType { none, fallReal, fallSimulated, nearFall }

/// Classe unificada de contatos utilizada pelo mobile e pelo wear
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

/// Cor correspondente ao status
Color statusColorFor(StatusAlertType type) {
  switch (type) {
    case StatusAlertType.none:
      return Colors.green;

    case StatusAlertType.fallReal:
      return Colors.red;

    case StatusAlertType.fallSimulated:
      return Colors.orange;

    case StatusAlertType.nearFall:
      return Colors.amber;
  }

  // Nunca chega aqui, mas mantém o return para segurança do Dart
  // (sem usar default)
  // ignore: dead_code
  return Colors.green;
}

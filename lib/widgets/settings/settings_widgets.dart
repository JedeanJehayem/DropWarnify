// lib/widgets/settings/settings_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ===============================
/// FORMATADOR DE TELEFONE
/// ===============================
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (i == 7) buffer.write('-');
      buffer.write(digits[i]);
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

/// ===============================
/// MODELO DE CONTATO
/// ===============================
class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}

/// ===============================
/// WIDGETS REUTILIZÁVEIS
/// ===============================

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}

class UserInfoSection extends StatelessWidget {
  const UserInfoSection({
    super.key,
    required this.nomeController,
    required this.telefoneController,
    required this.onClearNome,
    required this.onClearTelefone,
  });

  final TextEditingController nomeController;
  final TextEditingController telefoneController;
  final VoidCallback onClearNome;
  final VoidCallback onClearTelefone;

  OutlineInputBorder _roundedBorder(Color? color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color ?? Colors.grey.shade400, width: 1.2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        TextField(
          controller: nomeController,
          decoration: InputDecoration(
            labelText: 'Nome do idoso',
            border: _roundedBorder(null),
            enabledBorder: _roundedBorder(Colors.grey.shade400),
            focusedBorder: _roundedBorder(primary),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: onClearNome,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: telefoneController,
          decoration: InputDecoration(
            labelText: 'Telefone do idoso',
            hintText: '(00) 00000-0000',
            border: _roundedBorder(null),
            enabledBorder: _roundedBorder(Colors.grey.shade400),
            focusedBorder: _roundedBorder(primary),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: onClearTelefone,
            ),
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            PhoneInputFormatter(),
          ],
        ),
      ],
    );
  }
}

class EmergencyContactsSection extends StatelessWidget {
  const EmergencyContactsSection({
    super.key,
    required this.contacts,
    required this.onRemoveContact,
    required this.onAddPressed,
  });

  final List<EmergencyContact> contacts;
  final void Function(int index) onRemoveContact;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        if (contacts.isEmpty)
          Text(
            'Nenhum contato de emergência adicionado.\n'
            'Use o botão abaixo para adicionar.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          )
        else
          Column(
            children: List.generate(contacts.length, (index) {
              final c = contacts[index];
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: primary.withOpacity(0.08),
                    child: Text(
                      c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(c.name.isNotEmpty ? c.name : 'Contato sem nome'),
                  subtitle: Text(c.phone),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => onRemoveContact(index),
                  ),
                ),
              );
            }),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.person_add),
            label: const Text('Adicionar contato'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: primary, width: 1.4),
              foregroundColor: primary,
            ),
          ),
        ),
      ],
    );
  }
}

class PreferencesSection extends StatelessWidget {
  const PreferencesSection({
    super.key,
    required this.detecQuedaAtivada,
    required this.enviarSMS,
    required this.enviarWhatsApp,
    required this.alertarNearFall,
    required this.onDetecQuedaChanged,
    required this.onEnviarSmsChanged,
    required this.onEnviarWhatsChanged,
    required this.onNearFallChanged,
  });

  final bool detecQuedaAtivada;
  final bool enviarSMS;
  final bool enviarWhatsApp;
  final bool alertarNearFall;

  final ValueChanged<bool> onDetecQuedaChanged;
  final ValueChanged<bool> onEnviarSmsChanged;
  final ValueChanged<bool> onEnviarWhatsChanged;
  final ValueChanged<bool> onNearFallChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Detecção de quedas ativada'),
          value: detecQuedaAtivada,
          onChanged: onDetecQuedaChanged,
        ),
        SwitchListTile(
          title: const Text('Enviar alerta por SMS'),
          value: enviarSMS,
          onChanged: onEnviarSmsChanged,
        ),
        SwitchListTile(
          title: const Text('Enviar alerta por WhatsApp'),
          value: enviarWhatsApp,
          onChanged: onEnviarWhatsChanged,
        ),
        SwitchListTile(
          title: const Text('Enviar alerta de QUASE QUEDA'),
          subtitle: const Text(
            'Envia alerta quando detectar desequilíbrio forte.',
          ),
          value: alertarNearFall,
          onChanged: onNearFallChanged,
        ),
      ],
    );
  }
}

class SettingsActions extends StatelessWidget {
  const SettingsActions({
    super.key,
    required this.onSalvar,
    required this.onTestarAlertas,
  });

  final VoidCallback onSalvar;
  final VoidCallback onTestarAlertas;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSalvar,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Salvar configurações',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onTestarAlertas,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: primary.withOpacity(0.7), width: 1.2),
              foregroundColor: primary,
            ),
            child: const Text(
              'Testar chamada/SMS / WhatsApp',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}

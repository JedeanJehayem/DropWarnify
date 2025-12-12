import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dropwarnify/widgets/settings/settings_widgets.dart';

/// ===============================
/// TELA DE CONFIGURAÇÕES
/// ===============================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Campos do idoso
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();

  // Lista de contatos de emergência
  List<EmergencyContact> _contacts = [];

  bool detecQuedaAtivada = true;
  bool enviarSMS = false;
  bool enviarWhatsApp = false;

  // 🔹 NOVO: preferências de alerta de QUASE QUEDA
  bool _alertarNearFall = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  /// Carrega os dados salvos no dispositivo
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final nomeIdoso = prefs.getString('nome_idoso') ?? '';
    final telefoneIdoso = prefs.getString('telefone_idoso') ?? '';
    final detec = prefs.getBool('detec_queda') ?? true;
    final sms = prefs.getBool('enviar_sms') ?? false;
    final whatsapp = prefs.getBool('enviar_whatsapp') ?? false;
    final alertNearFall =
        prefs.getBool('alertar_quase_queda') ?? false; // 🔹 NOVO

    // Contatos salvos como lista JSON
    final listStr = prefs.getStringList('emergency_contacts') ?? [];
    List<EmergencyContact> loadedContacts = [];

    if (listStr.isNotEmpty) {
      loadedContacts = listStr
          .map((s) => EmergencyContact.fromJson(jsonDecode(s)))
          .toList();
    } else {
      // Backward compatibility: migra 1 contato antigo, se existir
      final oldName = prefs.getString('contato_nome') ?? '';
      final oldPhone = prefs.getString('contato_telefone') ?? '';
      if (oldName.isNotEmpty && oldPhone.isNotEmpty) {
        loadedContacts.add(EmergencyContact(name: oldName, phone: oldPhone));
      }
    }

    setState(() {
      _nomeController.text = nomeIdoso;
      _telefoneController.text = telefoneIdoso;
      detecQuedaAtivada = detec;
      enviarSMS = sms;
      enviarWhatsApp = whatsapp;
      _alertarNearFall = alertNearFall; // 🔹 NOVO
      _contacts = loadedContacts;
    });
  }

  /// Valida se o telefone tem quantidade mínima de dígitos (ex: 10 ou 11)
  bool _isValidPhone(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10; // aceita 10 ou 11 dígitos
  }

  /// Normaliza telefone para uso em URIs (+55DDXXXXXXXXX)
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
    final normalized = '55$digits'; // wa.me usa 55DDXXXXXXXXX
    final encodedMsg = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$normalized?text=$encodedMsg');
  }

  /// Salva as configurações no dispositivo
  Future<void> _saveSettings() async {
    final telefoneIdoso = _telefoneController.text.trim();

    if (!_isValidPhone(telefoneIdoso)) {
      _showSnack('Preencha um telefone válido para o idoso.');
      return;
    }

    if (_contacts.isEmpty) {
      _showSnack('Adicione pelo menos um contato de emergência.');
      return;
    }

    for (final c in _contacts) {
      if (!_isValidPhone(c.phone)) {
        _showSnack(
          'Telefone inválido no contato: '
          '${c.name.isEmpty ? "(sem nome)" : c.name}',
        );
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('nome_idoso', _nomeController.text.trim());
    await prefs.setString('telefone_idoso', telefoneIdoso);

    final listStr = _contacts
        .map((c) => jsonEncode(c.toJson()))
        .toList(growable: false);
    await prefs.setStringList('emergency_contacts', listStr);

    final first = _contacts.first;
    await prefs.setString('contato_nome', first.name);
    await prefs.setString('contato_telefone', first.phone);

    await prefs.setBool('detec_queda', detecQuedaAtivada);
    await prefs.setBool('enviar_sms', enviarSMS);
    await prefs.setBool('enviar_whatsapp', enviarWhatsApp);
    await prefs.setBool('alertar_quase_queda', _alertarNearFall);

    _showSnack('Configurações salvas com sucesso.');
  }

  Future<void> _testarEnvioAlerta() async {
    if (_contacts.isEmpty) {
      _showSnack(
        'Nenhum contato de emergência cadastrado. Adicione um contato antes de testar.',
      );
      return;
    }

    if (!enviarSMS && !enviarWhatsApp) {
      _showSnack('Selecione ao menos um canal (SMS ou WhatsApp).');
      return;
    }

    for (final c in _contacts) {
      if (!_isValidPhone(c.phone)) continue;

      final msgBase =
          'Alerta de teste do DropWarnify para '
          '${c.name.isEmpty ? "contato de emergência" : c.name}. '
          'Este é apenas um teste.';

      if (enviarSMS) {
        final smsUri = _buildSmsUri(c.phone, msgBase);
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        }
      }

      if (enviarWhatsApp) {
        final waUri = _buildWhatsAppUri(c.phone, msgBase);
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
        }
      }
    }

    _showSnack('Teste enviado para os contatos configurados.');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo contato de emergência'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                hintText: '(00) 00000-0000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();

              if (!_isValidPhone(phone)) {
                _showSnack('Informe um telefone válido para o contato.');
                return;
              }

              setState(() {
                _contacts.add(EmergencyContact(name: name, phone: phone));
              });

              Navigator.pop(context);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  void _removeContact(int index) {
    setState(() {
      _contacts.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const SectionTitle('Informações do Usuário'),
            const SizedBox(height: 12),

            UserInfoSection(
              nomeController: _nomeController,
              telefoneController: _telefoneController,
              onClearNome: () => setState(() => _nomeController.clear()),
              onClearTelefone: () =>
                  setState(() => _telefoneController.clear()),
            ),

            const SizedBox(height: 24),

            const SectionTitle('Contatos de Emergência'),
            const SizedBox(height: 12),

            EmergencyContactsSection(
              contacts: _contacts,
              onRemoveContact: _removeContact,
              onAddPressed: _openAddContactDialog,
            ),

            const SizedBox(height: 24),

            const SectionTitle('Preferências'),
            const SizedBox(height: 12),

            PreferencesSection(
              detecQuedaAtivada: detecQuedaAtivada,
              enviarSMS: enviarSMS,
              enviarWhatsApp: enviarWhatsApp,
              alertarNearFall: _alertarNearFall,
              onDetecQuedaChanged: (v) => setState(() => detecQuedaAtivada = v),
              onEnviarSmsChanged: (v) => setState(() => enviarSMS = v),
              onEnviarWhatsChanged: (v) => setState(() => enviarWhatsApp = v),
              onNearFallChanged: (v) => setState(() => _alertarNearFall = v),
            ),

            const SizedBox(height: 24),

            SettingsActions(
              onSalvar: _saveSettings,
              onTestarAlertas: _testarEnvioAlerta,
            ),
          ],
        ),
      ),
    );
  }
}

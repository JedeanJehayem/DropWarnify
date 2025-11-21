import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// ===============================
/// FORMATADOR DE TELEFONE
/// ===============================
/// Formata automaticamente:
/// 11987654321 → (11) 98765-4321
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Apenas dígitos
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limite de 11 dígitos
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    StringBuffer buffer = StringBuffer();

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
/// MODELO DE CONTATO DE EMERGÊNCIA
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
    // Se já começar com 55, só adiciona o +
    if (digits.startsWith('55')) return '+$digits';
    // Assume Brasil
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

  /// WhatsApp Web / App (funciona no PC via navegador também)
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha um telefone válido para o idoso.'),
        ),
      );
      return;
    }

    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um contato de emergência.'),
        ),
      );
      return;
    }

    // valida todos os contatos
    for (final c in _contacts) {
      if (!_isValidPhone(c.phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Telefone inválido no contato: ${c.name.isEmpty ? "(sem nome)" : c.name}',
            ),
          ),
        );
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();

    // Idoso
    await prefs.setString('nome_idoso', _nomeController.text.trim());
    await prefs.setString('telefone_idoso', telefoneIdoso);

    // Contatos: lista JSON
    final listStr = _contacts
        .map((c) => jsonEncode(c.toJson()))
        .toList(growable: false);
    await prefs.setStringList('emergency_contacts', listStr);

    // Backward compatibility: primeiro contato
    final first = _contacts.first;
    await prefs.setString('contato_nome', first.name);
    await prefs.setString('contato_telefone', first.phone);

    // Flags
    await prefs.setBool('detec_queda', detecQuedaAtivada);
    await prefs.setBool('enviar_sms', enviarSMS);
    await prefs.setBool('enviar_whatsapp', enviarWhatsApp);
    await prefs.setBool('alertar_quase_queda', _alertarNearFall); // 🔹 NOVO

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configurações salvas com sucesso.')),
    );
  }

  /// Teste real:
  /// - SMS: tenta abrir app de SMS (em celular)
  /// - WhatsApp: abre WhatsApp Web / App (no PC abre navegador)
  Future<void> _testarEnvioAlerta() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum contato de emergência cadastrado. Adicione um contato antes de testar.',
          ),
        ),
      );
      return;
    }

    if (!enviarSMS && !enviarWhatsApp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um canal (SMS ou WhatsApp).'),
        ),
      );
      return;
    }

    for (final c in _contacts) {
      if (!_isValidPhone(c.phone)) continue;

      final msgBase =
          'Alerta de teste do DropWarnify para ${c.name.isEmpty ? "contato de emergência" : c.name}. Este é apenas um teste.';

      // SMS (funciona em celular; no PC geralmente não abre nada)
      if (enviarSMS) {
        final smsUri = _buildSmsUri(c.phone, msgBase);
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        }
      }

      // WhatsApp Web / App (no PC abre navegador, no celular abre app)
      if (enviarWhatsApp) {
        final waUri = _buildWhatsAppUri(c.phone, msgBase);
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teste enviado para os contatos configurados.'),
      ),
    );
  }

  /// Abre diálogo para adicionar novo contato
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe um telefone válido para o contato.'),
                  ),
                );
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

  /// Remove contato na posição indicada
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
            const Text(
              'Informações do Usuário',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // Nome do idoso
            TextField(
              controller: _nomeController,
              decoration: InputDecoration(
                labelText: 'Nome do idoso',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _nomeController.clear()),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Telefone do idoso com máscara
            TextField(
              controller: _telefoneController,
              decoration: InputDecoration(
                labelText: 'Telefone do idoso',
                hintText: '(00) 00000-0000',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _telefoneController.clear()),
                ),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
            ),

            const SizedBox(height: 24),

            const Text(
              'Contatos de Emergência',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // Lista de contatos
            if (_contacts.isEmpty)
              Text(
                'Nenhum contato de emergência adicionado.\n'
                'Use o botão abaixo para cadastrar um ou mais contatos.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              )
            else
              Column(
                children: List.generate(_contacts.length, (index) {
                  final c = _contacts[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                        ),
                      ),
                      title: Text(
                        c.name.isNotEmpty ? c.name : 'Contato sem nome',
                      ),
                      subtitle: Text(c.phone),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeContact(index),
                      ),
                    ),
                  );
                }),
              ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _openAddContactDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Adicionar contato de emergência'),
            ),

            const SizedBox(height: 24),

            const Text(
              'Preferências',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            SwitchListTile(
              title: const Text('Detecção de quedas ativada'),
              value: detecQuedaAtivada,
              onChanged: (val) => setState(() => detecQuedaAtivada = val),
            ),

            SwitchListTile(
              title: const Text('Enviar alerta por SMS'),
              value: enviarSMS,
              onChanged: (val) => setState(() => enviarSMS = val),
            ),

            SwitchListTile(
              title: const Text('Enviar alerta por WhatsApp'),
              value: enviarWhatsApp,
              onChanged: (val) => setState(() => enviarWhatsApp = val),
            ),

            // 🔹 NOVO: preferência de quase queda
            SwitchListTile(
              title: const Text('Enviar alerta de QUASE QUEDA'),
              subtitle: const Text(
                'Quando detectar um desequilíbrio forte (quase queda), enviar alerta como precaução.',
              ),
              value: _alertarNearFall,
              onChanged: (val) {
                setState(() => _alertarNearFall = val);
              },
            ),

            const SizedBox(height: 24),

            // Botões de ação
            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Salvar configurações'),
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: _testarEnvioAlerta,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Testar chamada/SMS / WhatsApp'),
            ),
          ],
        ),
      ),
    );
  }
}

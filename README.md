# 🚨 DropWarnify
### Sistema Inteligente de Detecção e Alerta de Quedas  
Flutter • Android • Wear OS

---

<div align="center">
  <img src="https://img.shields.io/badge/Flutter-3.22+-blue?logo=flutter" />
  <img src="https://img.shields.io/badge/Wear%20OS-Data%20Layer-green?logo=wearos" />
  <img src="https://img.shields.io/badge/Platform-Android-informational?logo=android" />
  <img src="https://img.shields.io/badge/Status-Em%20Desenvolvimento-yellow" />
</div>

---

## 📘 Sobre o Projeto

**DropWarnify** é um sistema completo de detecção e alerta de quedas integrado entre **celular + smartwatch Wear OS**, capaz de:

- monitorar sensores internos (acelerômetro / giroscópio)
- detectar quedas e quase quedas
- enviar alertas automáticos (SMS/WhatsApp)
- compartilhar localização aproximada
- permitir acionamento manual via SOS no relógio
- sincronizar contatos do celular para o relógio

Hoje o projeto evoluiu com **monitoramento contínuo de sensores no Wear OS**, reorganização da arquitetura e início da preparação para integração com o **Mobile-Hub2 + ContextNet**.

---

## 🆕 Atualizações de Hoje (01/12/2025)

### 🔥 1. **Novo serviço nativo de sensores (Wear OS)**

Criado:

```
android/app/src/main/kotlin/.../FallDetectionService.kt
```

Funções principais:

- Roda em **Foreground Service**
- Mantém sensores ativos mesmo com o app fechado
- Coleta sensores acelerômetro/giroscópio
- Envia eventos para Flutter via MethodChannel
- Preparado para transmissão ao celular e backend

Permissões adicionadas:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

---

### 📡 2. **Novo WearSensorMonitor (Flutter)**

Criado:

```
lib/services/wear_sensor_monitor.dart
```

- Faz leitura em tempo real dos sensores enviados pelo serviço nativo
- Detecta padrões de queda
- Pode rodar enquanto a UI está fechada

---

### 🔗 3. **Nova ponte Wear → Phone (fall_service_bridge)**

Criado:

```
lib/wear/fall_service_bridge.dart
```

- Enviará eventos de SOS
- Transmitirá amostras do acelerômetro no futuro
- Preparado para integração com Mobile-Hub2 (MR-UDP / MQTT)

---

### 🗃 4. **Novo módulo central de histórico**

```
lib/services/fall_history_repository.dart
```

Agora o histórico:

- não depende mais da UI
- é centralizado
- será utilizado por relógio + celular

---

### 🧹 5. **Limpeza e reestruturação geral**

- Removido `sensor_service.dart`
- Criado `wear_sensor_monitor.dart`
- Criado `fall_service_bridge.dart`
- Atualizado `home_screen.dart`, `sensor_screen.dart`, `history_screen.dart`
- Atualizado `PhoneWearContactsService.kt`
- Corrigido `MainActivity.kt`
- `pubspec.yaml` e `pubspec.lock` atualizados
- Regeneração de plugins do macOS
- Ícone temporário `flutter_02.png` adicionado
- Removido widget_test default

---

### 🧠 6. **Preparação para integração com Mobile-Hub2 + ContextNet**

O projeto agora está preparado para:

- enviar dados do relógio para o backend
- trabalhar com módulos: Core, WPAN, WWAN, MR-UDP, MQTT
- usar o middleware distribuído descrito no artigo IEEE

---

## 🏗 Arquitetura do Sistema

```
Flutter App (Phone)
   ├─ Geolocalização + Reverse Geocoding
   ├─ Histórico de quedas
   ├─ Envio automático de alertas
   ├─ Sincronização de contatos
   └─ Interface SOS

Wear OS (Watch)
   ├─ FallDetectionService (Kotlin)
   ├─ WearSensorMonitor (Flutter)
   ├─ Botão SOS
   ├─ Tela “Enviando alerta…”
   └─ Sincronização automática de contatos

Comunicação Celular ↔ Relógio
   ├─ Data Layer API (Kotlin)
   ├─ MessageClient / NodeClient
   ├─ MethodChannel (Flutter ↔ Android)
   └─ JSON com contatos e eventos
```

---

## ⚙ Tecnologias

| Área | Tecnologia |
|------|------------|
| App Mobile | Flutter 3.22+ |
| Relógio | Wear OS + Kotlin |
| Sensores | Acelerômetro / Giroscópio |
| Persistência | SharedPreferences |
| Comunicação | Data Layer + MethodChannel |
| Localização | geolocator + geocoding |
| Backend futuro | Mobile-Hub2 + ContextNet |

---

## 📡 Status Atual

- ✔ Sincronização de contatos funcional
- ✔ Foreground Service do relógio funcionando
- ✔ Monitoramento de sensores integrado ao Flutter
- ✔ Histórico revisado e centralizado
- ❗ Falta pareamento real do Wear OS para sincronização completa
- ❗ Envio de sensores ao celular pendente
- ⏳ Preparação para Mobile-Hub2 iniciada

---

## 🎯 Roadmap

- [ ] Parear Wear OS real
- [ ] Transmitir sensores do relógio → celular
- [ ] Detecção de queda 100% no wearable
- [ ] Enviar SOS diretamente do relógio
- [ ] Integrar Mobile-Hub2 (MR-UDP / MQTT)
- [ ] Criar dashboard em nuvem
- [ ] Adicionar gráficos de movimento

---

## 📄 Licença

Projeto acadêmico — livre para estudo e evolução.

---

<div align="center">
Feito para o TCC — DropWarnify
</div>

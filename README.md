🚨 DropWarnify
Sistema Inteligente de Detecção e Alerta de Quedas

Flutter • Android • Wear OS

<div align="center"> <img src="https://img.shields.io/badge/Flutter-3.22+-blue?logo=flutter" /> <img src="https://img.shields.io/badge/Wear%20OS-Data%20Layer-green?logo=wearos" /> <img src="https://img.shields.io/badge/Platform-Android-informational?logo=android" /> <img src="https://img.shields.io/badge/Status-Em%20Desenvolvimento-yellow" /> </div>
📘 Sobre o Projeto

DropWarnify é um sistema completo de detecção e alerta de quedas integrado entre celular + smartwatch Wear OS, capaz de:

monitorar sensores internos (acelerômetro / giroscópio)

detectar quedas, quase quedas e movimentos bruscos

enviar alertas automáticos (SMS/WhatsApp)

enviar localização aproximada

permitir acionamento manual via SOS no relógio

sincronizar contatos do celular → relógio

Hoje o projeto ganhou grandes módulos novos, incluindo um serviço nativo no relógio que mantém sensores ativos continuamente.

🆕 Atualizações de Hoje (01/12/2025)
🔥 1. Implementação do serviço nativo de sensores (Wear OS)

Criamos o arquivo:

android/app/src/main/kotlin/.../FallDetectionService.kt


Esse serviço:

roda em Foreground (não é finalizado pelo Wear OS)

recebe sensores do relógio via Kotlin

envia dados para Flutter via MethodChannel

está preparado para transmitir amostras para o celular

Também adicionamos as permissões:

<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />

📡 2. Novo módulo WearSensorMonitor (Flutter)

Criado:

lib/services/wear_sensor_monitor.dart


Ele:

recebe dados em tempo real do serviço nativo

detecta quedas simples diretamente no relógio

mantém análise mesmo com o app fechado

🔗 3. Nova ponte Wear → Phone (fall_service_bridge.dart)

Criado:

lib/wear/fall_service_bridge.dart


Ele vai:

enviar sinais de SOS

sincronizar estado do sensor

transmitir eventos futuramente para o ContextNet (Mobile-Hub2)

🗃 4. Novo repositório de histórico centralizado

Criado:

lib/services/fall_history_repository.dart


Agora o histórico não depende mais apenas da UI.

🧹 5. Limpeza e reestruturação

Removido sensor_service.dart (obsoleto)

Ajustado home_screen.dart para usar monitoramento real

Ajustado history_screen.dart

Ajustado wear_contacts_bridge.dart

Atualizado pubspec.yaml

Corrigido MainActivity.kt e PhoneWearContactsService.kt

Criado ícone temporário flutter_02.png

Removido teste placeholder default do Flutter

🧠 6. Preparação para integração com Mobile-Hub2 + ContextNet

O projeto agora está pronto para:

enviar sensores do wearable para MR-UDP / MQTT

usar o middleware Mobile-Hub2 descrito no artigo IEEE

conectar-se ao backend inteligente de contexto

🏗 Arquitetura do Sistema
Flutter App (Phone)
   ├─ Geolocalização + Reverse Geocoding
   ├─ Histórico de quedas
   ├─ Envio de alertas SMS/WhatsApp
   ├─ Sincronização de contatos
   └─ Interface/SOS manual

Wear OS (Watch)
   ├─ FallDetectionService (nativo + foreground)
   ├─ WearSensorMonitor (Flutter)
   ├─ Botão SOS
   ├─ Modo Dark exclusivo
   └─ Envio de dados de sensores

Comunicação Celular ↔ Relógio
   ├─ Data Layer API (MessageClient/NodeClient)
   ├─ MethodChannel (Flutter ↔ Android nativo)
   └─ JSON com contatos e eventos

📡 Status Atual do Desenvolvimento

✔ Sincronização de contatos concluída

✔ Wear Sensor Service funcionando

✔ Monitor de sensores no Flutter funcional

✔ Queda detectada no relógio

✔ Histórico centralizado

❗ Falta pareamento real do Wear OS para testes de envio

⏳ Integração com backend Mobile-Hub2 em planejamento

🎯 Roadmap

 Pareamento real Wear OS

 Enviar sensores do relógio → celular

 Envio de SOS completo pelo relógio

 Integração com ContextNet/Mobile-Hub2

 Criar dashboard em nuvem

 Criar widget de status no Wear

📄 Licença

Projeto acadêmico — livre para estudo e evolução.

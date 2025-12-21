# 🚨 DropWarnify — Sistema Inteligente de Detecção e Alerta de Quedas
### *Flutter • Android • Wear OS • MobileHub • ContextNet • Kafka*

<div align="center">
  <img src="https://img.shields.io/badge/Flutter-3.22+-blue?logo=flutter" />
  <img src="https://img.shields.io/badge/Kotlin-Wear%20OS-green?logo=kotlin" />
  <img src="https://img.shields.io/badge/Android-Native-informational?logo=android" />
  <img src="https://img.shields.io/badge/Backend-ContextNet%20%2B%20Kafka-purple" />
  <img src="https://img.shields.io/badge/Status-Finalizado%20%2F%20TCC-yellow" />
</div>

---

## 📘 Sobre o Projeto

DropWarnify é um sistema completo de monitoramento, detecção e alerta de quedas, desenvolvido para acompanhar idosos e permitir resposta rápida de familiares ou cuidadores. A solução combina:

- App Flutter (Android + Wear OS)
- Serviços nativos Kotlin
- MobileHub (MR-UDP)
- Backend ContextNet + Kafka + Gateway + Processing Node + Mobile Node

O sistema coleta dados sensoriais, detecta eventos, envia alertas, processa informações distribuídas e disponibiliza visualização em tempo real.

---

## 🏗 Arquitetura Geral

```
Wear OS (Kotlin)
 ├─ FallDetectionService
 ├─ Coleta ACC/GYRO
 ├─ Botão SOS
 └─ JSON → Phone

Android (Flutter + Kotlin)
 ├─ WearServiceBridge
 ├─ MobileHub Publisher
 ├─ Histórico + localização
 └─ Alertas WhatsApp/SMS

MobileHub (Java)
 ├─ MR-UDP
 ├─ Encapsulamento JSON
 └─ Publicação Kafka

Backend (ContextNet + Kafka)
 ├─ Gateway
 ├─ Processing Node
 ├─ GroupDefiner
 └─ MobileNode (Dashboard)
```

---

## 🔥 Funcionalidades

### Wear OS
- Detecção de queda e quase queda
- Serviço persistente em Foreground
- Coleta contínua dos sensores
- Envio de snapshots e SOS

### Android
- Recepção de sensores
- Envio de eventos ao MobileHub
- Geolocalização e contatos
- Histórico de eventos

### Backend
- Pipeline distribuído completo
- Processamento de eventos
- Dashboard em tempo real

---

## ⚙ Tecnologias

| Camada | Tecnologias |
|-------|-------------|
| Wear OS | Kotlin, SensorManager |
| Android | Flutter 3.22+, Dart |
| Comunicação | Data Layer, MR-UDP |
| Backend | Kafka, Zookeeper, ContextNet |
| UI Web | MobileNode (WebSocket) |

---

## 🚧 Status Atual

- ✔ Wear OS funcional
- ✔ Aquisição de sensores
- ✔ MobileHub integrado
- ✔ Kafka + Processing Node operando
- ✔ MobileNode UI ativo
- ❗ Otimização de snapshots
- ❗ Ajustes finais no algoritmo

---

## 🎯 Roadmap Futuro

- [ ] Gráficos de movimento
- [ ] Melhorias de detecção
- [ ] App do cuidador
- [ ] Versão iOS
- [ ] Suporte para múltiplos idosos

---

## 🔗 Repositório Oficial
https://github.com/JedeanJehayem/DropWarnify

---

## 📄 Licença
Uso acadêmico – livre para estudo e pesquisa.

---

<div align="center">
<b>DropWarnify — TCC Finalizado</b>
<br/>PUC-Rio — 2025
</div>

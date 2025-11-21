
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

**DropWarnify** é um sistema completo de detecção de quedas integrado entre **celular + smartwatch Wear OS**, capaz de enviar alertas automáticos via SMS/WhatsApp, incluir localização aproximada e permitir acionamento manual pelo relógio.

Atualmente, o projeto está evoluindo para suportar **sincronização automática de contatos** entre celular e relógio, usando a *Wear OS Data Layer API*.

---

## 🏗 Arquitetura do Sistema

```
Flutter App (Phone)
   ├─ Leitura de sensores
   ├─ Envio de alertas (SMS / WhatsApp)
   ├─ Geolocalização + Reverse Geocoding
   ├─ Tela de status e histórico
   └─ Contatos em SharedPreferences

Wear OS App (Watch)
   ├─ Botão SOS
   ├─ Tela "Enviando alerta..."
   ├─ Modo Dark exclusivo
   └─ Recebe contatos do celular (via Data Layer)

Comunicação Celular ↔ Relógio
   ├─ MessageClient / NodeClient
   ├─ MethodChannel (Flutter ↔ Android)
   └─ JSON com contatos via Data Layer
```

---

## ✨ Funcionalidades

### 📱 Aplicativo Android
- Monitoramento real de queda  
- Detecta "quase queda"  
- Envio automático via SMS / WhatsApp  
- Localização aproximada no alerta  
- Histórico completo  
- Simulação de queda  
- Visualização da localização atual  
- UI moderna e responsiva  

---

### ⌚ Aplicativo Wear OS
- Botão SOS  
- Tela com animação "Enviando alerta…"  
- Modo Dark exclusivo  
- Recebe contatos do celular*  
- Sincronização automática via Data Layer*  

\* Em fase final de integração  

---

## 🔌 Tecnologias Utilizadas

| Componente | Tecnologia |
|-----------|------------|
| App principal | Flutter 3.22+ |
| Comunicação Wear OS | Data Layer API (Kotlin) |
| Sensores | sensors_plus |
| Localização | geolocator + geocoding |
| Persistência | SharedPreferences |
| Integração nativa | MethodChannel |
| Mapas | flutter_map + latlong2 |

---

## 🛠 Como Executar

### 1️⃣ Executar app do celular  
```bash
flutter run -d emulator-5554
```

### 2️⃣ Executar app do relógio  
```bash
flutter run -d emulator-5556
```

> 💡 **Importante**:  
> O emulador do celular precisa ter Google Play Store.  
> O app “Google Pixel Watch” deve ser instalado para parear ambos os dispositivos.

---

## 🔄 Pareamento Wear OS ↔ Android

1. Abra **Android Studio** → Device Manager  
2. Clique no relógio → `⋮`  
3. Selecione **Pair with Mobile Device**  
4. Instale **Google Pixel Watch** no emulador do celular  
5. Conclua o pareamento  
6. Rode os apps novamente

O relógio então passa a sincronizar automaticamente os contatos.

---

## 📡 Status Atual do Desenvolvimento

- ✔ Código Flutter funcional  
- ✔ WearContactsBridge implementado  
- ✔ Serviço PhoneWearContactsService funcionando  
- ✔ MessageClient configurado  
- ❗ Falta concluir PAREAMENTO real do Wear OS  
- ❗ Sincronização ainda não ocorre (por falta do pareamento)  
- ⏳ Próxima etapa: integração com ContextNet + Mobile-Hub  

---

## 🎯 Roadmap

- [ ] Finalizar pareamento Wear OS  
- [ ] Validar sincronização automática dos contatos  
- [ ] Testar envio de alerta direto pelo relógio  
- [ ] Conectar sensores a backend inteligente (ContextNet)  
- [ ] Dashboard em nuvem  

---

## 📸 Screenshots
*(Adicione quando quiser)*

```md
![screenshot1](images/screen1.png)
```

---

## 📄 Licença  
Projeto acadêmico — livre para estudo e evolução.

---

<div align="center">
Feito para o TCC — DropWarnify  
</div>

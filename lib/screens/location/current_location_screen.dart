import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:dropwarnify/models/watch_location.dart';
import 'package:dropwarnify/services/wear_contacts_bridge.dart';
import 'package:dropwarnify/widgets/location/location_content.dart';

class CurrentLocationScreen extends StatefulWidget {
  const CurrentLocationScreen({super.key});

  @override
  State<CurrentLocationScreen> createState() => _CurrentLocationScreenState();
}

class _CurrentLocationScreenState extends State<CurrentLocationScreen> {
  bool _loading = false;
  String? _error;
  Position? _position;

  /// Última localização recebida do relógio (se houver).
  WatchLocation? _watchLocation;

  StreamSubscription<WatchLocation>? _watchLocSub;

  @override
  void initState() {
    super.initState();

    // Fallback: localização do próprio celular (Geolocator).
    _obterLocalizacao();

    // 🔹 Assina as atualizações de localização do relógio (WATCH → PHONE).
    _watchLocSub = WearContactsBridge.instance.watchLocationStream.listen((
      loc,
    ) {
      setState(() {
        _watchLocation = loc;
        // Converte para Position para reaproveitar o LocationContent.
        _position = _positionFromWatch(loc);
        _loading = false;
        _error = null;
      });
    });
  }

  @override
  void dispose() {
    _watchLocSub?.cancel();
    super.dispose();
  }

  /// Converte a [WatchLocation] (vinda do relógio) em um [Position] do Geolocator,
  /// apenas para reaproveitar o widget [LocationContent] já existente.
  Position _positionFromWatch(WatchLocation loc) {
    return Position(
      latitude: loc.latitude,
      longitude: loc.longitude,
      accuracy: loc.accuracy, // vindo do relógio
      altitude: 0.0, // relógio normalmente não manda altitude
      altitudeAccuracy: 0.0, // obrigatório no Geolocator novo
      heading: 0.0, // relógio não envia heading
      headingAccuracy: 0.0, // obrigatório
      speed: 0.0, // relógio não manda velocidade
      speedAccuracy: 0.0, // obrigatório
      timestamp: loc.timestamp, // OK
      isMocked: false, // relógio não envia info de mock
    );
  }

  Future<void> _obterLocalizacao() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Se já temos localização do relógio, nem precisa forçar GPS do celular.
      if (_watchLocation != null && _position != null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      // 1) GPS / serviço de localização ligado?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error =
              'Serviço de localização desativado. Ative o GPS / localização do dispositivo.';
          _loading = false;
        });
        return;
      }

      // 2) Permissões
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _error =
              'Permissão de localização negada. Conceda acesso para usar este recurso.';
          _loading = false;
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _error =
              'Permissão negada permanentemente.\nHabilite o acesso à localização nas configurações do sistema.';
          _loading = false;
        });
        return;
      }

      // 3) Posição atual – pedindo MÁXIMA precisão possível (lado do CELULAR).
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        // Só atualiza se ainda não temos localização do relógio.
        _position ??= pos;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erro ao obter localização: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeBlue = Colors.blue.shade700;
    final size = MediaQuery.of(context).size;

    // Wearable / tela muito pequena
    final bool isSmallScreen = size.shortestSide < 300;

    final bool hasWatchLocation = _watchLocation != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        flexibleSpace: Container(decoration: BoxDecoration(color: themeBlue)),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          hasWatchLocation ? 'Localização (relógio)' : 'Localização atual',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fundo suave
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Conteúdo principal, empurrado pra baixo do AppBar
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              16,
              16,
            ),
            child: Column(
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _loading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Obtendo localização...'),
                              ],
                            ),
                          )
                        : _error != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _obterLocalizacao,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Tentar novamente'),
                              ),
                            ],
                          )
                        : _position == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Nenhuma localização obtida.'),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _obterLocalizacao,
                                icon: const Icon(Icons.my_location),
                                label: const Text('Obter agora'),
                              ),
                            ],
                          )
                        : LocationContent(
                            position: _position!,
                            isSmallScreen: isSmallScreen,
                            themeBlue: themeBlue,
                            onRefresh: _obterLocalizacao,
                          ),
                  ),
                ),
                if (!isSmallScreen) const SizedBox(height: 16),
                if (!isSmallScreen)
                  Text(
                    hasWatchLocation
                        ? 'Exibindo a localização enviada pelo relógio (Wear OS).\nSe o relógio perder conexão, o app pode usar a localização deste dispositivo como fallback.'
                        : kIsWeb
                        ? 'A precisão pode ser reduzida no navegador.\nPara melhor resultado, teste em um dispositivo Android com GPS ativo.'
                        : 'Protótipo de visualização da localização atual\nusando OpenStreetMap (flutter_map).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

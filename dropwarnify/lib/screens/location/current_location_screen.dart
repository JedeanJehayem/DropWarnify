import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class CurrentLocationScreen extends StatefulWidget {
  const CurrentLocationScreen({super.key});

  @override
  State<CurrentLocationScreen> createState() => _CurrentLocationScreenState();
}

class _CurrentLocationScreenState extends State<CurrentLocationScreen> {
  bool _loading = false;
  String? _error;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _obterLocalizacao();
  }

  Future<void> _obterLocalizacao() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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

      // 3) Posição atual – pedindo MÁXIMA precisão possível
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        _position = pos;
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        flexibleSpace: Container(decoration: BoxDecoration(color: themeBlue)),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Localização atual',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fundo suave (pode deixar só cor também)
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
                        : _buildLocationContent(
                            isSmallScreen: isSmallScreen,
                            themeBlue: themeBlue,
                          ),
                  ),
                ),
                if (!isSmallScreen) const SizedBox(height: 16),
                if (!isSmallScreen)
                  Text(
                    kIsWeb
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

  // Gera um rótulo e cor de "qualidade" da precisão
  (String label, Color color) _precisionInfo(double accuracyMeters) {
    if (accuracyMeters <= 30) {
      return (
        'Alta precisão (~${accuracyMeters.toStringAsFixed(0)} m)',
        Colors.green.shade700,
      );
    } else if (accuracyMeters <= 150) {
      return (
        'Precisão moderada (~${accuracyMeters.toStringAsFixed(0)} m)',
        Colors.orange.shade700,
      );
    } else {
      return (
        'Precisão baixa (~${accuracyMeters.toStringAsFixed(0)} m)',
        Colors.red.shade700,
      );
    }
  }

  // Conteúdo quando já temos posição
  Widget _buildLocationContent({
    required bool isSmallScreen,
    required Color themeBlue,
  }) {
    final lat = _position!.latitude;
    final lng = _position!.longitude;
    final acc = _position!.accuracy;

    final mapHeight = isSmallScreen ? 160.0 : 240.0;
    final zoom = 18.0; // zoom bem próximo (rua/casa)

    final (precisionLabel, precisionColor) = _precisionInfo(acc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.my_location, color: themeBlue),
            const SizedBox(width: 8),
            Text(
              'Coordenadas atuais',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.bold,
                color: themeBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Text(
          'Latitude:  $lat',
          style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
        ),
        Text(
          'Longitude: $lng',
          style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
        ),

        const SizedBox(height: 8),

        // Badge de precisão
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: precisionColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gps_fixed, size: 16, color: precisionColor),
              const SizedBox(width: 6),
              Text(
                precisionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: precisionColor,
                ),
              ),
            ],
          ),
        ),

        if (!isSmallScreen) ...[
          const SizedBox(height: 8),
          Text(
            'Atualizado em: ${_position!.timestamp}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],

        const SizedBox(height: 8),

        if (kIsWeb && acc > 200)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Observação: no navegador a localização geralmente é aproximada (por IP / rede).\n'
              'Para melhor precisão, teste no app Android com GPS ativado em modo alta precisão.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),

        const SizedBox(height: 16),

        // MAPA (flutter_map 7.x)
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: mapHeight,
            width: double.infinity,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(lat, lng),
                initialZoom: zoom,
                interactionOptions: isSmallScreen
                    ? const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                      )
                    : const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.dropwarnify',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _obterLocalizacao,
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar localização'),
          ),
        ),
      ],
    );
  }
}

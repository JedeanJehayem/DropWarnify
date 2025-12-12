import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationContent extends StatelessWidget {
  final Position position;
  final bool isSmallScreen;
  final Color themeBlue;
  final VoidCallback onRefresh;

  const LocationContent({
    super.key,
    required this.position,
    required this.isSmallScreen,
    required this.themeBlue,
    required this.onRefresh,
  });

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatTimestamp(DateTime? ts) {
    if (ts == null) return 'Data/hora não informada';
    final local = ts.toLocal();
    final dia = _twoDigits(local.day);
    final mes = _twoDigits(local.month);
    final ano = local.year;
    final hora = _twoDigits(local.hour);
    final min = _twoDigits(local.minute);
    return '$dia/$mes/$ano às $hora:$min';
  }

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

  @override
  Widget build(BuildContext context) {
    final lat = position.latitude;
    final lng = position.longitude;
    final acc = position.accuracy;

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
            'Atualizado em: ${_formatTimestamp(position.timestamp)}',
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
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar localização'),
          ),
        ),
      ],
    );
  }
}

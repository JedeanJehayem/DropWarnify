class WatchLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String provider;
  final DateTime timestamp;

  WatchLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.provider,
    required this.timestamp,
  });

  factory WatchLocation.fromJson(Map<String, dynamic> json) {
    return WatchLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['locationAccuracy'] as num).toDouble(),
      provider: json['locationProvider'] as String? ?? 'unknown',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

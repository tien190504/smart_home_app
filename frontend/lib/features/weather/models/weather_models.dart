class CurrentLocationSnapshot {
  const CurrentLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.addressLabel,
    required this.localityLabel,
  });

  final double latitude;
  final double longitude;
  final String addressLabel;
  final String localityLabel;
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.latitude,
    required this.longitude,
    required this.temperatureC,
    required this.condition,
    required this.iconKey,
    this.apparentTemperatureC,
    this.humidityPercent,
    this.observedAt,
  });

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    return WeatherSnapshot(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      temperatureC: (json['temperatureC'] as num?)?.toDouble() ?? 0,
      condition: json['condition'] as String? ?? 'Weather unavailable',
      iconKey: json['iconKey'] as String? ?? 'unknown',
      apparentTemperatureC: (json['apparentTemperatureC'] as num?)?.toDouble(),
      humidityPercent: (json['humidityPercent'] as num?)?.toInt(),
      observedAt: DateTime.tryParse(json['observedAt'] as String? ?? ''),
    );
  }

  final double latitude;
  final double longitude;
  final double temperatureC;
  final String condition;
  final String iconKey;
  final double? apparentTemperatureC;
  final int? humidityPercent;
  final DateTime? observedAt;
}

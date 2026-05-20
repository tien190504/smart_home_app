import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/api_client.dart';
import '../../devices/data/device_api.dart';
import '../models/weather_models.dart';

final weatherApiProvider = Provider<WeatherApi>((ref) {
  return WeatherApi(ref.watch(apiClientProvider));
});

class WeatherApi {
  WeatherApi(this._client);

  final ApiClient _client;

  Future<WeatherSnapshot> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final json = await _client.getMap(
      '/api/weather/current?lat=$latitude&lon=$longitude',
    );
    return WeatherSnapshot.fromJson(json);
  }
}

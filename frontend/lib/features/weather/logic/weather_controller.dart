import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/location_service.dart';
import '../data/weather_api.dart';
import '../models/weather_models.dart';

final weatherControllerProvider =
    StateNotifierProvider<WeatherController, WeatherState>((ref) {
      final controller = WeatherController(
        api: ref.watch(weatherApiProvider),
        locationService: ref.watch(currentLocationServiceProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class WeatherState {
  const WeatherState({
    required this.loading,
    required this.location,
    required this.weather,
    this.errorMessage,
  });

  const WeatherState.initial()
    : this(loading: false, location: null, weather: null);

  final bool loading;
  final CurrentLocationSnapshot? location;
  final WeatherSnapshot? weather;
  final String? errorMessage;

  WeatherState copyWith({
    bool? loading,
    CurrentLocationSnapshot? location,
    WeatherSnapshot? weather,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WeatherState(
      loading: loading ?? this.loading,
      location: location ?? this.location,
      weather: weather ?? this.weather,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class WeatherController extends StateNotifier<WeatherState> {
  WeatherController({
    required WeatherApi api,
    required CurrentLocationService locationService,
  }) : _api = api,
       _locationService = locationService,
       super(const WeatherState.initial());

  final WeatherApi _api;
  final CurrentLocationService _locationService;
  bool _initialized = false;
  bool _loading = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final location = await _locationService.tryResolveCurrentLocation(
        requestPermission: true,
      );
      if (location == null) {
        state = state.copyWith(
          loading: false,
          errorMessage:
              'Enable location access to show your local address and weather.',
        );
        return;
      }

      state = state.copyWith(
        loading: true,
        location: location,
        clearError: true,
      );

      final weather = await _api.getCurrentWeather(
        latitude: location.latitude,
        longitude: location.longitude,
      );

      state = state.copyWith(
        loading: false,
        location: location,
        weather: weather,
        clearError: true,
      );
      _initialized = true;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load the local address and weather right now.',
      );
    } finally {
      _loading = false;
    }
  }
}

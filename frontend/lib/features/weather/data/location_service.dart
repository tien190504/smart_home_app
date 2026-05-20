import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/weather_models.dart';

final currentLocationServiceProvider = Provider<CurrentLocationService>((ref) {
  return const CurrentLocationService();
});

class CurrentLocationService {
  const CurrentLocationService();

  static const Duration _positionTimeout = Duration(seconds: 10);
  static const Duration _placemarkTimeout = Duration(seconds: 6);

  Future<CurrentLocationSnapshot?> tryResolveCurrentLocation({
    bool requestPermission = false,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await _resolvePosition();
    if (position == null) {
      return null;
    }

    final placemark = await _resolvePlacemark(position);
    final localityParts = <String>[
      placemark?.locality ?? '',
      placemark?.administrativeArea ?? '',
      placemark?.country ?? '',
    ].where((part) => part.trim().isNotEmpty).toList();

    final addressParts = <String>[
      placemark?.subLocality ?? '',
      placemark?.locality ?? '',
      placemark?.administrativeArea ?? '',
      placemark?.country ?? '',
    ].where((part) => part.trim().isNotEmpty).toList();

    final localityLabel = localityParts.isEmpty
        ? '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}'
        : _uniqueJoined(localityParts);
    final addressLabel = addressParts.isEmpty
        ? localityLabel
        : _uniqueJoined(addressParts);

    return CurrentLocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      addressLabel: addressLabel,
      localityLabel: localityLabel,
    );
  }

  Future<Position?> _resolvePosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: _positionTimeout,
        ),
      );
    } on TimeoutException {
      return Geolocator.getLastKnownPosition();
    } catch (_) {
      final lastKnownPosition = await Geolocator.getLastKnownPosition();
      if (lastKnownPosition != null) {
        return lastKnownPosition;
      }
      rethrow;
    }
  }

  Future<Placemark?> _resolvePlacemark(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(_placemarkTimeout);
      return placemarks.isEmpty ? null : placemarks.first;
    } catch (_) {
      return null;
    }
  }

  String _uniqueJoined(List<String> parts) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (seen.add(lower)) {
        ordered.add(trimmed);
      }
    }
    return ordered.join(', ');
  }
}

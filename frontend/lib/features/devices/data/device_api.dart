import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/connection_settings_controller.dart';
import '../../../core/data/api_client.dart';
import '../models/device_models.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref, ref.watch(appConfigProvider));
});

final deviceApiProvider = Provider<DeviceApi>((ref) {
  return DeviceApi(ref.watch(apiClientProvider));
});

class DeviceApi {
  DeviceApi(this._client);

  final ApiClient _client;

  Future<List<DeviceStateSnapshot>> fetchDeviceSnapshots() async {
    final rawDevices = await _client.getList('/api/devices');
    final devices = rawDevices
        .map(
          (item) => DeviceStateSnapshot.fromDeviceJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    final enriched = await Future.wait(devices.map(_mergeLatestTelemetry));
    return enriched;
  }

  Future<DeviceStateSnapshot> provisionDevice({
    required String deviceCode,
    required String pairingCode,
  }) async {
    final json = await _client.postMap(
      '/api/devices/provision',
      data: {'deviceCode': deviceCode, 'pairingCode': pairingCode},
    );
    return DeviceStateSnapshot.fromDeviceJson(json);
  }

  Future<DeviceStateSnapshot> createDevice({
    required String name,
    required String deviceCode,
    required String pairingCode,
    String description = '',
    String location = '',
  }) async {
    final json = await _client.postMap(
      '/api/devices',
      data: {
        'name': name,
        'deviceCode': deviceCode,
        'pairingCode': pairingCode,
        'description': description,
        'location': location,
      },
    );
    return DeviceStateSnapshot.fromDeviceJson(json);
  }

  Future<DeviceStateSnapshot> provisionOrCreateDevice({
    required String deviceCode,
    required String pairingCode,
    required String fallbackName,
  }) async {
    try {
      return await provisionDevice(
        deviceCode: deviceCode,
        pairingCode: pairingCode,
      );
    } on DioException catch (error) {
      if (!_isMissingDeviceError(error)) {
        rethrow;
      }

      return createDevice(
        name: fallbackName.trim().isEmpty
            ? 'Smart Device'
            : fallbackName.trim(),
        deviceCode: deviceCode,
        pairingCode: pairingCode,
      );
    }
  }

  Future<DeviceStateSnapshot> _mergeLatestTelemetry(
    DeviceStateSnapshot device,
  ) async {
    try {
      final latest = await _client.getMap(
        '/api/telemetry/devices/${device.id}/latest',
      );

      final rawPayload = latest['rawPayload'] as String? ?? '';
      final statePayload = latest['statePayload'] as String? ?? rawPayload;
      final event = MqttTelemetryEvent(
        deviceCode: device.deviceCode,
        rawPayload: rawPayload,
        state: _parseLatestState(statePayload),
        receivedAt:
            DateTime.tryParse(latest['recordedAt'] as String? ?? '') ??
            DateTime.now(),
        temperature: (latest['temperature'] as num?)?.toDouble(),
        humidity: (latest['humidity'] as num?)?.toDouble(),
        batteryLevel: (latest['batteryLevel'] as num?)?.toDouble(),
      );
      return device.mergeTelemetry(event);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return device;
      }
      rethrow;
    }
  }

  Map<String, dynamic> _parseLatestState(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Fall back to storing the raw payload when telemetry state is not JSON.
    }

    final boolValue = switch (trimmed.toLowerCase()) {
      'on' || 'true' || '1' => true,
      'off' || 'false' || '0' => false,
      _ => null,
    };
    if (boolValue != null) {
      return <String, dynamic>{'power': boolValue};
    }
    return <String, dynamic>{'raw': trimmed};
  }

  bool _isMissingDeviceError(DioException error) {
    if (error.response?.statusCode == 404) {
      return true;
    }

    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String &&
          message.toLowerCase().contains('device not found')) {
        return true;
      }
    }

    if (data is String && data.toLowerCase().contains('device not found')) {
      return true;
    }

    return false;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/connection_settings_controller.dart';
import '../models/device_models.dart';
import 'device_mqtt_client_io.dart'
    if (dart.library.js_interop) 'device_mqtt_client_web.dart';

final mqttMessageCodecProvider = Provider<MqttMessageCodec>((ref) {
  return const MqttMessageCodec();
});

final deviceMqttServiceProvider = Provider<DeviceMqttService>((ref) {
  final service = DeviceMqttService(
    config: ref.watch(appConfigProvider),
    codec: ref.read(mqttMessageCodecProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class DeviceMqttService {
  static const Duration _connectTimeout = Duration(seconds: 6);

  DeviceMqttService({
    required AppConfig config,
    required MqttMessageCodec codec,
  }) : _config = config,
       _codec = codec;

  final AppConfig _config;
  final MqttMessageCodec _codec;

  final _telemetryController = StreamController<MqttTelemetryEvent>.broadcast();
  final _connectionController =
      StreamController<BrokerConnectionStatus>.broadcast();

  MqttClient? _client;
  StreamSubscription? _updatesSubscription;
  bool _connecting = false;
  Set<String> _deviceCodes = <String>{};

  Stream<MqttTelemetryEvent> get telemetryStream => _telemetryController.stream;

  Stream<BrokerConnectionStatus> get connectionStream =>
      _connectionController.stream;

  BrokerConnectionStatus get connectionStatus {
    final state = _client?.connectionStatus?.state;
    if (state == MqttConnectionState.connected) {
      return BrokerConnectionStatus.connected;
    }
    if (_connecting) {
      return BrokerConnectionStatus.connecting;
    }
    return BrokerConnectionStatus.disconnected;
  }

  Future<void> connect() async {
    if (_connecting || connectionStatus == BrokerConnectionStatus.connected) {
      return;
    }

    _connecting = true;
    _connectionController.add(BrokerConnectionStatus.connecting);

    final clientId =
        'smartify_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final client = _buildClient(clientId);

    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.connectTimeoutPeriod = 5000;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.setProtocolV311();
    client.onConnected = _handleConnected;
    client.onDisconnected = _handleDisconnected;
    client.onAutoReconnect = () {
      _connectionController.add(BrokerConnectionStatus.connecting);
    };
    client.onAutoReconnected = _handleConnected;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    try {
      await client
          .connect(_config.mqttUsername, _config.mqttPassword)
          .timeout(_connectTimeout);
    } on TimeoutException catch (_) {
      client.disconnect();
      _client = null;
      _connecting = false;
      _connectionController.add(BrokerConnectionStatus.disconnected);
      throw StateError(
        'MQTT connection timed out after ${_connectTimeout.inSeconds} seconds.',
      );
    } catch (_) {
      client.disconnect();
      _client = null;
      _connecting = false;
      _connectionController.add(BrokerConnectionStatus.disconnected);
      rethrow;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      _client = null;
      _connecting = false;
      _connectionController.add(BrokerConnectionStatus.disconnected);
      throw StateError('MQTT connection failed: ${client.connectionStatus}');
    }

    await _updatesSubscription?.cancel();
    _updatesSubscription = client.updates?.listen(
      _handleMessages,
      onDone: _handleDisconnected,
      onError: (_) => _handleDisconnected(),
    );
    _client = client;
    _connecting = false;
    _connectionController.add(BrokerConnectionStatus.connected);
    _syncSubscriptions();
  }

  Future<void> syncDeviceCodes(Iterable<String> deviceCodes) async {
    _deviceCodes = deviceCodes.where((code) => code.trim().isNotEmpty).toSet();
    if (_deviceCodes.isEmpty) {
      return;
    }
    if (connectionStatus != BrokerConnectionStatus.connected) {
      await connect();
      return;
    }
    _syncSubscriptions();
  }

  Future<void> publishCommand({
    required String deviceCode,
    required DeviceControlPayload payload,
  }) async {
    if (payload.isEmpty) {
      return;
    }
    if (connectionStatus != BrokerConnectionStatus.connected) {
      await connect();
    }

    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('MQTT is not connected.');
    }

    final topic = _config.commandTopicFor(deviceCode);
    final builder = MqttClientPayloadBuilder()
      ..addString(_codec.encodeCommand(payload));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  Future<void> dispose() async {
    await _updatesSubscription?.cancel();
    _client?.disconnect();
    await _telemetryController.close();
    await _connectionController.close();
  }

  MqttClient _buildClient(String clientId) {
    return buildPlatformMqttClient(_config, clientId);
  }

  void _handleConnected() {
    _connecting = false;
    _connectionController.add(BrokerConnectionStatus.connected);
    _syncSubscriptions();
  }

  void _handleDisconnected() {
    _connecting = false;
    _connectionController.add(BrokerConnectionStatus.disconnected);
  }

  void _syncSubscriptions() {
    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    for (final deviceCode in _deviceCodes) {
      client.subscribe(
        _config.telemetryTopicFor(deviceCode),
        MqttQos.atLeastOnce,
      );
      client.subscribe(
        _config.statusTopicFor(deviceCode),
        MqttQos.atLeastOnce,
      );
    }
  }

  void _handleMessages(List<MqttReceivedMessage<MqttMessage?>> messages) {
    for (final message in messages) {
      final payloadMessage = message.payload as MqttPublishMessage;
      final rawPayload = MqttPublishPayload.bytesToStringAsString(
        payloadMessage.payload.message,
      );
      final event = _codec.decodeTelemetry(
        topic: message.topic,
        rawPayload: rawPayload,
      );
      if (event != null) {
        _telemetryController.add(event);
      }
    }
  }
}

class MqttMessageCodec {
  const MqttMessageCodec();

  String encodeCommand(DeviceControlPayload payload) {
    return jsonEncode({'commandType': 'set_state', 'payload': payload.toMap()});
  }

  MqttTelemetryEvent? decodeTelemetry({
    required String topic,
    required String rawPayload,
  }) {
    final segments = topic.split('/');
    if (segments.length < 4) {
      return null;
    }

    final deviceCode = segments[2];
    final payloadMap = _toPayloadMap(rawPayload);
    final state = _toStateMap(payloadMap['state'] ?? payloadMap);
    final online = _parseBool(
      payloadMap['online'] ?? state['online'] ?? state['status'],
    );

    return MqttTelemetryEvent(
      deviceCode: deviceCode,
      rawPayload: rawPayload,
      state: state,
      receivedAt: DateTime.now(),
      online: online,
      temperature: _parseDouble(
        payloadMap['temperature'] ?? payloadMap['temp'],
      ),
      humidity: _parseDouble(payloadMap['humidity']),
      batteryLevel: _parseDouble(
        payloadMap['batteryLevel'] ??
            payloadMap['battery'] ??
            payloadMap['battery_level'],
      ),
    );
  }

  Map<String, dynamic> _toPayloadMap(String rawPayload) {
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is bool) {
        return {'power': decoded};
      }
      if (decoded is String) {
        final boolValue = _parseBool(decoded);
        return boolValue == null ? {'raw': decoded} : {'power': boolValue};
      }
    } catch (_) {
      final boolValue = _parseBool(rawPayload);
      if (boolValue != null) {
        return {'power': boolValue};
      }
    }
    return <String, dynamic>{'raw': rawPayload};
  }

  Map<String, dynamic> _toStateMap(Object? rawState) {
    if (rawState is Map<String, dynamic>) {
      return rawState;
    }
    if (rawState is Map) {
      return Map<String, dynamic>.from(rawState);
    }
    final boolValue = _parseBool(rawState);
    if (boolValue != null) {
      return {'power': boolValue};
    }
    if (rawState is String && rawState.trim().isNotEmpty) {
      return {'raw': rawState.trim()};
    }
    return <String, dynamic>{};
  }

  bool? _parseBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'on':
        case 'true':
        case '1':
        case 'online':
        case 'active':
          return true;
        case 'off':
        case 'false':
        case '0':
        case 'offline':
        case 'inactive':
          return false;
      }
    }
    return null;
  }

  double? _parseDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

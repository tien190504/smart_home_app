import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.restBaseUrl,
    required this.mqttTcpHost,
    required this.mqttTcpPort,
    required this.mqttWsUrl,
    required this.mqttUsername,
    required this.mqttPassword,
    required this.telemetryTopicTemplate,
    required this.statusTopicTemplate,
    required this.commandTopicTemplate,
    required this.commandAckTimeout,
    required this.heartbeatTimeout,
    required this.defaultBleServiceUuid,
    required this.defaultBleWriteCharacteristicUuid,
    required this.defaultBleNotifyCharacteristicUuid,
  });

  factory AppConfig.fromEnvironment() {
    final restBaseUrl = _envString(
      'REST_BASE_URL',
      _PlatformDefaults.restBaseUrl,
    );
    final defaultMqttHost = _mqttHostFromRestBaseUrl(
      restBaseUrl,
      _PlatformDefaults.mqttHost,
    );

    return AppConfig(
      restBaseUrl: restBaseUrl,
      mqttTcpHost: _envString('MQTT_TCP_HOST', defaultMqttHost),
      mqttTcpPort: const int.fromEnvironment(
        'MQTT_TCP_PORT',
        defaultValue: 1883,
      ),
      mqttWsUrl: _envString('MQTT_WS_URL', _PlatformDefaults.mqttWsUrl),
      mqttUsername: _stringOrNull(
        const String.fromEnvironment('MQTT_USERNAME', defaultValue: 'flutter_app'),
      ),
      mqttPassword: _stringOrNull(
        const String.fromEnvironment('MQTT_PASSWORD', defaultValue: 'MatKhauFlutterApp789!'),
      ),
      telemetryTopicTemplate: const String.fromEnvironment(
        'MQTT_TELEMETRY_TOPIC_TEMPLATE',
        defaultValue: 'iot/devices/%s/telemetry',
      ),
      statusTopicTemplate: const String.fromEnvironment(
        'MQTT_STATUS_TOPIC_TEMPLATE',
        defaultValue: 'iot/devices/%s/status',
      ),
      commandTopicTemplate: const String.fromEnvironment(
        'MQTT_COMMAND_TOPIC_TEMPLATE',
        defaultValue: 'iot/devices/%s/commands',
      ),
      commandAckTimeout: Duration(
        seconds: const int.fromEnvironment(
          'MQTT_COMMAND_ACK_TIMEOUT_SECONDS',
          defaultValue: 6,
        ),
      ),
      heartbeatTimeout: Duration(
        seconds: const int.fromEnvironment(
          'MQTT_HEARTBEAT_TIMEOUT_SECONDS',
          defaultValue: 30,
        ),
      ),
      defaultBleServiceUuid: const String.fromEnvironment(
        'BLE_SERVICE_UUID',
        defaultValue: '0000FFF0-0000-1000-8000-00805F9B34FB',
      ),
      defaultBleWriteCharacteristicUuid: const String.fromEnvironment(
        'BLE_WRITE_CHARACTERISTIC_UUID',
        defaultValue: '0000FFF1-0000-1000-8000-00805F9B34FB',
      ),
      defaultBleNotifyCharacteristicUuid: const String.fromEnvironment(
        'BLE_NOTIFY_CHARACTERISTIC_UUID',
        defaultValue: '0000FFF2-0000-1000-8000-00805F9B34FB',
      ),
    );
  }

  final String restBaseUrl;
  final String mqttTcpHost;
  final int mqttTcpPort;
  final String mqttWsUrl;
  final String? mqttUsername;
  final String? mqttPassword;
  final String telemetryTopicTemplate;
  final String statusTopicTemplate;
  final String commandTopicTemplate;
  final Duration commandAckTimeout;
  final Duration heartbeatTimeout;
  final String defaultBleServiceUuid;
  final String defaultBleWriteCharacteristicUuid;
  final String defaultBleNotifyCharacteristicUuid;

  AppConfig copyWith({
    String? restBaseUrl,
    String? mqttTcpHost,
    int? mqttTcpPort,
    String? mqttWsUrl,
    String? mqttUsername,
    String? mqttPassword,
    String? telemetryTopicTemplate,
    String? statusTopicTemplate,
    String? commandTopicTemplate,
    Duration? commandAckTimeout,
    Duration? heartbeatTimeout,
    String? defaultBleServiceUuid,
    String? defaultBleWriteCharacteristicUuid,
    String? defaultBleNotifyCharacteristicUuid,
  }) {
    return AppConfig(
      restBaseUrl: restBaseUrl ?? this.restBaseUrl,
      mqttTcpHost: mqttTcpHost ?? this.mqttTcpHost,
      mqttTcpPort: mqttTcpPort ?? this.mqttTcpPort,
      mqttWsUrl: mqttWsUrl ?? this.mqttWsUrl,
      mqttUsername: mqttUsername ?? this.mqttUsername,
      mqttPassword: mqttPassword ?? this.mqttPassword,
      telemetryTopicTemplate:
          telemetryTopicTemplate ?? this.telemetryTopicTemplate,
      statusTopicTemplate: statusTopicTemplate ?? this.statusTopicTemplate,
      commandTopicTemplate: commandTopicTemplate ?? this.commandTopicTemplate,
      commandAckTimeout: commandAckTimeout ?? this.commandAckTimeout,
      heartbeatTimeout: heartbeatTimeout ?? this.heartbeatTimeout,
      defaultBleServiceUuid:
          defaultBleServiceUuid ?? this.defaultBleServiceUuid,
      defaultBleWriteCharacteristicUuid:
          defaultBleWriteCharacteristicUuid ??
          this.defaultBleWriteCharacteristicUuid,
      defaultBleNotifyCharacteristicUuid:
          defaultBleNotifyCharacteristicUuid ??
          this.defaultBleNotifyCharacteristicUuid,
    );
  }

  String telemetryTopicFor(String deviceCode) =>
      telemetryTopicTemplate.replaceFirst('%s', deviceCode);

  String statusTopicFor(String deviceCode) =>
      statusTopicTemplate.replaceFirst('%s', deviceCode);

  String commandTopicFor(String deviceCode) =>
      commandTopicTemplate.replaceFirst('%s', deviceCode);

  static String _envString(String key, String fallback) {
    final value = String.fromEnvironment(key, defaultValue: '');
    return value.trim().isEmpty ? fallback : value.trim();
  }

  static String? _stringOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _mqttHostFromRestBaseUrl(String restBaseUrl, String fallback) {
    final uri = Uri.tryParse(restBaseUrl.trim());
    final host = uri?.host.trim() ?? '';
    return host.isEmpty ? fallback : host;
  }
}

abstract final class _PlatformDefaults {
  static String get restBaseUrl {
    if (kIsWeb) {
      if (_shouldUseSameOriginProxy) {
        return Uri.base.origin;
      }
      return 'http://47.128.65.214';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://47.128.65.214';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://47.128.65.214';
    }
  }

  static String get mqttHost {
    if (kIsWeb) {
      return '47.128.65.214';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return '47.128.65.214';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return '47.128.65.214';
    }
  }

  static String get mqttWsUrl {
    if (!kIsWeb) {
      return 'ws://47.128.65.214:9001';
    }

    if (!_shouldUseSameOriginProxy) {
      return 'ws://47.128.65.214:9001';
    }

    final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    final authority = Uri.base.hasPort
        ? '${Uri.base.host}:${Uri.base.port}'
        : Uri.base.host;
    return '$scheme://$authority/mqtt';
  }

  static bool get _shouldUseSameOriginProxy {
    final host = Uri.base.host.toLowerCase();
    final isLocalHost = host == 'localhost' || host == '127.0.0.1';
    final port = Uri.base.hasPort
        ? Uri.base.port
        : (Uri.base.scheme == 'https' ? 443 : 80);

    if (!isLocalHost) {
      return true;
    }

    return port == 3000 || port == 80 || port == 443;
  }
}

import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../../../core/config/app_config.dart';

MqttClient buildPlatformMqttClient(AppConfig config, String clientId) {
  final client = MqttBrowserClient(config.mqttWsUrl, clientId);
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  final uri = Uri.parse(config.mqttWsUrl);
  if (uri.hasPort) {
    client.port = uri.port;
  }
  return client;
}

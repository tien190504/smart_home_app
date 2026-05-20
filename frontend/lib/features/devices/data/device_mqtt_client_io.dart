import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../../core/config/app_config.dart';

MqttClient buildPlatformMqttClient(AppConfig config, String clientId) {
  return MqttServerClient.withPort(
    config.mqttTcpHost,
    clientId,
    config.mqttTcpPort,
  );
}

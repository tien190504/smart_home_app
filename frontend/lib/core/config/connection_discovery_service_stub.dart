import 'app_config.dart';
import 'connection_settings.dart';

class ConnectionDiscoveryService {
  const ConnectionDiscoveryService();

  Future<ConnectionSettings?> discover({
    required AppConfig fallbackConfig,
    ConnectionSettings? preferredSettings,
  }) async {
    return null;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'connection_discovery_service.dart';
import 'connection_settings.dart';
import 'connection_settings_storage.dart';

final initialConnectionSettingsProvider = Provider<ConnectionSettings?>(
  (ref) => null,
);

final connectionSettingsStorageProvider = Provider<ConnectionSettingsStorage>((
  ref,
) {
  throw UnimplementedError(
    'connectionSettingsStorageProvider must be overridden in main().',
  );
});

final connectionSettingsControllerProvider =
    StateNotifierProvider<
      ConnectionSettingsController,
      ConnectionSettingsState
    >((ref) {
      return ConnectionSettingsController(
        baseConfig: AppConfig.fromEnvironment(),
        initialSettings: ref.read(initialConnectionSettingsProvider),
        discoveryService: ref.read(connectionDiscoveryServiceProvider),
        storage: ref.read(connectionSettingsStorageProvider),
      );
    });

final appConfigProvider = Provider<AppConfig>((ref) {
  return ref.watch(connectionSettingsControllerProvider).effectiveConfig;
});

class ConnectionSettingsState {
  const ConnectionSettingsState({
    required this.baseConfig,
    required this.effectiveConfig,
    required this.runtimeSettings,
    required this.requiresSetup,
  });

  final AppConfig baseConfig;
  final AppConfig effectiveConfig;
  final ConnectionSettings? runtimeSettings;
  final bool requiresSetup;

  bool get usesRuntimeSettings => runtimeSettings != null;
}

class ConnectionSettingsController
    extends StateNotifier<ConnectionSettingsState> {
  ConnectionSettingsController({
    required AppConfig baseConfig,
    required ConnectionSettings? initialSettings,
    required ConnectionDiscoveryService discoveryService,
    required ConnectionSettingsStorage storage,
  }) : _baseConfig = baseConfig,
       _discoveryService = discoveryService,
       _storage = storage,
       super(_buildState(baseConfig, initialSettings));

  final AppConfig _baseConfig;
  final ConnectionDiscoveryService _discoveryService;
  final ConnectionSettingsStorage _storage;
  bool _autoDiscoveryInProgress = false;

  Future<void> save(ConnectionSettings settings) async {
    final normalized = ConnectionSettings.fromUserInput(
      restBaseUrl: settings.restBaseUrl,
      mqttTcpHost: settings.mqttTcpHost,
      mqttTcpPort: settings.mqttTcpPort,
    );
    await _storage.save(normalized);
    state = _buildState(_baseConfig, normalized);
  }

  Future<void> clear() async {
    await _storage.clear();
    state = _buildState(_baseConfig, null);
  }

  Future<ConnectionSettings?> autoDiscover({bool force = false}) async {
    if (kIsWeb || _autoDiscoveryInProgress) {
      return state.runtimeSettings;
    }

    _autoDiscoveryInProgress = true;
    try {
      final discovered = await _discoveryService.discover(
        fallbackConfig: state.effectiveConfig,
        preferredSettings: state.runtimeSettings,
      );
      if (discovered == null) {
        return null;
      }

      final normalized = ConnectionSettings.fromUserInput(
        restBaseUrl: discovered.restBaseUrl,
        mqttTcpHost: discovered.mqttTcpHost,
        mqttTcpPort: discovered.mqttTcpPort,
      );

      final current = state.runtimeSettings;
      if (!force && _sameSettings(current, normalized)) {
        return current;
      }

      await _storage.save(normalized);
      state = _buildState(_baseConfig, normalized);
      return normalized;
    } finally {
      _autoDiscoveryInProgress = false;
    }
  }

  bool _sameSettings(ConnectionSettings? left, ConnectionSettings right) {
    if (left == null) {
      return false;
    }

    return left.restBaseUrl == right.restBaseUrl &&
        left.mqttTcpHost == right.mqttTcpHost &&
        left.mqttTcpPort == right.mqttTcpPort;
  }

  static ConnectionSettingsState _buildState(
    AppConfig baseConfig,
    ConnectionSettings? runtimeSettings,
  ) {
    if (kIsWeb) {
      return ConnectionSettingsState(
        baseConfig: baseConfig,
        effectiveConfig: baseConfig,
        runtimeSettings: null,
        requiresSetup: false,
      );
    }

    final normalizedSettings = runtimeSettings == null
        ? null
        : ConnectionSettings.fromUserInput(
            restBaseUrl: runtimeSettings.restBaseUrl,
            mqttTcpHost: runtimeSettings.mqttTcpHost,
            mqttTcpPort: runtimeSettings.mqttTcpPort,
          );

    final effectiveConfig = normalizedSettings == null
        ? baseConfig
        : baseConfig.copyWith(
            restBaseUrl: normalizedSettings.restBaseUrl,
            mqttTcpHost: normalizedSettings.mqttTcpHost,
            mqttTcpPort: normalizedSettings.mqttTcpPort,
          );

    return ConnectionSettingsState(
      baseConfig: baseConfig,
      effectiveConfig: effectiveConfig,
      runtimeSettings: normalizedSettings,
      requiresSetup:
          normalizedSettings == null || !normalizedSettings.isComplete,
    );
  }
}

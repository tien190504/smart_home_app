import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/smartify_app.dart';
import 'package:frontend/core/config/connection_settings.dart';
import 'package:frontend/core/config/connection_settings_controller.dart';
import 'package:frontend/core/config/connection_settings_storage.dart';
import 'package:frontend/features/auth/data/auth_models.dart';
import 'package:frontend/features/auth/data/auth_storage.dart';
import 'package:frontend/features/auth/logic/auth_controller.dart';

void main() {
  testWidgets('shows splash branding on startup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStorageProvider.overrideWithValue(_InMemoryAuthStorage()),
          initialConnectionSettingsProvider.overrideWithValue(
            ConnectionSettings.fromUserInput(
              restBaseUrl: 'http://127.0.0.1:8080',
              mqttTcpHost: '127.0.0.1',
              mqttTcpPort: 1883,
            ),
          ),
          connectionSettingsStorageProvider.overrideWithValue(
            _InMemoryConnectionSettingsStorage(),
          ),
        ],
        child: const SmartifyApp(),
      ),
    );

    expect(find.text('Smartify'), findsOneWidget);
  });
}

class _InMemoryAuthStorage implements AuthStorage {
  AuthSession? _session;
  bool _rememberMe = true;

  @override
  Future<void> clear() async {
    _session = null;
  }

  @override
  Future<bool> loadRememberMe() async => _rememberMe;

  @override
  Future<AuthSession?> loadSession() async => _session;

  @override
  Future<void> saveSession(
    AuthSession session, {
    required bool rememberMe,
  }) async {
    _session = rememberMe ? session : null;
    _rememberMe = rememberMe;
  }
}

class _InMemoryConnectionSettingsStorage implements ConnectionSettingsStorage {
  ConnectionSettings? _settings;

  @override
  ConnectionSettings? load() => _settings;

  @override
  Future<void> save(ConnectionSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> clear() async {
    _settings = null;
  }
}

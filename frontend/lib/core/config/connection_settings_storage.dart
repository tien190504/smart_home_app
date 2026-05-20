import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'connection_settings.dart';

class ConnectionSettingsStorage {
  ConnectionSettingsStorage(this._preferences);

  static const String _settingsKey = 'smartify.connection.settings';

  final SharedPreferences _preferences;

  ConnectionSettings? load() {
    final raw = _preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return ConnectionSettings.fromJson(json);
      }
      if (json is Map) {
        return ConnectionSettings.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (_) {
      // Ignore malformed saved settings and fall back to setup flow.
    }

    return null;
  }

  Future<void> save(ConnectionSettings settings) async {
    await _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> clear() async {
    await _preferences.remove(_settingsKey);
  }
}

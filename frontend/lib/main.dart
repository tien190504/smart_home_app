import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/smartify_app.dart';
import 'core/config/connection_settings_controller.dart';
import 'core/config/connection_settings_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final storage = ConnectionSettingsStorage(preferences);
  final initialSettings = kIsWeb ? null : storage.load();

  runApp(
    ProviderScope(
      overrides: [
        connectionSettingsStorageProvider.overrideWithValue(storage),
        initialConnectionSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const SmartifyApp(),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/connection_settings.dart';
import '../../../core/config/connection_settings_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/logic/auth_controller.dart';

class ConnectionSetupScreen extends ConsumerStatefulWidget {
  const ConnectionSetupScreen({super.key});

  @override
  ConsumerState<ConnectionSetupScreen> createState() =>
      _ConnectionSetupScreenState();
}

class _ConnectionSetupScreenState extends ConsumerState<ConnectionSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _restBaseUrlController = TextEditingController();
  final _mqttHostController = TextEditingController();
  final _mqttPortController = TextEditingController(text: '1883');
  bool _saving = false;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(connectionSettingsControllerProvider);
    final runtimeSettings = state.runtimeSettings;

    if (runtimeSettings != null) {
      _restBaseUrlController.text = runtimeSettings.restBaseUrl;
      _mqttHostController.text = runtimeSettings.mqttTcpHost;
      _mqttPortController.text = runtimeSettings.mqttTcpPort.toString();
    }
  }

  @override
  void dispose() {
    _restBaseUrlController.dispose();
    _mqttHostController.dispose();
    _mqttPortController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (kIsWeb) {
      if (!mounted) {
        return;
      }
      context.pop();
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    final settings = ConnectionSettings.fromUserInput(
      restBaseUrl: _restBaseUrlController.text,
      mqttTcpHost: _mqttHostController.text,
      mqttTcpPort: int.parse(_mqttPortController.text.trim()),
    );

    try {
      await ref
          .read(connectionSettingsControllerProvider.notifier)
          .save(settings);
      await ref.read(authControllerProvider.notifier).clearSessionLocally();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection settings saved: ${settings.restBaseUrl}'),
        ),
      );
      context.go('/login');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _autoDetect() async {
    if (kIsWeb) {
      return;
    }

    setState(() => _detecting = true);
    try {
      final discovered = await ref
          .read(connectionSettingsControllerProvider.notifier)
          .autoDiscover(force: true);

      if (!mounted) {
        return;
      }

      if (discovered == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find the Smartify backend automatically on this Wi-Fi yet.',
            ),
          ),
        );
        return;
      }

      _restBaseUrlController.text = discovered.restBaseUrl;
      _mqttHostController.text = discovered.mqttTcpHost;
      _mqttPortController.text = discovered.mqttTcpPort.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Detected backend at ${discovered.restBaseUrl}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionSettingsControllerProvider);
    final effectiveConfig = connectionState.effectiveConfig;
    final requiresSetup = connectionState.requiresSetup;

    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connection')),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Web uses the current origin automatically.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Open the web app from the same Wi-Fi network at the host machine address.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              DisabledFeatureBanner(
                title: 'Current web endpoints',
                subtitle:
                    'REST: ${effectiveConfig.restBaseUrl}\nMQTT WebSocket: ${effectiveConfig.mqttWsUrl}',
                icon: Icons.language_rounded,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!requiresSetup)
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                if (!requiresSetup) const SizedBox(height: 8),
                Text(
                  requiresSetup
                      ? 'Connect To Your LAN Server'
                      : 'Connection Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Use your computer IP on the same Wi-Fi network. For the current Docker backend, LAN REST uses HTTP on port 8080 and LAN MQTT uses the same computer IP on port 1883. Docker-only names such as `mosquitto` do not work from a real phone or ESP device.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                DisabledFeatureBanner(
                  title: requiresSetup
                      ? 'Setup is required on real devices'
                      : 'Changing the server signs you in again',
                  subtitle: requiresSetup
                      ? 'This app no longer depends on Android-emulator-only addresses like 10.0.2.2.'
                      : 'The stored session will be cleared after you save a different LAN server.',
                  icon: Icons.router_outlined,
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Auto Detect On This Wi-Fi',
                  loading: _detecting,
                  backgroundColor: AppColors.primarySoft,
                  foregroundColor: AppColors.primary,
                  onPressed: _autoDetect,
                ),
                const SizedBox(height: 16),
                Text(
                  'REST Base URL',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _restBaseUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.http_rounded),
                    hintText: 'http://192.168.1.10:8080',
                  ),
                  validator: (value) {
                    final normalized = _normalizeRestBaseUrl(value ?? '');
                    if (normalized.isEmpty) {
                      return 'Please enter the REST base URL.';
                    }
                    final uri = Uri.tryParse(normalized);
                    if (uri == null ||
                        !uri.hasScheme ||
                        !(uri.scheme == 'http' || uri.scheme == 'https') ||
                        uri.host.isEmpty) {
                      return 'Please enter a valid HTTP or HTTPS URL.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Examples: `192.168.1.86`, `192.168.1.86:8080`, or `http://192.168.1.86:8080`. The app will normalize LAN inputs automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Text('MQTT Host', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mqttHostController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.sensors_outlined),
                    hintText: '192.168.1.10',
                  ),
                  validator: (value) {
                    final normalized = ConnectionSettings.normalizeMqttHost(
                      value ?? '',
                    );
                    if (normalized.isEmpty) {
                      return 'Please enter the MQTT host.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Use the same LAN IP as the REST server in most setups. Avoid `localhost`, `127.0.0.1`, `10.0.2.2`, and Docker service names like `mosquitto` when provisioning from a real phone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Text('MQTT Port', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mqttPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.numbers_rounded),
                    hintText: '1883',
                  ),
                  validator: (value) {
                    final port = int.tryParse(value?.trim() ?? '');
                    if (port == null || port < 1 || port > 65535) {
                      return 'Please enter a valid TCP port.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 26),
                PrimaryButton(
                  label: requiresSetup
                      ? 'Save And Continue'
                      : 'Save Connection',
                  loading: _saving,
                  onPressed: _save,
                ),
                const SizedBox(height: 16),
                DisabledFeatureBanner(
                  title: 'Current effective values',
                  subtitle:
                      'REST: ${effectiveConfig.restBaseUrl}\nMQTT: ${effectiveConfig.mqttTcpHost}:${effectiveConfig.mqttTcpPort}',
                  icon: Icons.info_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeRestBaseUrl(String value) {
    return ConnectionSettings.normalizeRestBaseUrl(value);
  }
}

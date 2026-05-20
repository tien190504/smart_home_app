import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/connection_settings_controller.dart';
import '../../devices/data/device_api.dart';
import '../../devices/logic/device_dashboard_controller.dart';
import '../../devices/models/device_models.dart';
import '../data/ble_provisioning_service.dart';
import '../data/qr_provision_codec.dart';
import '../models/provisioning_models.dart';

final qrProvisionCodecProvider = Provider<QrProvisionCodec>((ref) {
  return QrProvisionCodec(ref.watch(appConfigProvider));
});

final provisioningControllerProvider =
    StateNotifierProvider<ProvisioningController, ProvisioningState>((ref) {
      return ProvisioningController(
        config: ref.watch(appConfigProvider),
        qrCodec: ref.watch(qrProvisionCodecProvider),
        bleService: ref.read(bleProvisioningServiceProvider),
        deviceApi: ref.watch(deviceApiProvider),
        dashboardController: ref.read(dashboardControllerProvider.notifier),
      );
    });

class ProvisioningState {
  const ProvisioningState({
    this.draft,
    this.progress = const ProvisioningProgress(
      stage: ProvisioningStage.idle,
      progress: 0,
      message: '',
    ),
    this.result,
    this.loading = false,
    this.errorMessage,
  });

  final ProvisionDraft? draft;
  final ProvisioningProgress progress;
  final ProvisioningResult? result;
  final bool loading;
  final String? errorMessage;

  ProvisioningState copyWith({
    ProvisionDraft? draft,
    ProvisioningProgress? progress,
    ProvisioningResult? result,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return ProvisioningState(
      draft: draft ?? this.draft,
      progress: progress ?? this.progress,
      result: clearResult ? null : result ?? this.result,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ProvisioningController extends StateNotifier<ProvisioningState> {
  ProvisioningController({
    required AppConfig config,
    required QrProvisionCodec qrCodec,
    required BleProvisioningService bleService,
    required DeviceApi deviceApi,
    required DeviceDashboardController dashboardController,
  }) : _config = config,
       _qrCodec = qrCodec,
       _bleService = bleService,
       _deviceApi = deviceApi,
       _dashboardController = dashboardController,
       super(const ProvisioningState());

  final AppConfig _config;
  final QrProvisionCodec _qrCodec;
  final BleProvisioningService _bleService;
  final DeviceApi _deviceApi;
  final DeviceDashboardController _dashboardController;

  String sampleQrPayload() => _qrCodec.samplePayload();

  void reset() {
    state = const ProvisioningState();
  }

  QrProvisionPayload decodeQr(String raw) => _qrCodec.decode(raw);

  void startDraft(QrProvisionPayload payload) {
    state = ProvisioningState(
      draft: ProvisionDraft(
        qrPayload: payload,
        pop: payload.pop,
        mqttBrokerUrl: _buildProvisioningMqttBrokerUrl(),
      ),
    );
  }

  void updatePop(String pop) {
    final draft = state.draft;
    if (draft == null) {
      return;
    }
    state = state.copyWith(draft: draft.copyWith(pop: pop), clearError: true);
  }

  void updateWifi({required String ssid, required String password}) {
    final draft = state.draft;
    if (draft == null) {
      return;
    }
    final normalizedSsid = ssid.trim();
    final normalizedPassword = password.replaceAll(RegExp(r'[\r\n]'), '');
    state = state.copyWith(
      draft: draft.copyWith(
        ssid: normalizedSsid,
        password: normalizedPassword,
      ),
      clearError: true,
    );
  }

  Future<ProvisioningResult> manualProvision({
    required String deviceCode,
    required String pairingCode,
  }) async {
    state = state.copyWith(loading: true, clearError: true, clearResult: true);
    try {
      final normalizedDeviceCode = deviceCode.trim();
      final device = await _deviceApi.provisionOrCreateDevice(
        deviceCode: normalizedDeviceCode,
        pairingCode: pairingCode.trim(),
        fallbackName: normalizedDeviceCode,
      );
      final result = ProvisioningResult(
        deviceId: device.id,
        deviceCode: device.deviceCode,
        deviceName: device.name,
      );
      state = state.copyWith(
        loading: false,
        result: result,
        progress: const ProvisioningProgress(
          stage: ProvisioningStage.success,
          progress: 1,
          message: 'Device linked successfully.',
        ),
      );
      _scheduleDashboardSync(device);
      return result;
    } catch (error) {
      final message = _messageFromError(
        error,
        fallback: 'Could not link the device manually.',
      );
      state = state.copyWith(
        loading: false,
        errorMessage: message,
        progress: ProvisioningProgress(
          stage: ProvisioningStage.failure,
          progress: 0,
          message: message,
        ),
      );
      rethrow;
    }
  }

  Future<ProvisioningResult> runProvisioning() async {
    final draft = state.draft;
    if (draft == null || !draft.canStart) {
      throw StateError('Provisioning draft is incomplete.');
    }

    state = state.copyWith(loading: true, clearError: true, clearResult: true);

    try {
      final mqttBrokerUrl = _requireProvisioningMqttBrokerUrl();
      final effectiveDraft = draft.copyWith(mqttBrokerUrl: mqttBrokerUrl);
      state = state.copyWith(draft: effectiveDraft);

      await for (final progress in _bleService.provision(effectiveDraft)) {
        state = state.copyWith(progress: progress);
      }

      state = state.copyWith(
        progress: const ProvisioningProgress(
          stage: ProvisioningStage.provisioningBackend,
          progress: 0.93,
          message: 'Linking the device to your account...',
        ),
      );

      final device = await _deviceApi.provisionOrCreateDevice(
        deviceCode: effectiveDraft.qrPayload.deviceCode,
        pairingCode: effectiveDraft.qrPayload.pairingCode,
        fallbackName: effectiveDraft.qrPayload.deviceName,
      );

      final result = ProvisioningResult(
        deviceId: device.id,
        deviceCode: device.deviceCode,
        deviceName: device.name,
      );
      state = state.copyWith(
        loading: false,
        result: result,
        progress: const ProvisioningProgress(
          stage: ProvisioningStage.success,
          progress: 1,
          message: 'Device connected successfully.',
        ),
      );
      _scheduleDashboardSync(device);
      return result;
    } catch (error) {
      final message = _messageFromError(
        error,
        fallback: 'Could not add this device.',
      );
      state = state.copyWith(
        loading: false,
        errorMessage: message,
        progress: ProvisioningProgress(
          stage: ProvisioningStage.failure,
          progress: 0,
          message: message,
        ),
      );
      rethrow;
    }
  }

  Future<ProvisioningResult> linkCurrentDraftAfterFailure() async {
    final draft = state.draft;
    if (draft == null) {
      throw StateError('Provisioning draft is missing.');
    }

    state = state.copyWith(loading: true, clearError: true, clearResult: true);
    try {
      final device = await _deviceApi.provisionOrCreateDevice(
        deviceCode: draft.qrPayload.deviceCode,
        pairingCode: draft.qrPayload.pairingCode,
        fallbackName: draft.qrPayload.deviceName,
      );

      final result = ProvisioningResult(
        deviceId: device.id,
        deviceCode: device.deviceCode,
        deviceName: device.name,
      );
      state = state.copyWith(
        loading: false,
        result: result,
        progress: const ProvisioningProgress(
          stage: ProvisioningStage.success,
          progress: 1,
          message:
              'Device linked to your account. It may take a little longer to come online.',
        ),
      );
      _scheduleDashboardSync(device);
      return result;
    } catch (error) {
      final message = _messageFromError(
        error,
        fallback: 'Could not link this device right now.',
      );
      state = state.copyWith(
        loading: false,
        errorMessage: message,
        progress: ProvisioningProgress(
          stage: ProvisioningStage.failure,
          progress: 0,
          message: message,
        ),
      );
      rethrow;
    }
  }

  String _messageFromError(Object error, {required String fallback}) {
    if (error is DioException) {
      return _messageFromDio(error) ?? fallback;
    }

    if (error is StateError) {
      final message = error.message.toString().trim();
      if (message.isNotEmpty) {
        return _normalizeProvisioningMessage(message);
      }
    }

    final message = error.toString().trim();
    if (message.isEmpty) {
      return fallback;
    }
    return _normalizeProvisioningMessage(message);
  }

  String? _messageFromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }

    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return _buildConnectionErrorMessage();
    }

    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return _normalizeProvisioningMessage(message);
    }

    return null;
  }

  String _normalizeProvisioningMessage(String message) {
    final normalized = _extractProvisioningMessage(message.trim());
    final lower = normalized.toLowerCase();
    if (lower.contains('wi-fi connection failed or timed out') ||
        lower.contains(
          'timed out while waiting for the device to finish wi-fi setup',
        )) {
      return 'Wi-Fi connection failed or timed out. '
          'ESP32-C3 only supports 2.4 GHz Wi-Fi, so if you are using a phone hotspot or router on 5 GHz, switch it to 2.4 GHz and try again.';
    }
    if (lower.contains('authentication failed')) {
      return 'Wi-Fi authentication failed. '
          'Usually this means the password is incorrect, the hotspot/router is using a mode the ESP32-C3 cannot join cleanly, or the SSID/password was entered with an extra space. '
          'Please re-enter the password and prefer a 2.4 GHz WPA2 or WPA2/WPA3 mixed network.';
    }
    return normalized;
  }

  String _extractProvisioningMessage(String message) {
    if (message.isEmpty) {
      return message;
    }

    final candidates = <String>[message];
    final firstBrace = message.indexOf('{');
    final lastBrace = message.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      candidates.add(message.substring(firstBrace, lastBrace + 1));
    }

    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final extracted =
              (map['message'] as String?)?.trim() ??
              (map['status'] as String?)?.trim();
          if (extracted != null && extracted.isNotEmpty) {
            return extracted;
          }
        }
      } catch (_) {
        // Fall back to the original string.
      }
    }

    return message;
  }

  void _scheduleDashboardSync(DeviceStateSnapshot device) {
    Future<void>.microtask(() {
      _dashboardController.attachProvisionedDevice(device);
    });
  }

  String? _buildProvisioningMqttBrokerUrl() {
    final host = _config.mqttTcpHost.trim();
    if (host.isEmpty) {
      return null;
    }

    final normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost' ||
        normalizedHost == '127.0.0.1' ||
        normalizedHost == '10.0.2.2') {
      return null;
    }

    final looksLikeIpv4 = RegExp(
      r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$',
    ).hasMatch(host);
    final looksLikeHostname = host.contains('.');
    if (!looksLikeIpv4 && !looksLikeHostname) {
      return null;
    }

    return 'mqtt://$host:${_config.mqttTcpPort}';
  }

  String _requireProvisioningMqttBrokerUrl() {
    final mqttBrokerUrl = _buildProvisioningMqttBrokerUrl();
    if (mqttBrokerUrl != null) {
      return mqttBrokerUrl;
    }

    throw StateError(
      'MQTT host `${_config.mqttTcpHost}` is not valid for provisioning. '
      'In Connection Settings, use the LAN IP or reachable hostname of the '
      'computer running Docker instead of localhost, 127.0.0.1, 10.0.2.2, or Docker service names such as mosquitto.',
    );
  }

  String _buildConnectionErrorMessage() {
    final baseUrl = _config.restBaseUrl;
    final uri = Uri.tryParse(baseUrl);

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        baseUrl.contains('10.0.2.2')) {
      return 'Cannot reach backend at $baseUrl. '
          '10.0.2.2 only works on the Android emulator. '
          'If you are using a real phone, run the app with '
          '--dart-define=REST_BASE_URL=http://<your-computer-lan-ip>:8080 '
          'and --dart-define=MQTT_TCP_HOST=<your-computer-lan-ip>.';
    }

    final host = uri?.host.toLowerCase() ?? '';
    final likelyLanHost =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.');

    if (likelyLanHost && uri?.scheme.toLowerCase() == 'https') {
      return 'Cannot reach backend at $baseUrl. '
          'For the current LAN Docker setup, use http://${uri!.host}:8080 instead of HTTPS.';
    }

    if (likelyLanHost && uri != null && !uri.hasPort) {
      return 'Cannot reach backend at $baseUrl. '
          'For the current LAN Docker setup, include backend port 8080, for example http://${uri.host}:8080.';
    }

    return 'Cannot reach backend at $baseUrl. Please make sure the server is running and reachable from this device.';
  }
}

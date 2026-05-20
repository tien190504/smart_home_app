import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/connection_settings_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/logic/auth_controller.dart';
import '../data/device_api.dart';
import '../data/device_mqtt_service.dart';
import '../models/device_models.dart';

final dashboardControllerProvider =
    StateNotifierProvider<DeviceDashboardController, DashboardState>((ref) {
      final controller = DeviceDashboardController(
        api: ref.watch(deviceApiProvider),
        mqttService: ref.watch(deviceMqttServiceProvider),
        config: ref.watch(appConfigProvider),
      );

      ref.listen<AuthState>(authControllerProvider, (previous, next) {
        if (!next.isAuthenticated) {
          controller.reset();
          return;
        }
        unawaited(controller.initialize(forceRefresh: true));
      });

      ref.onDispose(controller.dispose);
      return controller;
    });

class DashboardState {
  const DashboardState({
    required this.loading,
    required this.devices,
    required this.selectedRoom,
    required this.brokerStatus,
    this.errorMessage,
  });

  const DashboardState.initial()
    : this(
        loading: true,
        devices: const [],
        selectedRoom: 'All Rooms',
        brokerStatus: BrokerConnectionStatus.disconnected,
      );

  final bool loading;
  final List<DeviceStateSnapshot> devices;
  final String selectedRoom;
  final BrokerConnectionStatus brokerStatus;
  final String? errorMessage;

  List<String> get rooms {
    final roomSet =
        devices
            .map((device) => device.roomLabel)
            .where((room) => room.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All Rooms', ...roomSet];
  }

  List<DeviceStateSnapshot> get filteredDevices {
    if (selectedRoom == 'All Rooms') {
      return devices;
    }
    return devices.where((device) => device.roomLabel == selectedRoom).toList();
  }

  DashboardState copyWith({
    bool? loading,
    List<DeviceStateSnapshot>? devices,
    String? selectedRoom,
    BrokerConnectionStatus? brokerStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DashboardState(
      loading: loading ?? this.loading,
      devices: devices ?? this.devices,
      selectedRoom: selectedRoom ?? this.selectedRoom,
      brokerStatus: brokerStatus ?? this.brokerStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class DeviceDashboardController extends StateNotifier<DashboardState> {
  DeviceDashboardController({
    required DeviceApi api,
    required DeviceMqttService mqttService,
    required AppConfig config,
  }) : _api = api,
       _mqttService = mqttService,
       _config = config,
       super(const DashboardState.initial()) {
    _telemetrySubscription = _mqttService.telemetryStream.listen(
      _applyTelemetry,
    );
    _connectionSubscription = _mqttService.connectionStream.listen((status) {
      state = state.copyWith(brokerStatus: status);
    });
  }

  final DeviceApi _api;
  final DeviceMqttService _mqttService;
  final AppConfig _config;

  StreamSubscription<MqttTelemetryEvent>? _telemetrySubscription;
  StreamSubscription<BrokerConnectionStatus>? _connectionSubscription;
  final Map<String, Timer> _heartbeatTimers = <String, Timer>{};
  final Map<String, _PendingCommand> _pendingCommands =
      <String, _PendingCommand>{};

  bool _initialized = false;
  bool _loading = false;

  Future<void> initialize({bool forceRefresh = false}) async {
    if (_loading) {
      return;
    }
    if (_initialized && !forceRefresh) {
      return;
    }
    _loading = true;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final devices = await _api.fetchDeviceSnapshots();
      _syncHeartbeatTimers(devices);
      state = state.copyWith(
        loading: false,
        devices: devices,
        brokerStatus: _mqttService.connectionStatus,
      );
      unawaited(_connectRealtime(devices));
      _initialized = true;
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load the device list.',
      );
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() => initialize(forceRefresh: true);

  Future<void> _connectRealtime(List<DeviceStateSnapshot> devices) async {
    try {
      await _mqttService.syncDeviceCodes(
        devices.map((device) => device.deviceCode),
      );
    } catch (_) {
      state = state.copyWith(
        brokerStatus: BrokerConnectionStatus.disconnected,
        errorMessage:
            'Device list loaded, but the realtime MQTT connection is unavailable.',
      );
    }
  }

  void setSelectedRoom(String room) {
    state = state.copyWith(selectedRoom: room);
  }

  DeviceStateSnapshot? deviceById(int deviceId) {
    for (final device in state.devices) {
      if (device.id == deviceId) {
        return device;
      }
    }
    return null;
  }

  List<DeviceStateSnapshot> devicesForGroup(DeviceGroup group) {
    return state.devices.where((device) => device.group == group).toList();
  }

  Future<void> toggleDevicePower(DeviceStateSnapshot device) async {
    await sendCommand(
      deviceId: device.id,
      payload: DeviceControlPayload(
        power: !device.power,
        brightness: device.brightness,
        mode: device.mode,
        scene: device.scene,
        color: device.color,
        colorTemperature: device.colorTemperature,
      ),
    );
  }

  Future<void> sendCommand({
    required int deviceId,
    required DeviceControlPayload payload,
  }) async {
    final devices = [...state.devices];
    final index = devices.indexWhere((device) => device.id == deviceId);
    if (index == -1) {
      throw StateError('Device not found.');
    }

    final current = devices[index];
    if (!current.online) {
      throw StateError('Device is offline.');
    }

    final optimistic = current.applyOptimistic(payload);
    devices[index] = optimistic;
    state = state.copyWith(devices: devices, clearError: true);

    _pendingCommands[current.deviceCode]?.timer.cancel();
    _pendingCommands[current.deviceCode] = _PendingCommand(
      previousSnapshot: current,
      payload: payload,
      timer: Timer(_config.commandAckTimeout, () {
        _rollbackPending(current.deviceCode);
      }),
    );

    try {
      await _mqttService.publishCommand(
        deviceCode: current.deviceCode,
        payload: payload,
      );
    } catch (error) {
      _rollbackPending(current.deviceCode);
      rethrow;
    }
  }

  void applyExternalPowerUpdate({
    required int deviceId,
    required bool power,
  }) {
    final devices = [...state.devices];
    final index = devices.indexWhere((device) => device.id == deviceId);
    if (index == -1) {
      return;
    }

    final current = devices[index];
    devices[index] = current.copyWith(
      power: power,
      pendingCommand: false,
      rawState: <String, dynamic>{...current.rawState, 'power': power},
    );
    state = state.copyWith(devices: devices, clearError: true);
  }

  void attachProvisionedDevice(DeviceStateSnapshot device) {
    final devices = [...state.devices];
    final existingIndex = devices.indexWhere(
      (element) => element.deviceCode == device.deviceCode,
    );
    if (existingIndex >= 0) {
      devices[existingIndex] = device;
    } else {
      devices.insert(0, device);
    }
    state = state.copyWith(
      devices: devices,
      loading: false,
      clearError: true,
    );
    _scheduleHeartbeat(device);
    unawaited(
      _mqttService.syncDeviceCodes(devices.map((item) => item.deviceCode)),
    );
  }

  void reset() {
    _initialized = false;
    _loading = false;
    for (final pending in _pendingCommands.values) {
      pending.timer.cancel();
    }
    _pendingCommands.clear();
    for (final timer in _heartbeatTimers.values) {
      timer.cancel();
    }
    _heartbeatTimers.clear();
    state = const DashboardState.initial();
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    _connectionSubscription?.cancel();
    reset();
    super.dispose();
  }

  void _applyTelemetry(MqttTelemetryEvent event) {
    final devices = [...state.devices];
    final index = devices.indexWhere(
      (device) => device.deviceCode == event.deviceCode,
    );
    if (index == -1) {
      return;
    }

    final merged = devices[index].mergeTelemetry(event);
    devices[index] = merged;
    state = state.copyWith(devices: devices);

    if (event.online == false) {
      _heartbeatTimers[event.deviceCode]?.cancel();
      _heartbeatTimers.remove(event.deviceCode);
    } else {
      _scheduleHeartbeat(merged);
    }

    final pending = _pendingCommands[event.deviceCode];
    if (pending != null && merged.acknowledges(pending.payload)) {
      pending.timer.cancel();
      _pendingCommands.remove(event.deviceCode);
      _replaceDevice(event.deviceCode, merged.copyWith(pendingCommand: false));
    }
  }

  void _markDeviceOffline(String deviceCode) {
    _heartbeatTimers.remove(deviceCode)?.cancel();
    final device = state.devices
        .where((item) => item.deviceCode == deviceCode)
        .firstOrNull;
    if (device == null) {
      return;
    }
    _replaceDevice(
      deviceCode,
      device.copyWith(online: false, status: 'OFFLINE'),
    );
  }

  void _rollbackPending(String deviceCode) {
    final pending = _pendingCommands.remove(deviceCode);
    if (pending == null) {
      return;
    }
    pending.timer.cancel();
    _replaceDevice(
      deviceCode,
      pending.previousSnapshot.copyWith(pendingCommand: false),
    );
    state = state.copyWith(
      errorMessage:
          'No confirmation was received from the device. The UI has been rolled back.',
    );
  }

  void _replaceDevice(String deviceCode, DeviceStateSnapshot snapshot) {
    final devices = [...state.devices];
    final index = devices.indexWhere(
      (device) => device.deviceCode == deviceCode,
    );
    if (index == -1) {
      return;
    }
    devices[index] = snapshot;
    state = state.copyWith(devices: devices);
  }

  void _syncHeartbeatTimers(List<DeviceStateSnapshot> devices) {
    final activeCodes = devices.map((device) => device.deviceCode).toSet();
    final staleCodes = _heartbeatTimers.keys
        .where((deviceCode) => !activeCodes.contains(deviceCode))
        .toList(growable: false);

    for (final deviceCode in staleCodes) {
      _heartbeatTimers.remove(deviceCode)?.cancel();
    }

    for (final device in devices) {
      _scheduleHeartbeat(device);
    }
  }

  void _scheduleHeartbeat(DeviceStateSnapshot device) {
    _heartbeatTimers.remove(device.deviceCode)?.cancel();
    if (!device.online) {
      return;
    }

    final lastSeenAt = device.lastTelemetryAt ?? device.lastSeenAt;
    final age = lastSeenAt == null
        ? Duration.zero
        : DateTime.now().difference(lastSeenAt.toLocal());
    final remaining = _config.heartbeatTimeout - age;

    if (remaining <= Duration.zero) {
      Future<void>.microtask(() => _markDeviceOffline(device.deviceCode));
      return;
    }

    _heartbeatTimers[device.deviceCode] = Timer(
      remaining,
      () => _markDeviceOffline(device.deviceCode),
    );
  }
}

class _PendingCommand {
  const _PendingCommand({
    required this.previousSnapshot,
    required this.payload,
    required this.timer,
  });

  final DeviceStateSnapshot previousSnapshot;
  final DeviceControlPayload payload;
  final Timer timer;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

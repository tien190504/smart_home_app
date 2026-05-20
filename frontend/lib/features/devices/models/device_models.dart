import 'dart:convert';

const Duration _backendPresenceFallbackWindow = Duration(seconds: 30);

enum DeviceGroup { lighting, cameras, electrical }

extension DeviceGroupX on DeviceGroup {
  String get key => switch (this) {
    DeviceGroup.lighting => 'lighting',
    DeviceGroup.cameras => 'cameras',
    DeviceGroup.electrical => 'electrical',
  };

  String get label => switch (this) {
    DeviceGroup.lighting => 'Lighting',
    DeviceGroup.cameras => 'Cameras',
    DeviceGroup.electrical => 'Electrical',
  };

  static DeviceGroup fromKey(String key) {
    return DeviceGroup.values.firstWhere(
      (group) => group.key == key,
      orElse: () => DeviceGroup.lighting,
    );
  }
}

enum DeviceKind {
  lighting,
  camera,
  speaker,
  climate,
  router,
  electrical,
  unknown,
}

extension DeviceKindX on DeviceKind {
  String get label => switch (this) {
    DeviceKind.lighting => 'Smart Lamp',
    DeviceKind.camera => 'Camera',
    DeviceKind.speaker => 'Speaker',
    DeviceKind.climate => 'Air Conditioner',
    DeviceKind.router => 'Router',
    DeviceKind.electrical => 'Electrical',
    DeviceKind.unknown => 'Device',
  };

  DeviceGroup get group => switch (this) {
    DeviceKind.lighting => DeviceGroup.lighting,
    DeviceKind.camera => DeviceGroup.cameras,
    DeviceKind.speaker ||
    DeviceKind.climate ||
    DeviceKind.router ||
    DeviceKind.electrical ||
    DeviceKind.unknown => DeviceGroup.electrical,
  };
}

enum BrokerConnectionStatus { disconnected, connecting, connected }

class DeviceControlPayload {
  const DeviceControlPayload({
    this.power,
    this.brightness,
    this.mode,
    this.scene,
    this.color,
    this.colorTemperature,
  });

  final bool? power;
  final int? brightness;
  final String? mode;
  final String? scene;
  final String? color;
  final int? colorTemperature;

  bool get isEmpty =>
      power == null &&
      brightness == null &&
      mode == null &&
      scene == null &&
      color == null &&
      colorTemperature == null;

  Map<String, dynamic> toMap() {
    return {
      'power': power,
      'brightness': brightness,
      'mode': mode,
      'scene': scene,
      'color': color,
      'colorTemperature': colorTemperature,
    };
  }
}

class MqttTelemetryEvent {
  const MqttTelemetryEvent({
    required this.deviceCode,
    required this.rawPayload,
    required this.state,
    required this.receivedAt,
    this.online,
    this.temperature,
    this.humidity,
    this.batteryLevel,
  });

  final String deviceCode;
  final String rawPayload;
  final Map<String, dynamic> state;
  final DateTime receivedAt;
  final bool? online;
  final double? temperature;
  final double? humidity;
  final double? batteryLevel;
}

class DeviceStateSnapshot {
  const DeviceStateSnapshot({
    required this.id,
    required this.deviceCode,
    required this.name,
    required this.description,
    required this.location,
    required this.status,
    required this.createdAt,
    required this.kind,
    required this.lastSeenAt,
    required this.lastTelemetryAt,
    required this.power,
    required this.online,
    required this.brightness,
    required this.mode,
    required this.scene,
    required this.color,
    required this.colorTemperature,
    required this.temperature,
    required this.humidity,
    required this.batteryLevel,
    required this.rawState,
    required this.pendingCommand,
  });

  factory DeviceStateSnapshot.fromDeviceJson(Map<String, dynamic> json) {
    final rawState = _parseState(json['lastKnownState']);
    final kind = _inferKind(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      deviceCode: json['deviceCode'] as String? ?? '',
    );
    final status = (json['status'] as String? ?? 'PENDING').toUpperCase();
    final lastSeenAt = DateTime.tryParse(json['lastSeenAt'] as String? ?? '');
    return DeviceStateSnapshot(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceCode: json['deviceCode'] as String? ?? '',
      name: json['name'] as String? ?? 'Smart Device',
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      status: status,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      kind: kind,
      lastSeenAt: lastSeenAt,
      lastTelemetryAt: null,
      power: _parsePower(rawState) ?? false,
      online: _resolveOnlineState(json, status, lastSeenAt),
      brightness: _parseInt(rawState, const ['brightness']) ?? 85,
      mode: _parseString(rawState, const ['mode']) ?? 'white',
      scene: _parseString(rawState, const ['scene']),
      color: _parseString(rawState, const ['color']),
      colorTemperature: _parseInt(rawState, const [
        'colorTemperature',
        'color_temp',
      ]),
      temperature: _parseDouble(rawState, const ['temperature', 'temp']),
      humidity: _parseDouble(rawState, const ['humidity']),
      batteryLevel: _parseDouble(rawState, const [
        'batteryLevel',
        'battery',
        'battery_level',
      ]),
      rawState: rawState,
      pendingCommand: false,
    );
  }

  final int id;
  final String deviceCode;
  final String name;
  final String description;
  final String location;
  final String status;
  final DateTime? createdAt;
  final DeviceKind kind;
  final DateTime? lastSeenAt;
  final DateTime? lastTelemetryAt;
  final bool power;
  final bool online;
  final int brightness;
  final String mode;
  final String? scene;
  final String? color;
  final int? colorTemperature;
  final double? temperature;
  final double? humidity;
  final double? batteryLevel;
  final Map<String, dynamic> rawState;
  final bool pendingCommand;

  String get roomLabel => location.trim().isEmpty ? 'Unassigned' : location;

  DeviceGroup get group => kind.group;

  bool get supportsBrightness => kind == DeviceKind.lighting;

  bool get supportsColor =>
      kind == DeviceKind.lighting &&
      (rawState.containsKey('color') ||
          rawState.containsKey('colorTemperature') ||
          rawState.containsKey('mode'));

  bool get supportsScenes =>
      kind == DeviceKind.lighting &&
      (rawState.containsKey('scene') || rawState.containsKey('mode'));

  bool? get relayOnState => _parseBooleanValue(rawState['relayOn']);

  bool? get switchActiveState => _parseBooleanValue(rawState['switchActive']);

  bool get measurementValid =>
      _parseBooleanValue(rawState['measurementValid']) ?? false;

  double? get voltageV => _parseDouble(rawState, const ['voltageV']);

  double? get currentA => _parseDouble(rawState, const ['currentA']);

  double? get powerW => _parseDouble(rawState, const ['powerW']);

  double? get energyKWh => _parseDouble(rawState, const ['energyKWh']);

  double? get frequencyHz => _parseDouble(rawState, const ['frequencyHz']);

  double? get powerFactor => _parseDouble(rawState, const ['powerFactor']);

  bool get hasElectricalMetrics =>
      voltageV != null ||
      currentA != null ||
      powerW != null ||
      energyKWh != null ||
      frequencyHz != null ||
      powerFactor != null ||
      rawState.containsKey('measurementValid');

  DeviceStateSnapshot copyWith({
    String? name,
    String? description,
    String? location,
    String? status,
    DateTime? lastSeenAt,
    DateTime? lastTelemetryAt,
    bool? power,
    bool? online,
    int? brightness,
    String? mode,
    String? scene,
    bool clearScene = false,
    String? color,
    bool clearColor = false,
    int? colorTemperature,
    bool clearColorTemperature = false,
    double? temperature,
    bool clearTemperature = false,
    double? humidity,
    bool clearHumidity = false,
    double? batteryLevel,
    bool clearBatteryLevel = false,
    Map<String, dynamic>? rawState,
    bool? pendingCommand,
  }) {
    return DeviceStateSnapshot(
      id: id,
      deviceCode: deviceCode,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      status: status ?? this.status,
      createdAt: createdAt,
      kind: kind,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastTelemetryAt: lastTelemetryAt ?? this.lastTelemetryAt,
      power: power ?? this.power,
      online: online ?? this.online,
      brightness: brightness ?? this.brightness,
      mode: mode ?? this.mode,
      scene: clearScene ? null : scene ?? this.scene,
      color: clearColor ? null : color ?? this.color,
      colorTemperature: clearColorTemperature
          ? null
          : colorTemperature ?? this.colorTemperature,
      temperature: clearTemperature ? null : temperature ?? this.temperature,
      humidity: clearHumidity ? null : humidity ?? this.humidity,
      batteryLevel: clearBatteryLevel
          ? null
          : batteryLevel ?? this.batteryLevel,
      rawState: rawState ?? this.rawState,
      pendingCommand: pendingCommand ?? this.pendingCommand,
    );
  }

  DeviceStateSnapshot mergeTelemetry(MqttTelemetryEvent event) {
    final mergedState = <String, dynamic>{...rawState, ...event.state};
    final nextOnline = event.online ?? online;
    final nextStatus = switch ((nextOnline, status)) {
      (true, _) => 'ACTIVE',
      (false, 'DISABLED') => 'DISABLED',
      (false, 'PENDING') => 'PENDING',
      _ => 'OFFLINE',
    };
    final nextSeenAt = nextOnline ? event.receivedAt : lastSeenAt;
    final nextTelemetryAt = nextOnline ? event.receivedAt : lastTelemetryAt;
    return copyWith(
      status: nextStatus,
      lastSeenAt: nextSeenAt,
      lastTelemetryAt: nextTelemetryAt,
      power: _parsePower(mergedState) ?? power,
      online: nextOnline,
      brightness: _parseInt(mergedState, const ['brightness']) ?? brightness,
      mode: _parseString(mergedState, const ['mode']) ?? mode,
      scene: _parseString(mergedState, const ['scene']),
      clearScene: !mergedState.containsKey('scene') && scene == null,
      color: _parseString(mergedState, const ['color']),
      clearColor: !mergedState.containsKey('color') && color == null,
      colorTemperature: _parseInt(mergedState, const [
        'colorTemperature',
        'color_temp',
      ]),
      clearColorTemperature:
          !mergedState.containsKey('colorTemperature') &&
          !mergedState.containsKey('color_temp') &&
          colorTemperature == null,
      temperature: event.temperature,
      humidity: event.humidity,
      batteryLevel: event.batteryLevel,
      rawState: mergedState,
      pendingCommand: false,
    );
  }

  DeviceStateSnapshot applyOptimistic(DeviceControlPayload payload) {
    final optimisticState = <String, dynamic>{...rawState};
    if (payload.power != null) optimisticState['power'] = payload.power;
    if (payload.brightness != null) {
      optimisticState['brightness'] = payload.brightness;
    }
    if (payload.mode != null) optimisticState['mode'] = payload.mode;
    if (payload.scene != null) optimisticState['scene'] = payload.scene;
    if (payload.color != null) optimisticState['color'] = payload.color;
    if (payload.colorTemperature != null) {
      optimisticState['colorTemperature'] = payload.colorTemperature;
    }

    return copyWith(
      power: payload.power,
      brightness: payload.brightness,
      mode: payload.mode,
      scene: payload.scene,
      color: payload.color,
      colorTemperature: payload.colorTemperature,
      rawState: optimisticState,
      pendingCommand: true,
    );
  }

  bool acknowledges(DeviceControlPayload payload) {
    if (payload.power != null && power != payload.power) {
      return false;
    }
    if (payload.brightness != null &&
        (brightness - payload.brightness!).abs() > 2) {
      return false;
    }
    if (payload.mode != null && mode != payload.mode) {
      return false;
    }
    if (payload.scene != null && scene != payload.scene) {
      return false;
    }
    if (payload.color != null && color != payload.color) {
      return false;
    }
    if (payload.colorTemperature != null &&
        colorTemperature != payload.colorTemperature) {
      return false;
    }
    return true;
  }
}

DeviceKind _inferKind({
  required String name,
  required String description,
  required String deviceCode,
}) {
  final merged = '$name $description $deviceCode'.toLowerCase();
  if (merged.contains('lamp') ||
      merged.contains('light') ||
      merged.contains('bulb')) {
    return DeviceKind.lighting;
  }
  if (merged.contains('camera') ||
      merged.contains('cctv') ||
      merged.contains('webcam')) {
    return DeviceKind.camera;
  }
  if (merged.contains('speaker') || merged.contains('audio')) {
    return DeviceKind.speaker;
  }
  if (merged.contains('air') ||
      merged.contains('conditioner') ||
      merged.contains('ac')) {
    return DeviceKind.climate;
  }
  if (merged.contains('router') || merged.contains('wifi')) {
    return DeviceKind.router;
  }
  if (merged.contains('plug') ||
      merged.contains('socket') ||
      merged.contains('relay') ||
      merged.contains('switch')) {
    return DeviceKind.electrical;
  }
  return DeviceKind.unknown;
}

Map<String, dynamic> _parseState(Object? rawState) {
  if (rawState == null) {
    return <String, dynamic>{};
  }

  if (rawState is Map<String, dynamic>) {
    return rawState;
  }

  if (rawState is String) {
    final trimmed = rawState.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{};
    }

    final directBoolean = _parseBooleanValue(trimmed);
    if (directBoolean != null) {
      return <String, dynamic>{'power': directBoolean};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        if (decoded['state'] is Map<String, dynamic>) {
          return Map<String, dynamic>.from(
            decoded['state'] as Map<String, dynamic>,
          );
        }
        return decoded;
      }
      if (decoded is bool) {
        return <String, dynamic>{'power': decoded};
      }
      if (decoded is String) {
        final boolean = _parseBooleanValue(decoded);
        return boolean == null
            ? <String, dynamic>{'raw': decoded}
            : {'power': boolean};
      }
    } catch (_) {
      return <String, dynamic>{'raw': trimmed};
    }
  }

  return <String, dynamic>{};
}

bool? _parsePower(Map<String, dynamic> rawState) {
  for (final key in const [
    'power',
    'relayOn',
    'on',
    'isOn',
    'enabled',
    'state',
  ]) {
    final parsed = _parseBooleanValue(rawState[key]);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

bool? _parseBooleanValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'on':
      case 'true':
      case '1':
      case 'online':
      case 'active':
        return true;
      case 'off':
      case 'false':
      case '0':
      case 'offline':
      case 'inactive':
        return false;
    }
  }
  return null;
}

int? _parseInt(Map<String, dynamic> rawState, List<String> keys) {
  for (final key in keys) {
    final value = rawState[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

double? _parseDouble(Map<String, dynamic> rawState, List<String> keys) {
  for (final key in keys) {
    final value = rawState[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

String? _parseString(Map<String, dynamic> rawState, List<String> keys) {
  for (final key in keys) {
    final value = rawState[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

bool _resolveOnlineState(
  Map<String, dynamic> json,
  String status,
  DateTime? lastSeenAt,
) {
  final explicitOnline = _parseBooleanValue(json['online']);
  if (explicitOnline != null) {
    return explicitOnline;
  }

  final normalizedStatus = status.trim().toUpperCase();
  if (normalizedStatus == 'OFFLINE' ||
      normalizedStatus == 'PENDING' ||
      normalizedStatus == 'DISABLED') {
    return false;
  }

  if (lastSeenAt == null) {
    return false;
  }

  return DateTime.now().difference(lastSeenAt.toLocal()) <=
      _backendPresenceFallbackWindow;
}

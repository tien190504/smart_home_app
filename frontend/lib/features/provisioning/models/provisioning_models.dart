import 'dart:convert';

class BleDescriptor {
  const BleDescriptor({
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    required this.notifyCharacteristicUuid,
  });

  factory BleDescriptor.fromJson(Map<String, dynamic> json) {
    return BleDescriptor(
      serviceUuid: json['serviceUuid'] as String? ?? '',
      writeCharacteristicUuid:
          json['writeCharacteristicUuid'] as String? ?? '',
      notifyCharacteristicUuid:
          json['notifyCharacteristicUuid'] as String? ?? '',
    );
  }

  final String serviceUuid;
  final String writeCharacteristicUuid;
  final String notifyCharacteristicUuid;

  Map<String, dynamic> toJson() {
    return {
      'serviceUuid': serviceUuid,
      'writeCharacteristicUuid': writeCharacteristicUuid,
      'notifyCharacteristicUuid': notifyCharacteristicUuid,
    };
  }
}

class QrProvisionPayload {
  const QrProvisionPayload({
    required this.deviceCode,
    required this.pairingCode,
    required this.pop,
    required this.deviceName,
    required this.ble,
  });

  factory QrProvisionPayload.fromJson(Map<String, dynamic> json) {
    return QrProvisionPayload(
      deviceCode: json['deviceCode'] as String? ?? '',
      pairingCode: json['pairingCode'] as String? ?? '',
      pop: json['pop'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Smart Device',
      ble: BleDescriptor.fromJson(
        Map<String, dynamic>.from(json['ble'] as Map? ?? const {}),
      ),
    );
  }

  final String deviceCode;
  final String pairingCode;
  final String pop;
  final String deviceName;
  final BleDescriptor ble;

  Map<String, dynamic> toJson() {
    return {
      'deviceCode': deviceCode,
      'pairingCode': pairingCode,
      'pop': pop,
      'deviceName': deviceName,
      'ble': ble.toJson(),
    };
  }
}

class ProvisionDraft {
  const ProvisionDraft({
    required this.qrPayload,
    required this.pop,
    this.mqttBrokerUrl,
    this.ssid = '',
    this.password = '',
  });

  final QrProvisionPayload qrPayload;
  final String pop;
  final String? mqttBrokerUrl;
  final String ssid;
  final String password;

  ProvisionDraft copyWith({
    String? pop,
    String? mqttBrokerUrl,
    String? ssid,
    String? password,
  }) {
    return ProvisionDraft(
      qrPayload: qrPayload,
      pop: pop ?? this.pop,
      mqttBrokerUrl: mqttBrokerUrl ?? this.mqttBrokerUrl,
      ssid: ssid ?? this.ssid,
      password: password ?? this.password,
    );
  }

  bool get canStart =>
      qrPayload.deviceCode.trim().isNotEmpty &&
      qrPayload.pairingCode.trim().isNotEmpty &&
      pop.trim().isNotEmpty &&
      ssid.trim().isNotEmpty;
}

class BleProvisionPacket {
  const BleProvisionPacket({
    required this.deviceCode,
    required this.pairingCode,
    required this.pop,
    required this.ssid,
    required this.password,
    this.mqttBrokerUrl,
  });

  final String deviceCode;
  final String pairingCode;
  final String pop;
  final String ssid;
  final String password;
  final String? mqttBrokerUrl;

  Map<String, dynamic> toJson() {
    return {
      'deviceCode': deviceCode,
      'pairingCode': pairingCode,
      'pop': pop,
      'ssid': ssid,
      'password': password,
      if (mqttBrokerUrl != null && mqttBrokerUrl!.trim().isNotEmpty)
        'mqttBrokerUrl': mqttBrokerUrl!.trim(),
    };
  }

  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));
}

enum ProvisioningStage {
  idle,
  scanning,
  connecting,
  discovering,
  sendingWifi,
  waitingForDevice,
  provisioningBackend,
  success,
  failure,
}

class ProvisioningProgress {
  const ProvisioningProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.details,
  });

  final ProvisioningStage stage;
  final double progress;
  final String message;
  final String? details;
}

class ProvisioningResult {
  const ProvisioningResult({
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
  });

  final int deviceId;
  final String deviceCode;
  final String deviceName;
}

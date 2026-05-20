import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../models/provisioning_models.dart';

class QrProvisionCodec {
  const QrProvisionCodec(this._config);

  final AppConfig _config;

  QrProvisionPayload decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('QR payload is empty.');
    }

    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR payload must be a JSON object.');
    }

    final payload = QrProvisionPayload.fromJson(decoded);
    if (payload.deviceCode.trim().isEmpty ||
        payload.pairingCode.trim().isEmpty ||
        payload.pop.trim().isEmpty) {
      throw const FormatException(
        'QR payload is missing deviceCode, pairingCode, or pop.',
      );
    }

    return QrProvisionPayload(
      deviceCode: payload.deviceCode.trim(),
      pairingCode: payload.pairingCode.trim(),
      pop: payload.pop.trim(),
      deviceName: payload.deviceName.trim().isEmpty
          ? _fallbackDeviceName(payload.deviceCode.trim())
          : payload.deviceName.trim(),
      ble: BleDescriptor(
        serviceUuid: payload.ble.serviceUuid.trim().isEmpty
            ? _config.defaultBleServiceUuid
            : payload.ble.serviceUuid.trim(),
        writeCharacteristicUuid:
            payload.ble.writeCharacteristicUuid.trim().isEmpty
                ? _config.defaultBleWriteCharacteristicUuid
                : payload.ble.writeCharacteristicUuid.trim(),
        notifyCharacteristicUuid:
            payload.ble.notifyCharacteristicUuid.trim().isEmpty
                ? _config.defaultBleNotifyCharacteristicUuid
                : payload.ble.notifyCharacteristicUuid.trim(),
      ),
    );
  }

  String encode(QrProvisionPayload payload) {
    return const JsonEncoder.withIndent('  ').convert(payload.toJson());
  }

  String samplePayload() {
    return encode(
      QrProvisionPayload(
        deviceCode: 'LAMP-LIVING-01',
        pairingCode: 'K7COL6S2NX',
        pop: '12345678',
        deviceName: 'Smart Lamp',
        ble: BleDescriptor(
          serviceUuid: _config.defaultBleServiceUuid,
          writeCharacteristicUuid: _config.defaultBleWriteCharacteristicUuid,
          notifyCharacteristicUuid: _config.defaultBleNotifyCharacteristicUuid,
        ),
      ),
    );
  }

  String _fallbackDeviceName(String deviceCode) {
    final trimmed = deviceCode.trim();
    if (trimmed.isEmpty) {
      return 'Smart Device';
    }

    final upper = trimmed.toUpperCase();
    if (upper.startsWith('IOTESP-') && upper.length > 7) {
      return 'Smart Electrical Node ${upper.substring(7)}';
    }

    return trimmed;
  }
}

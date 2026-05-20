import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/provisioning_models.dart';

final bleProvisioningServiceProvider = Provider<BleProvisioningService>((ref) {
  return const BleProvisioningService();
});

class BleProvisioningService {
  const BleProvisioningService();

  Stream<ProvisioningProgress> provision(ProvisionDraft draft) async* {
    if (kIsWeb) {
      throw const BleProvisioningException(
        'Bluetooth provisioning is only available on the mobile app.',
      );
    }

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw const BleProvisioningException('Bluetooth is not supported.');
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn(timeout: 12);
      } catch (_) {
        throw const BleProvisioningException(
          'Please enable Bluetooth before provisioning the device.',
        );
      }
    }

    yield const ProvisioningProgress(
      stage: ProvisioningStage.scanning,
      progress: 0.14,
      message: 'Looking for your device over Bluetooth...',
    );

    final scanResult = await _scanForDevice(draft);
    if (scanResult == null) {
      throw BleProvisioningException(
        'Could not find BLE device ${draft.qrPayload.deviceCode}.',
      );
    }

    final device = scanResult.device;

    yield ProvisioningProgress(
      stage: ProvisioningStage.connecting,
      progress: 0.34,
      message: 'Connecting to ${draft.qrPayload.deviceName}...',
    );

    await device.connect(timeout: const Duration(seconds: 15));

    StreamSubscription<List<int>>? notifySubscription;
    StreamController<ProvisioningProgress>? progressController;
    var provisioningCompleted = false;
    try {
      yield const ProvisioningProgress(
        stage: ProvisioningStage.discovering,
        progress: 0.5,
        message: 'Discovering provisioning service...',
      );

      final services = await device.discoverServices();
      final serviceGuid = Guid(draft.qrPayload.ble.serviceUuid);
      final writeGuid = Guid(draft.qrPayload.ble.writeCharacteristicUuid);
      final notifyGuid = Guid(draft.qrPayload.ble.notifyCharacteristicUuid);

      final service = services
          .where((item) => item.uuid == serviceGuid)
          .firstOrNull;
      if (service == null) {
        throw const BleProvisioningException(
          'Provisioning service UUID was not found on the device.',
        );
      }

      final writeCharacteristic = service.characteristics
          .where((item) => item.uuid == writeGuid)
          .firstOrNull;
      if (writeCharacteristic == null) {
        throw const BleProvisioningException(
          'BLE write characteristic UUID was not found.',
        );
      }

      final notifyCharacteristic = service.characteristics
          .where((item) => item.uuid == notifyGuid)
          .firstOrNull;
      if (notifyCharacteristic == null) {
        throw const BleProvisioningException(
          'BLE notify characteristic UUID was not found.',
        );
      }

      await notifyCharacteristic.setNotifyValue(true);
      progressController = StreamController<ProvisioningProgress>();
      final currentProgressController = progressController;
      notifySubscription = notifyCharacteristic.lastValueStream.listen((value) {
        if (value.isEmpty) {
          return;
        }
        final message = utf8.decode(value, allowMalformed: true);
        final decoded = _decodeProgress(message);
        if (decoded != null) {
          if (currentProgressController.isClosed) {
            return;
          }
          currentProgressController.add(decoded);
        }
      });

      yield const ProvisioningProgress(
        stage: ProvisioningStage.sendingWifi,
        progress: 0.64,
        message: 'Sending Wi-Fi credentials to the device...',
      );

      final packet = BleProvisionPacket(
        deviceCode: draft.qrPayload.deviceCode,
        pairingCode: draft.qrPayload.pairingCode,
        pop: draft.pop,
        ssid: draft.ssid,
        password: draft.password,
        mqttBrokerUrl: draft.mqttBrokerUrl,
      );

      await writeCharacteristic.write(
        packet.toBytes(),
        withoutResponse: !writeCharacteristic.properties.write,
        allowLongWrite:
            writeCharacteristic.properties.write &&
            packet.toBytes().length > 140,
      );

      yield const ProvisioningProgress(
        stage: ProvisioningStage.waitingForDevice,
        progress: 0.78,
        message: 'Waiting for the device to apply network settings...',
      );

      await for (final progress in currentProgressController.stream.timeout(
        const Duration(seconds: 75),
        onTimeout: (sink) => sink.close(),
      )) {
        yield progress;
        if (progress.stage == ProvisioningStage.failure) {
          throw BleProvisioningException(progress.message);
        }
        if (progress.stage == ProvisioningStage.success) {
          provisioningCompleted = true;
          break;
        }
      }

      if (!provisioningCompleted) {
        final latestStatus = await _readLatestStatus(notifyCharacteristic);
        if (latestStatus != null) {
          yield latestStatus;
          if (latestStatus.stage == ProvisioningStage.failure) {
            throw BleProvisioningException(latestStatus.message);
          }
          if (latestStatus.stage == ProvisioningStage.success) {
            provisioningCompleted = true;
          }
        }
      }

      if (!provisioningCompleted) {
        throw const BleProvisioningException(
          'Timed out while waiting for the device to finish Wi-Fi setup. '
          'Make sure the network is 2.4 GHz and the password is correct.',
        );
      }
    } finally {
      await notifySubscription?.cancel();
      await progressController?.close();
      await device.disconnect();
    }
  }

  Future<ScanResult?> _scanForDevice(ProvisionDraft draft) async {
    final primary = await _scanAttempt(
      draft,
      useServiceFilter: true,
      timeout: const Duration(seconds: 12),
    );
    if (primary != null) {
      return primary;
    }

    return _scanAttempt(
      draft,
      useServiceFilter: false,
      timeout: const Duration(seconds: 8),
    );
  }

  Future<ScanResult?> _scanAttempt(
    ProvisionDraft draft, {
    required bool useServiceFilter,
    required Duration timeout,
  }) async {
    final serviceGuid = Guid(draft.qrPayload.ble.serviceUuid);
    final completer = Completer<ScanResult?>();
    final seenResults = <String, ScanResult>{};

    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      ScanResult? bestMatch;
      var bestScore = 0;

      for (final result in results) {
        final deviceKey = result.device.remoteId.toString();
        seenResults[deviceKey] = result;

        final score = _deviceIdentityScore(result, draft);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = result;
        }
      }

      if (bestMatch != null && bestScore >= 70 && !completer.isCompleted) {
        completer.complete(bestMatch);
      }
    });

    try {
      if (useServiceFilter) {
        await FlutterBluePlus.startScan(
          withServices: [serviceGuid],
          webOptionalServices: [serviceGuid],
          androidUsesFineLocation: true,
          timeout: timeout,
        );
      } else {
        await FlutterBluePlus.startScan(
          webOptionalServices: [serviceGuid],
          androidUsesFineLocation: true,
          timeout: timeout,
        );
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => _bestFallbackCandidate(
          seenResults.values,
          draft,
          useServiceFilter: useServiceFilter,
        ),
      );
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  ScanResult? _bestFallbackCandidate(
    Iterable<ScanResult> results,
    ProvisionDraft draft, {
    required bool useServiceFilter,
  }) {
    ScanResult? bestMatch;
    var bestScore = 0;
    final uniqueResults = results.toList(growable: false);

    for (final result in uniqueResults) {
      final score = _deviceIdentityScore(result, draft);
      if (score > bestScore ||
          (score == bestScore &&
              bestMatch != null &&
              result.rssi > bestMatch.rssi)) {
        bestScore = score;
        bestMatch = result;
      }
    }

    if (bestMatch != null && bestScore > 0) {
      return bestMatch;
    }

    if (useServiceFilter && uniqueResults.length == 1) {
      return uniqueResults.single;
    }

    return null;
  }

  int _deviceIdentityScore(ScanResult result, ProvisionDraft draft) {
    final expectedServiceGuid = Guid(draft.qrPayload.ble.serviceUuid);
    final normalizedPlatformName = _normalizeBleText(
      result.device.platformName,
    );
    final normalizedAdvertisementName = _normalizeBleText(
      result.advertisementData.advName,
    );
    final normalizedRemoteId = _normalizeBleText(result.device.remoteId.str);
    final normalizedDeviceCode = _normalizeBleText(draft.qrPayload.deviceCode);
    final normalizedDeviceName = _normalizeBleText(draft.qrPayload.deviceName);
    final suffixCandidates = <String>{
      _identitySuffix(normalizedDeviceCode),
      _identitySuffix(normalizedDeviceName),
    }..removeWhere((value) => value.length < 4);
    final advertisesExpectedService =
        result.advertisementData.serviceUuids.any(
          (uuid) => uuid == expectedServiceGuid,
        ) ||
        result.advertisementData.serviceData.keys.any(
          (uuid) => uuid == expectedServiceGuid,
        );

    var score = 0;
    if (advertisesExpectedService) {
      score = 70;
    }

    for (final suffix in suffixCandidates) {
      if (normalizedRemoteId.endsWith(suffix)) {
        score = score < 140 ? 140 : score;
      }
    }

    for (final candidate in <String>[
      normalizedPlatformName,
      normalizedAdvertisementName,
    ]) {
      if (candidate.isEmpty) {
        continue;
      }

      if (candidate == normalizedDeviceCode ||
          candidate == normalizedDeviceName) {
        score = score < 120 ? 120 : score;
      }

      if (normalizedDeviceCode.isNotEmpty &&
          (candidate.contains(normalizedDeviceCode) ||
              normalizedDeviceCode.contains(candidate))) {
        score = score < 100 ? 100 : score;
      }

      if (normalizedDeviceName.isNotEmpty &&
          (candidate.contains(normalizedDeviceName) ||
              normalizedDeviceName.contains(candidate))) {
        score = score < 95 ? 95 : score;
      }

      for (final suffix in suffixCandidates) {
        if (candidate.contains(suffix)) {
          score = score < 80 ? 80 : score;
        }
      }
    }

    return score;
  }

  String _normalizeBleText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _identitySuffix(String normalized) {
    if (normalized.length <= 6) {
      return normalized;
    }
    return normalized.substring(normalized.length - 6);
  }

  ProvisioningProgress? _decodeProgress(String message) {
    final sanitized = _sanitizeBleStatusMessage(message);
    if (sanitized.isEmpty) {
      return null;
    }

    final decoded = _decodeProgressPayload(sanitized);
    if (decoded != null) {
      final progressValue = (decoded['progress'] as num?)?.toDouble();
      final text =
          (decoded['message'] as String?)?.trim() ??
          (decoded['status'] as String?)?.trim() ??
          'Device is processing provisioning data...';
      final stage = _stageForDeviceUpdate(progressValue, text);
      return ProvisioningProgress(
        stage: stage,
        progress: _mapDeviceProgressToUi(progressValue, stage),
        message: text,
        details: sanitized,
      );
    }

    final stage = _stageForDeviceUpdate(null, sanitized);
    return ProvisioningProgress(
      stage: stage,
      progress: _mapDeviceProgressToUi(null, stage),
      message: sanitized,
      details: sanitized,
    );
  }

  Map<String, dynamic>? _decodeProgressPayload(String message) {
    for (final candidate in _candidateJsonPayloads(message)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Try the next candidate.
      }
    }
    return null;
  }

  Iterable<String> _candidateJsonPayloads(String message) sync* {
    yield message;

    final firstBrace = message.indexOf('{');
    final lastBrace = message.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      yield message.substring(firstBrace, lastBrace + 1);
    }

    if (lastBrace >= 0) {
      final prefix = message.substring(0, lastBrace + 1);
      if (prefix != message) {
        yield prefix;
      }
    }
  }

  String _sanitizeBleStatusMessage(String message) {
    final cleaned = message
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\u0001-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .trim();
    return cleaned;
  }

  Future<ProvisioningProgress?> _readLatestStatus(
    BluetoothCharacteristic notifyCharacteristic,
  ) async {
    try {
      final value = await notifyCharacteristic.read();
      if (value.isEmpty) {
        return null;
      }
      return _decodeProgress(utf8.decode(value, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  ProvisioningStage _stageForDeviceUpdate(
    double? progressValue,
    String message,
  ) {
    final normalizedMessage = message.trim().toLowerCase();
    if ((progressValue ?? 0) >= 100 || normalizedMessage.contains('success')) {
      return ProvisioningStage.success;
    }

    final isInitialReadyMessage = normalizedMessage.contains(
      'ready to receive wi-fi credentials',
    );
    if (!isInitialReadyMessage &&
        (((progressValue ?? 1) <= 0) || _looksLikeFailure(normalizedMessage))) {
      return ProvisioningStage.failure;
    }

    return ProvisioningStage.waitingForDevice;
  }

  double _mapDeviceProgressToUi(
    double? progressValue,
    ProvisioningStage stage,
  ) {
    return switch (stage) {
      ProvisioningStage.success => 0.9,
      ProvisioningStage.failure => 0,
      _ =>
        progressValue == null
            ? 0.86
            : (0.72 + (progressValue.clamp(0, 100) / 100) * 0.18),
    };
  }

  bool _looksLikeFailure(String message) {
    return message.contains('failed') ||
        message.contains('invalid') ||
        message.contains('timed out') ||
        message.contains('does not match') ||
        message.contains('missing') ||
        message.contains('too large') ||
        message.contains('not valid') ||
        message.contains('not ready');
  }
}

class BleProvisioningException implements Exception {
  const BleProvisioningException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

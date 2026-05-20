import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'qr_gallery_analyze_path_stub.dart'
    if (dart.library.io) 'qr_gallery_analyze_path_io.dart' as gallery_path;

final qrImageScanServiceProvider = Provider<QrImageScanService>((ref) {
  return QrImageScanService();
});

class QrImageScanService {
  const QrImageScanService();

  Future<QrImageScanResult> pickFromGallery() async {
    if (kIsWeb) {
      return const QrImageScanResult(
        errorMessage: 'Picking a QR image from the gallery is not supported on web.',
      );
    }

    final imagePicker = ImagePicker();
    var pickedFile = await imagePicker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );

    if (pickedFile == null) {
      final recovered = await restoreLostSelection();
      if (recovered.rawPayload != null || recovered.errorMessage != null) {
        return recovered;
      }
    }

    return _decodeQrFromFile(pickedFile);
  }

  Future<QrImageScanResult> restoreLostSelection() async {
    if (kIsWeb) {
      return const QrImageScanResult();
    }

    final imagePicker = ImagePicker();
    try {
      final response = await imagePicker.retrieveLostData();
      if (response.isEmpty) {
        return const QrImageScanResult();
      }
      if (response.exception != null) {
        return const QrImageScanResult(
          errorMessage: 'Could not restore the selected QR image.',
        );
      }

      final file = response.file ?? response.files?.firstOrNull;
      return _decodeQrFromFile(file);
    } on UnimplementedError {
      return const QrImageScanResult();
    } catch (_) {
      return const QrImageScanResult(
        errorMessage: 'Could not restore the selected QR image.',
      );
    }
  }

  Future<QrImageScanResult> _decodeQrFromFile(XFile? pickedFile) async {
    if (pickedFile == null) {
      return const QrImageScanResult();
    }

    final analyzer = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );

    try {
      final pathForAnalyze = await gallery_path.qrGalleryPathForAnalyze(
        pickedFile,
      );
      final capture = await analyzer.analyzeImage(pathForAnalyze);
      final rawValue = capture?.barcodes.firstOrNull?.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) {
        return const QrImageScanResult(
          errorMessage: 'No QR code could be found in this image.',
        );
      }

      return QrImageScanResult(rawPayload: rawValue);
    } catch (_) {
      return const QrImageScanResult(
        errorMessage: 'This image could not be analyzed for QR content.',
      );
    } finally {
      analyzer.dispose();
    }
  }
}

class QrImageScanResult {
  const QrImageScanResult({
    this.rawPayload,
    this.errorMessage,
  });

  final String? rawPayload;
  final String? errorMessage;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Runs [action] after the current frame so [StateNotifier] state from
/// [startDraft] is visible to the next route before it builds.
void scheduleProvisioningNavigation(void Function() action) {
  SchedulerBinding.instance.addPostFrameCallback((_) => action());
}

import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// Android [MobileScannerHandler] uses `Uri.fromFile(File(path))`, so the path
/// must be a real filesystem path. Gallery picks often yield `content://` or
/// paths that ML Kit cannot open — copy bytes to a temp file first.
Future<String> qrGalleryPathForAnalyze(XFile file) async {
  var path = file.path.trim();
  if (path.startsWith('file://')) {
    path = Uri.parse(path).toFilePath();
  }

  var needsMaterialize = path.isEmpty || path.startsWith('content:');
  if (!needsMaterialize) {
    try {
      needsMaterialize = !File(path).existsSync();
    } on Object {
      needsMaterialize = true;
    }
  }

  if (!needsMaterialize) {
    return path;
  }

  final bytes = await file.readAsBytes();
  final tmp = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'qr_gallery_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await tmp.writeAsBytes(bytes, flush: true);
  return tmp.path;
}

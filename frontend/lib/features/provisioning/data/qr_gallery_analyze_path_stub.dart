import 'package:image_picker/image_picker.dart';

/// Web / non-IO: pass path through (gallery analyze is not used on web).
Future<String> qrGalleryPathForAnalyze(XFile file) async => file.path;

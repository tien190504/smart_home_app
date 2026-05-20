import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/api_client.dart';
import '../../devices/data/device_api.dart';
import '../models/assistant_models.dart';

final assistantApiProvider = Provider<AssistantApi>((ref) {
  return AssistantApi(ref.watch(apiClientProvider));
});

class AssistantApi {
  AssistantApi(this._client);

  final ApiClient _client;

  Future<AssistantReply> chat({
    required String message,
    double? latitude,
    double? longitude,
  }) async {
    final json = await _client.postMap(
      '/api/assistant/chat',
      data: {
        'message': message.trim(),
        'latitude': latitude,
        'longitude': longitude,
      },
    );

    return AssistantReply.fromJson(json);
  }
}

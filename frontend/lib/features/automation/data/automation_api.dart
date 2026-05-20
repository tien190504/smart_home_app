import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/api_client.dart';
import '../../devices/data/device_api.dart';
import '../models/automation_models.dart';

final automationApiProvider = Provider<AutomationApi>((ref) {
  return AutomationApi(ref.watch(apiClientProvider));
});

class AutomationApi {
  AutomationApi(this._client);

  final ApiClient _client;

  Future<List<AutomationSchedule>> fetchSchedules() async {
    final json = await _client.getList('/api/automations');
    return json
        .map(
          (item) =>
              AutomationSchedule.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<AutomationSchedule> createSchedule(
    AutomationScheduleRequest request,
  ) async {
    final json = await _client.postMap(
      '/api/automations',
      data: request.toJson(),
    );
    return AutomationSchedule.fromJson(json);
  }

  Future<AutomationSchedule> updateSchedule(
    int scheduleId,
    AutomationScheduleRequest request,
  ) async {
    final json = await _client.putMap(
      '/api/automations/$scheduleId',
      data: request.toJson(),
    );
    return AutomationSchedule.fromJson(json);
  }

  Future<void> deleteSchedule(int scheduleId) {
    return _client.delete('/api/automations/$scheduleId');
  }
}

import 'package:flutter/material.dart';

class AutomationSchedule {
  const AutomationSchedule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.targetPower,
    required this.timeOfDay,
    required this.daysOfWeek,
    required this.timezoneOffsetMinutes,
    required this.deviceId,
    required this.deviceName,
    required this.deviceCode,
    required this.deviceLocation,
    required this.createdAt,
    required this.updatedAt,
    required this.lastTriggeredAt,
  });

  factory AutomationSchedule.fromJson(Map<String, dynamic> json) {
    return AutomationSchedule(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Automation',
      enabled: json['enabled'] as bool? ?? true,
      targetPower: json['targetPower'] as bool? ?? true,
      timeOfDay: json['timeOfDay'] as String? ?? '07:00',
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>? ?? const [])
          .map((value) => (value as num).toInt())
          .toList(),
      timezoneOffsetMinutes:
          (json['timezoneOffsetMinutes'] as num?)?.toInt() ??
          DateTime.now().timeZoneOffset.inMinutes,
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName'] as String? ?? 'Device',
      deviceCode: json['deviceCode'] as String? ?? '',
      deviceLocation: json['deviceLocation'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      lastTriggeredAt: DateTime.tryParse(json['lastTriggeredAt'] as String? ?? ''),
    );
  }

  final int id;
  final String name;
  final bool enabled;
  final bool targetPower;
  final String timeOfDay;
  final List<int> daysOfWeek;
  final int timezoneOffsetMinutes;
  final int deviceId;
  final String deviceName;
  final String deviceCode;
  final String deviceLocation;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastTriggeredAt;

  String get actionLabel => targetPower ? 'Turn On' : 'Turn Off';

  String get roomLabel =>
      deviceLocation.trim().isEmpty ? 'Unassigned' : deviceLocation.trim();

  String get daysLabel {
    final normalized = [...daysOfWeek]..sort();
    if (normalized.length == 7) {
      return 'Every day';
    }
    if (_sameDays(normalized, const [1, 2, 3, 4, 5])) {
      return 'Weekdays';
    }
    if (_sameDays(normalized, const [6, 7])) {
      return 'Weekend';
    }
    return normalized.map(weekdayLabel).join(', ');
  }

  AutomationSchedule copyWith({
    String? name,
    bool? enabled,
    bool? targetPower,
    String? timeOfDay,
    List<int>? daysOfWeek,
    int? timezoneOffsetMinutes,
    int? deviceId,
    String? deviceName,
    String? deviceCode,
    String? deviceLocation,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastTriggeredAt,
  }) {
    return AutomationSchedule(
      id: id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      targetPower: targetPower ?? this.targetPower,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      timezoneOffsetMinutes:
          timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceCode: deviceCode ?? this.deviceCode,
      deviceLocation: deviceLocation ?? this.deviceLocation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
    );
  }

  AutomationScheduleRequest toRequest() {
    return AutomationScheduleRequest(
      name: name,
      deviceId: deviceId,
      enabled: enabled,
      targetPower: targetPower,
      timeOfDay: timeOfDay,
      daysOfWeek: daysOfWeek,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
  }

  static String weekdayLabel(int day) {
    return switch (day) {
      1 => 'Mon',
      2 => 'Tue',
      3 => 'Wed',
      4 => 'Thu',
      5 => 'Fri',
      6 => 'Sat',
      7 => 'Sun',
      _ => 'Day',
    };
  }

  static bool _sameDays(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

class AutomationScheduleRequest {
  const AutomationScheduleRequest({
    required this.name,
    required this.deviceId,
    required this.enabled,
    required this.targetPower,
    required this.timeOfDay,
    required this.daysOfWeek,
    required this.timezoneOffsetMinutes,
  });

  final String name;
  final int deviceId;
  final bool enabled;
  final bool targetPower;
  final String timeOfDay;
  final List<int> daysOfWeek;
  final int timezoneOffsetMinutes;

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'deviceId': deviceId,
      'enabled': enabled,
      'targetPower': targetPower,
      'timeOfDay': timeOfDay,
      'daysOfWeek': daysOfWeek,
      'timezoneOffsetMinutes': timezoneOffsetMinutes,
    };
  }

  AutomationScheduleRequest copyWith({
    String? name,
    int? deviceId,
    bool? enabled,
    bool? targetPower,
    String? timeOfDay,
    List<int>? daysOfWeek,
    int? timezoneOffsetMinutes,
  }) {
    return AutomationScheduleRequest(
      name: name ?? this.name,
      deviceId: deviceId ?? this.deviceId,
      enabled: enabled ?? this.enabled,
      targetPower: targetPower ?? this.targetPower,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      timezoneOffsetMinutes:
          timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
    );
  }
}

TimeOfDay parseAutomationTime(String timeOfDay) {
  final parts = timeOfDay.split(':');
  if (parts.length != 2) {
    return const TimeOfDay(hour: 7, minute: 0);
  }
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 7,
    minute: int.tryParse(parts[1]) ?? 0,
  );
}

String formatAutomationTime(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

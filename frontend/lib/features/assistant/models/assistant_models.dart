class AssistantAction {
  const AssistantAction({
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
    required this.roomLabel,
    required this.targetPower,
    required this.success,
    required this.status,
    required this.message,
  });

  factory AssistantAction.fromJson(Map<String, dynamic> json) {
    return AssistantAction(
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      deviceCode: json['deviceCode'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Device',
      roomLabel: json['roomLabel'] as String? ?? 'Unassigned',
      targetPower: json['targetPower'] as bool?,
      success: json['success'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  final int deviceId;
  final String deviceCode;
  final String deviceName;
  final String roomLabel;
  final bool? targetPower;
  final bool success;
  final String status;
  final String message;
}

class AssistantWeatherContext {
  const AssistantWeatherContext({
    required this.temperatureC,
    required this.condition,
    required this.iconKey,
  });

  factory AssistantWeatherContext.fromJson(Map<String, dynamic> json) {
    return AssistantWeatherContext(
      temperatureC: (json['temperatureC'] as num?)?.toDouble() ?? 0,
      condition: json['condition'] as String? ?? 'Weather unavailable',
      iconKey: json['iconKey'] as String? ?? 'unknown',
    );
  }

  final double temperatureC;
  final String condition;
  final String iconKey;
}

class AssistantReply {
  const AssistantReply({
    required this.reply,
    required this.mode,
    required this.actions,
    required this.weather,
  });

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    return AssistantReply(
      reply: json['reply'] as String? ?? '',
      mode: json['mode'] as String? ?? 'chat',
      actions: (json['actions'] as List<dynamic>? ?? const [])
          .map(
            (item) => AssistantAction.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      weather: json['weather'] is Map
          ? AssistantWeatherContext.fromJson(
              Map<String, dynamic>.from(json['weather'] as Map),
            )
          : null,
    );
  }

  final String reply;
  final String mode;
  final List<AssistantAction> actions;
  final AssistantWeatherContext? weather;
}

enum AssistantMessageRole { assistant, user }

class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.actions = const [],
    this.weather,
    this.transient = false,
  });

  final String id;
  final AssistantMessageRole role;
  final String text;
  final DateTime createdAt;
  final List<AssistantAction> actions;
  final AssistantWeatherContext? weather;
  final bool transient;

  AssistantMessage copyWith({
    String? text,
    DateTime? createdAt,
    List<AssistantAction>? actions,
    AssistantWeatherContext? weather,
    bool? transient,
  }) {
    return AssistantMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      actions: actions ?? this.actions,
      weather: weather ?? this.weather,
      transient: transient ?? this.transient,
    );
  }
}

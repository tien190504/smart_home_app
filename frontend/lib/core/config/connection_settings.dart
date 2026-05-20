class ConnectionSettings {
  static const int defaultRestPort = 8080;
  static const int defaultMqttPort = 1883;

  const ConnectionSettings({
    required this.restBaseUrl,
    required this.mqttTcpHost,
    required this.mqttTcpPort,
  });

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) {
    return ConnectionSettings.fromUserInput(
      restBaseUrl: json['restBaseUrl'] as String? ?? '',
      mqttTcpHost: json['mqttTcpHost'] as String? ?? '',
      mqttTcpPort: (json['mqttTcpPort'] as num?)?.toInt() ?? defaultMqttPort,
    );
  }

  factory ConnectionSettings.fromUserInput({
    required String restBaseUrl,
    required String mqttTcpHost,
    required int mqttTcpPort,
  }) {
    return ConnectionSettings(
      restBaseUrl: _normalizeRestBaseUrl(restBaseUrl),
      mqttTcpHost: _normalizeHost(mqttTcpHost),
      mqttTcpPort: mqttTcpPort > 0 ? mqttTcpPort : defaultMqttPort,
    );
  }

  final String restBaseUrl;
  final String mqttTcpHost;
  final int mqttTcpPort;

  bool get isComplete => restBaseUrl.isNotEmpty && mqttTcpHost.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'restBaseUrl': restBaseUrl,
      'mqttTcpHost': mqttTcpHost,
      'mqttTcpPort': mqttTcpPort,
    };
  }

  static String normalizeRestBaseUrl(String value) {
    return _normalizeRestBaseUrl(value);
  }

  static String normalizeMqttHost(String value) {
    return _normalizeHost(value);
  }

  static String _normalizeRestBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final raw = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.trim().isEmpty) {
      return trimmed;
    }

    final host = uri.host.trim();
    final likelyLanHost = _isLikelyLanHost(host);
    final scheme = likelyLanHost && uri.scheme.toLowerCase() == 'https'
        ? 'http'
        : (uri.scheme.isEmpty ? 'http' : uri.scheme.toLowerCase());
    final hasExplicitPort = uri.hasPort;
    final port = hasExplicitPort
        ? uri.port
        : (likelyLanHost ? defaultRestPort : 0);

    return Uri(
      scheme: scheme,
      host: host,
      port: port > 0 ? port : null,
    ).toString();
  }

  static String _normalizeHost(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final raw = trimmed.contains('://') ? trimmed : 'tcp://$trimmed';
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.host.trim().isNotEmpty) {
      return uri.host.trim();
    }

    return trimmed
        .replaceAll(RegExp(r'^/+|/+$'), '')
        .split('/')
        .first
        .split(':')
        .first
        .trim();
  }

  static bool _isLikelyLanHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    if (normalized == 'localhost' || normalized == '127.0.0.1') {
      return true;
    }

    if (normalized.startsWith('192.168.') ||
        normalized.startsWith('10.') ||
        normalized.startsWith('172.16.') ||
        normalized.startsWith('172.17.') ||
        normalized.startsWith('172.18.') ||
        normalized.startsWith('172.19.') ||
        normalized.startsWith('172.2') ||
        normalized.startsWith('172.30.') ||
        normalized.startsWith('172.31.')) {
      return true;
    }

    return !normalized.contains('.');
  }
}

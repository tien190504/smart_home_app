import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_config.dart';
import 'connection_settings.dart';

class ConnectionDiscoveryService {
  const ConnectionDiscoveryService();

  static const String _discoveryPath = '/api/system/discovery';
  static const int _defaultRestPort = 8080;
  static const int _batchSize = 32;
  static const Duration _connectTimeout = Duration(milliseconds: 450);
  static const Duration _responseTimeout = Duration(milliseconds: 900);

  Future<ConnectionSettings?> discover({
    required AppConfig fallbackConfig,
    ConnectionSettings? preferredSettings,
  }) async {
    final candidates = <Uri>[];
    final seen = <String>{};

    void addCandidate(Uri? uri) {
      if (uri == null) {
        return;
      }

      final normalized = uri.replace(
        path: _discoveryPath,
        query: null,
        fragment: null,
      );
      if (normalized.host.trim().isEmpty) {
        return;
      }

      final key = normalized.toString();
      if (seen.add(key)) {
        candidates.add(normalized);
      }
    }

    addCandidate(_candidateFromRestBaseUrl(preferredSettings?.restBaseUrl));
    addCandidate(_candidateFromRestBaseUrl(fallbackConfig.restBaseUrl));

    final prefixes = await _privateIpv4Prefixes();
    for (final prefix in prefixes) {
      for (final host in _hostScanOrder()) {
        addCandidate(
          Uri(
            scheme: 'http',
            host: '$prefix.$host',
            port: _defaultRestPort,
            path: _discoveryPath,
          ),
        );
      }
    }

    for (var start = 0; start < candidates.length; start += _batchSize) {
      final end = start + _batchSize < candidates.length
          ? start + _batchSize
          : candidates.length;
      final batch = candidates.sublist(start, end);
      final results = await Future.wait(
        batch.map(_probeCandidate),
        eagerError: false,
      );

      for (final result in results) {
        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  Uri? _candidateFromRestBaseUrl(String? rawBaseUrl) {
    final trimmed = rawBaseUrl?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }

    final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
    final port = uri.hasPort ? uri.port : _defaultRestPort;
    return Uri(scheme: scheme, host: uri.host, port: port, path: _discoveryPath);
  }

  Future<Set<String>> _privateIpv4Prefixes() async {
    final prefixes = <String>{};
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        final rawAddress = address.address.trim();
        if (!_isPrivateIpv4(rawAddress)) {
          continue;
        }

        final lastDot = rawAddress.lastIndexOf('.');
        if (lastDot <= 0) {
          continue;
        }
        prefixes.add(rawAddress.substring(0, lastDot));
      }
    }

    return prefixes;
  }

  bool _isPrivateIpv4(String address) {
    return address.startsWith('192.168.') ||
        address.startsWith('10.') ||
        address.startsWith('172.16.') ||
        address.startsWith('172.17.') ||
        address.startsWith('172.18.') ||
        address.startsWith('172.19.') ||
        address.startsWith('172.20.') ||
        address.startsWith('172.21.') ||
        address.startsWith('172.22.') ||
        address.startsWith('172.23.') ||
        address.startsWith('172.24.') ||
        address.startsWith('172.25.') ||
        address.startsWith('172.26.') ||
        address.startsWith('172.27.') ||
        address.startsWith('172.28.') ||
        address.startsWith('172.29.') ||
        address.startsWith('172.30.') ||
        address.startsWith('172.31.');
  }

  Iterable<int> _hostScanOrder() sync* {
    for (final preferred in const [1, 2, 10, 20, 50, 86, 100, 101, 200, 254]) {
      yield preferred;
    }

    for (var host = 1; host <= 254; host++) {
      if (const {1, 2, 10, 20, 50, 86, 100, 101, 200, 254}.contains(host)) {
        continue;
      }
      yield host;
    }
  }

  Future<ConnectionSettings?> _probeCandidate(Uri discoveryUri) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;

    try {
      final request = await client.getUrl(discoveryUri).timeout(_connectTimeout);
      request.followRedirects = false;

      final response = await request.close().timeout(_responseTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return null;
      }

      final payload = Map<String, dynamic>.from(decoded);
      final service = (payload['service'] as String? ?? '').trim().toLowerCase();
      if (service != 'smartify-backend') {
        return null;
      }

      final restBaseUrl =
          (payload['restBaseUrl'] as String?)?.trim().isNotEmpty == true
          ? (payload['restBaseUrl'] as String).trim()
          : Uri(
              scheme: discoveryUri.scheme,
              host: discoveryUri.host,
              port: discoveryUri.hasPort ? discoveryUri.port : null,
            ).toString();

      final mqttTcpHost = (payload['mqttTcpHost'] as String? ?? '').trim();
      final mqttTcpPort = (payload['mqttTcpPort'] as num?)?.toInt() ??
          ConnectionSettings.defaultMqttPort;
      if (mqttTcpHost.isEmpty) {
        return null;
      }

      return ConnectionSettings.fromUserInput(
        restBaseUrl: restBaseUrl,
        mqttTcpHost: mqttTcpHost,
        mqttTcpPort: mqttTcpPort,
      );
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HandshakeException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

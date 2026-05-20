import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_discovery_service_stub.dart'
    if (dart.library.io) 'connection_discovery_service_io.dart' as impl;

typedef ConnectionDiscoveryService = impl.ConnectionDiscoveryService;

final connectionDiscoveryServiceProvider = Provider<ConnectionDiscoveryService>(
  (ref) => impl.ConnectionDiscoveryService(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/connection/presentation/connection_screens.dart';
import '../../features/auth/data/auth_models.dart';
import '../../features/auth/logic/auth_controller.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/assistant/presentation/assistant_screens.dart';
import '../../features/automation/presentation/automation_screens.dart';
import '../../features/devices/presentation/device_screens.dart';
import '../../features/provisioning/presentation/provisioning_screens.dart';
import '../config/connection_settings_controller.dart';
import '../utils/go_router_refresh_stream.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final connectionState = ref.watch(connectionSettingsControllerProvider);
  final authNotifier = ref.watch(authControllerProvider.notifier);
  final refreshListenable = GoRouterRefreshStream(authNotifier.stream);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final goingToSplash = state.matchedLocation == '/splash';
      final goingToLogin = state.matchedLocation == '/login';
      final goingToRegister = state.matchedLocation == '/register';
      final goingToConnection = state.matchedLocation == '/connection';

      if (connectionState.requiresSetup) {
        return goingToConnection ? null : '/connection';
      }

      if (authState.status == AuthStatus.unknown) {
        return goingToSplash || goingToConnection ? null : '/splash';
      }

      if (!authState.isAuthenticated) {
        return goingToLogin || goingToRegister || goingToConnection
            ? null
            : '/login';
      }

      if (goingToSplash || goingToLogin || goingToRegister) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/connection',
        builder: (context, state) => const ConnectionSetupScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const ShellScreen()),
      GoRoute(
        path: '/assistant',
        builder: (context, state) => AssistantScreen(
          autoListen: state.uri.queryParameters['listen'] == '1',
        ),
      ),
      GoRoute(
        path: '/category/:group',
        builder: (context, state) => CategoryScreen(
          groupKey: state.pathParameters['group'] ?? 'lighting',
        ),
      ),
      GoRoute(
        path: '/device/:id',
        builder: (context, state) => DeviceControlScreen(
          deviceId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/automation/new',
        builder: (context, state) => AutomationEditorScreen(
          deviceId: int.tryParse(state.uri.queryParameters['deviceId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/automation/:id/edit',
        builder: (context, state) => AutomationEditorScreen(
          scheduleId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/add-device',
        builder: (context, state) => const AddDeviceScreen(),
      ),
      GoRoute(
        path: '/scan-device',
        builder: (context, state) => const ScanDeviceScreen(),
      ),
      GoRoute(
        path: '/proof-of-possession',
        builder: (context, state) =>
            ProofOfPossessionScreen(rawPayload: state.extra),
      ),
      GoRoute(
        path: '/wifi-setup',
        builder: (context, state) => const WifiSetupScreen(),
      ),
      GoRoute(
        path: '/connecting',
        builder: (context, state) => const ConnectingDeviceScreen(),
      ),
      GoRoute(
        path: '/connected',
        builder: (context, state) => const ConnectedDeviceScreen(),
      ),
    ],
  );
});

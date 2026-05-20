import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/connection_settings_controller.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';
import '../data/auth_storage.dart';

final authStorageProvider = Provider<AuthStorage>((ref) {
  return HybridAuthStorage();
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(appConfigProvider));
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(
      api: ref.watch(authApiProvider),
      config: ref.watch(appConfigProvider),
      storage: ref.read(authStorageProvider),
    );
  },
);

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthApi api,
    required AppConfig config,
    required AuthStorage storage,
  }) : _api = api,
       _config = config,
       _storage = storage,
       super(const AuthState.unknown()) {
    unawaited(bootstrap());
  }

  final AuthApi _api;
  final AppConfig _config;
  final AuthStorage _storage;

  Completer<String?>? _refreshCompleter;

  Future<void> bootstrap() async {
    final rememberMe = await _storage.loadRememberMe();
    final session = await _storage.loadSession();

    if (session == null) {
      state = AuthState.unauthenticated(rememberMe: rememberMe);
      return;
    }

    if (session.isRefreshExpired) {
      await _storage.clear();
      state = AuthState.unauthenticated(rememberMe: rememberMe);
      return;
    }

    state = AuthState.authenticated(session, rememberMe: rememberMe);
    await ensureValidAccessToken();
  }

  Future<bool> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    state = state.copyWith(
      status: AuthStatus.submitting,
      rememberMe: rememberMe,
      clearError: true,
    );

    try {
      final response = await _api.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      await _persistAuthenticatedSession(
        response.toSession(),
        rememberMe: rememberMe,
      );
      return true;
    } on DioException catch (error) {
      state = AuthState.unauthenticated(
        rememberMe: rememberMe,
        errorMessage: _messageFromDio(error) ?? 'Sign in failed.',
      );
      return false;
    } catch (_) {
      state = AuthState.unauthenticated(
        rememberMe: rememberMe,
        errorMessage: 'Sign in failed.',
      );
      return false;
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    state = state.copyWith(
      status: AuthStatus.submitting,
      rememberMe: rememberMe,
      clearError: true,
    );

    try {
      final response = await _api.register(
        fullName: fullName.trim(),
        email: email.trim().toLowerCase(),
        password: password,
      );
      await _persistAuthenticatedSession(
        response.toSession(),
        rememberMe: rememberMe,
      );
      return true;
    } on DioException catch (error) {
      state = AuthState.unauthenticated(
        rememberMe: rememberMe,
        errorMessage: _messageFromDio(error) ?? 'Sign up failed.',
      );
      return false;
    } catch (_) {
      state = AuthState.unauthenticated(
        rememberMe: rememberMe,
        errorMessage: 'Sign up failed.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final refreshToken = state.session?.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {
        // Keep logout resilient even when the backend session was already invalid.
      }
    }

    await _storage.clear();
    state = AuthState.unauthenticated(rememberMe: state.rememberMe);
  }

  Future<void> clearSessionLocally() async {
    await _storage.clear();
    state = AuthState.unauthenticated(rememberMe: state.rememberMe);
  }

  Future<String?> ensureValidAccessToken() async {
    final session = state.session;
    if (session == null) {
      return null;
    }

    if (!session.isAccessExpired) {
      return session.accessToken;
    }

    return _refreshAccessToken();
  }

  Future<String?> forceRefreshAccessToken() => _refreshAccessToken();

  Future<void> _persistAuthenticatedSession(
    AuthSession session, {
    required bool rememberMe,
  }) async {
    if (rememberMe) {
      await _storage.saveSession(session, rememberMe: true);
    } else {
      await _storage.clear();
    }
    state = AuthState.authenticated(session, rememberMe: rememberMe);
  }

  Future<String?> _refreshAccessToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final session = state.session;
    if (session == null || session.isRefreshExpired) {
      await _storage.clear();
      state = AuthState.unauthenticated(rememberMe: state.rememberMe);
      return null;
    }

    _refreshCompleter = Completer<String?>();

    try {
      final refreshed = await _api.refresh(session.refreshToken);
      final nextSession = refreshed.toSession();
      if (state.rememberMe) {
        await _storage.saveSession(nextSession, rememberMe: true);
      }
      state = AuthState.authenticated(
        nextSession,
        rememberMe: state.rememberMe,
      );
      _refreshCompleter!.complete(nextSession.accessToken);
      return nextSession.accessToken;
    } on DioException {
      await _storage.clear();
      state = AuthState.unauthenticated(rememberMe: state.rememberMe);
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _refreshCompleter = null;
    }
  }

  String? _messageFromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }

    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return _buildConnectionErrorMessage();
    }

    final fallbackMessage = error.message?.trim();
    if (fallbackMessage != null && fallbackMessage.isNotEmpty) {
      return fallbackMessage;
    }

    return null;
  }

  String _buildConnectionErrorMessage() {
    final baseUrl = _config.restBaseUrl;
    final uri = Uri.tryParse(baseUrl);

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        baseUrl.contains('10.0.2.2')) {
      return 'Cannot reach backend at $baseUrl. '
          '10.0.2.2 only works on the Android emulator. '
          'If you are using a real phone, run the app with '
          '--dart-define=REST_BASE_URL=http://<your-computer-lan-ip>:8080 '
          'and --dart-define=MQTT_TCP_HOST=<your-computer-lan-ip>.';
    }

    final host = uri?.host.toLowerCase() ?? '';
    final likelyLanHost =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.');

    if (likelyLanHost && uri?.scheme.toLowerCase() == 'https') {
      return 'Cannot reach backend at $baseUrl. '
          'For the current LAN Docker setup, use http://${uri!.host}:8080 instead of HTTPS.';
    }

    if (likelyLanHost && uri != null && !uri.hasPort) {
      return 'Cannot reach backend at $baseUrl. '
          'For the current LAN Docker setup, include backend port 8080, for example http://${uri.host}:8080.';
    }

    return 'Cannot reach backend at $baseUrl. Please make sure the server is running and reachable from this device.';
  }
}

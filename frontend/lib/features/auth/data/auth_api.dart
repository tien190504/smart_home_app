import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import 'auth_models.dart';

class AuthApi {
  AuthApi(AppConfig config)
      : _dio = Dio(
          BaseOptions(
            baseUrl: config.restBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
            contentType: 'application/json',
          ),
        );

  final Dio _dio;

  Future<AuthResponseModel> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'fullName': fullName,
        'email': email,
        'password': password,
      },
    );
    return AuthResponseModel.fromJson(response.data ?? const {});
  }

  Future<AuthResponseModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );
    return AuthResponseModel.fromJson(response.data ?? const {});
  }

  Future<AuthResponseModel> refresh(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {
        'refreshToken': refreshToken,
      },
    );
    return AuthResponseModel.fromJson(response.data ?? const {});
  }

  Future<void> logout(String refreshToken) async {
    await _dio.post<void>(
      '/api/auth/logout',
      data: {
        'refreshToken': refreshToken,
      },
    );
  }
}

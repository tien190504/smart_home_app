import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/logic/auth_controller.dart';
import '../config/app_config.dart';

class ApiClient {
  ApiClient(this._ref, AppConfig config)
      : _dio = Dio(
          BaseOptions(
            baseUrl: config.restBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 16),
            contentType: 'application/json',
          ),
        );

  final Ref _ref;
  final Dio _dio;

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await _authorizedRequest<Map<String, dynamic>>(
      (options) => _dio.get<Map<String, dynamic>>(path, options: options),
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<List<dynamic>> getList(String path) async {
    final response = await _authorizedRequest<List<dynamic>>(
      (options) => _dio.get<List<dynamic>>(path, options: options),
    );
    return List<dynamic>.from(response.data ?? const []);
  }

  Future<Map<String, dynamic>> postMap(
    String path, {
    Object? data,
  }) async {
    final response = await _authorizedRequest<Map<String, dynamic>>(
      (options) => _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: options,
      ),
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> putMap(
    String path, {
    Object? data,
  }) async {
    final response = await _authorizedRequest<Map<String, dynamic>>(
      (options) => _dio.put<Map<String, dynamic>>(
        path,
        data: data,
        options: options,
      ),
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<void> delete(String path) async {
    await _authorizedRequest<void>(
      (options) => _dio.delete<void>(path, options: options),
    );
  }

  Future<Response<T>> _authorizedRequest<T>(
    Future<Response<T>> Function(Options options) request,
  ) async {
    final authController = _ref.read(authControllerProvider.notifier);
    String? accessToken = await authController.ensureValidAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        error: 'Missing access token',
      );
    }

    try {
      return await request(
        Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        rethrow;
      }

      accessToken = await authController.forceRefreshAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        rethrow;
      }

      return request(
        Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );
    }
  }
}

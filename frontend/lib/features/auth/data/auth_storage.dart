import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';

abstract class AuthStorage {
  Future<AuthSession?> loadSession();

  Future<void> saveSession(AuthSession session, {required bool rememberMe});

  Future<bool> loadRememberMe();

  Future<void> clear();
}

class HybridAuthStorage implements AuthStorage {
  static const String _sessionKey = 'smartify.auth.session';
  static const String _rememberMeKey = 'smartify.auth.remember_me';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  Future<AuthSession?> loadSession() async {
    final raw = kIsWeb
        ? (await SharedPreferences.getInstance()).getString(_sessionKey)
        : await _secureStorage.read(key: _sessionKey);

    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      return AuthSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> saveSession(
    AuthSession session, {
    required bool rememberMe,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, rememberMe);
      if (rememberMe) {
        await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
      } else {
        await prefs.remove(_sessionKey);
      }
      return;
    }

    await _secureStorage.write(
      key: _rememberMeKey,
      value: rememberMe.toString(),
    );
    if (rememberMe) {
      await _secureStorage.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
    } else {
      await _secureStorage.delete(key: _sessionKey);
    }
  }

  @override
  Future<bool> loadRememberMe() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_rememberMeKey) ?? true;
    }

    final raw = await _secureStorage.read(key: _rememberMeKey);
    return raw == null ? true : raw.toLowerCase() == 'true';
  }

  @override
  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      return;
    }

    await _secureStorage.delete(key: _sessionKey);
  }
}

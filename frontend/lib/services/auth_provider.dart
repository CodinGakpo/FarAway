import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_service.dart';

// ignore_for_file: avoid_print

class AuthProvider extends ChangeNotifier {
  AuthProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  User? currentUser;

  bool get isLoggedIn => currentUser != null;

  bool get isDriver => currentUser?.role == 'driver';

  Future<void> login(String email, String password) async {
    final user = await _apiService.login(email, password);
    await _apiService.saveToken(user.token);
    currentUser = user;
    notifyListeners();
  }

  Future<void> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    final user = await _apiService.register(name, email, password, role);
    await _apiService.saveToken(user.token);
    currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    await _apiService.clearToken();
    currentUser = null;
    notifyListeners();
  }

  Future<void> tryAutoLogin() async {
    debugPrint('[AuthProvider] tryAutoLogin — reading stored token');
    final String? token;
    try {
      token = await _apiService.getToken();
    } catch (e) {
      debugPrint('[AuthProvider] tryAutoLogin — secure storage read failed: $e');
      return;
    }

    if (token == null || token.isEmpty) {
      debugPrint('[AuthProvider] tryAutoLogin — no token found');
      return;
    }

    final role = _extractRoleFromToken(token);
    debugPrint('[AuthProvider] tryAutoLogin — token present, role=$role');
    currentUser = User(
      id: '',
      email: '',
      role: role,
      name: '',
      token: token,
    );
    notifyListeners();
  }

  String _extractRoleFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return 'customer';
      }

      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);

      if (decoded is Map<String, dynamic>) {
        final role = decoded['role'];
        if (role is String && (role == 'driver' || role == 'customer')) {
          return role;
        }
      }
    } catch (_) {
      // Falls back to customer when token cannot be decoded.
    }

    return 'customer';
  }
}

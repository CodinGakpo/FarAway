import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    ApiService? apiService,
  })  : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  User? currentUser;

  bool get isLoggedIn => currentUser != null;

  bool get isDriver => currentUser?.role == 'driver';

  // ── Login / register / logout ──────────────────────────────────────────────

  Future<void> login(String email, String password) async {
    try {
      final user = await _apiService.login(email, password);
      await _apiService.saveToken(user.token);
      currentUser = user;
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    try {
      final user = await _apiService.register(name, email, password, role);
      await _apiService.saveToken(user.token);
      currentUser = user;
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> logout() async {
    await _apiService.clearToken();
    currentUser = null;
    notifyListeners();
  }

  // ── Session restoration on app start ──────────────────────────────────────

  /// Called once on app launch by [_AuthGate].
  Future<void> tryAutoLogin() async {
    debugPrint('[AuthProvider] tryAutoLogin — checking local token');
    final token = await _apiService.getToken();
    
    if (token == null || token.isEmpty) {
      debugPrint('[AuthProvider] tryAutoLogin — no token found');
      currentUser = null;
      notifyListeners();
      return;
    }

    debugPrint('[AuthProvider] tryAutoLogin — token found, verifying...');
    try {
      final user = await _apiService.getMe(token);
      currentUser = user;
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] tryAutoLogin — failed to restore session: $e');
      await _apiService.clearToken();
      currentUser = null;
      notifyListeners();
    }
  }
}

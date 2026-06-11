import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  User? currentUser;

  bool get isLoggedIn => currentUser != null;

  bool get isDriver => currentUser?.role == 'driver';

  // ── Login / register / logout ──────────────────────────────────────────────

  Future<void> login(String email, String password) async {
    final user = await _apiService.login(email, password);
    await _apiService.saveToken(user.token);
    currentUser = await _fetchFullProfile(user);
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
    currentUser = await _fetchFullProfile(user);
    notifyListeners();
  }

  Future<void> logout() async {
    await _apiService.clearToken();
    currentUser = null;
    notifyListeners();
  }

  // ── Session restoration on app start ──────────────────────────────────────

  /// Called once on app launch by [_AuthGate].
  ///
  /// Strategy:
  /// 1. Read stored token from secure storage.
  /// 2. Validate it by calling GET /auth/me.
  /// 3. On 401 the token is stale: clear it and stay logged out.
  /// 4. On network error, fall back to local JWT decoding so the app stays
  ///    usable offline; the profile will be incomplete until reconnected.
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
      debugPrint('[AuthProvider] tryAutoLogin — no stored token');
      return;
    }

    debugPrint('[AuthProvider] tryAutoLogin — token found, calling /auth/me');
    try {
      currentUser = await _apiService.getMe(token);
      debugPrint(
        '[AuthProvider] tryAutoLogin — restored: '
        'id=${currentUser!.id}, role=${currentUser!.role}',
      );
      notifyListeners();
    } on UnauthorizedException {
      // Token is expired or revoked — force re-login.
      debugPrint('[AuthProvider] tryAutoLogin — 401, clearing stored token');
      await _apiService.clearToken();
    } catch (e) {
      // Network error or server unreachable — restore a minimal session from
      // the token's own claims so the user can still see the UI offline.
      debugPrint('[AuthProvider] tryAutoLogin — /auth/me failed ($e), falling back to JWT decode');
      final role = _roleFromToken(token);
      if (role != null) {
        currentUser = User(id: '', email: '', role: role, name: '', token: token);
        notifyListeners();
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Enriches [partialUser] with the full profile from GET /auth/me.
  /// Returns [partialUser] unchanged if the call fails (e.g. brief outage).
  Future<User> _fetchFullProfile(User partialUser) async {
    try {
      return await _apiService.getMe(partialUser.token);
    } catch (_) {
      return partialUser;
    }
  }

  /// Decodes the JWT payload and extracts the `role` claim.
  ///
  /// Returns `null` if the token is malformed or carries an unknown role.
  /// Valid backend roles are `'driver'` and `'shipper'`.
  String? _roleFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // base64Url.normalize handles missing padding characters.
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);

      if (decoded is Map<String, dynamic>) {
        final role = decoded['role'];
        if (role == 'driver' || role == 'shipper') return role as String;
      }
    } catch (_) {
      // Malformed token — return null.
    }
    return null;
  }
}

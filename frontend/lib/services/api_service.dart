import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/shipment_request.dart';
import '../models/trip.dart';
import '../models/user.dart';

// Thrown when the server returns 401 Unauthorized (token expired / invalid).
class UnauthorizedException implements Exception {
  @override
  String toString() => 'Session expired. Please log in again.';
}

class ApiService {
  ApiService._internal();

  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;

  final http.Client _client = http.Client();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _tokenKey = 'jwt_token';

  String get _baseUrl => AppConstants.BASE_URL;

  // ── Token storage ──────────────────────────────────────────────────────────

  Future<String?> getToken() {
    return _secureStorage.read(key: _tokenKey);
  }

  Future<void> saveToken(String token) {
    return _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() {
    return _secureStorage.delete(key: _tokenKey);
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  /// Signs in an existing user.
  ///
  /// The backend (LOCAL_DEV_MODE) does not verify passwords; the user is
  /// identified by a deterministic ID derived from their email.  If the
  /// user already exists in the database the server returns their stored
  /// role, so the [password] parameter is accepted here for UI compatibility
  /// but is not forwarded to the server.
  Future<User> login(String email, String password) async {
    final userId = _deriveUserId(email);
    final name = _deriveName(email);

    final response = await _post(
      AppConstants.AUTH_LOGIN,
      {
        'id': userId,
        'email': email,
        // Default role sent on login — the backend returns the user's actual
        // stored role when the account already exists, so this only matters
        // for brand-new accounts (which should go through register instead).
        'role': 'shipper',
        'name': name,
      },
    );

    return _handleResponse(response, (body) {
      _assertMap(body, 'login');
      final user = User.fromLoginResponse(
        body as Map<String, dynamic>,
        email: email,
        name: name,
      );
      if (user.token.isEmpty) throw Exception('No access token in response');
      return user;
    });
  }

  /// Registers a new user.
  ///
  /// The backend's /auth/login endpoint creates the account when the ID does
  /// not yet exist, so registration and login share the same endpoint.
  Future<User> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    final userId = _deriveUserId(email);
    // Normalise role: the register screen may emit 'customer' (UI label) but
    // the backend only understands 'driver' and 'shipper'.
    final backendRole = (role == 'customer') ? 'shipper' : role;

    final response = await _post(
      AppConstants.AUTH_LOGIN,
      {
        'id': userId,
        'email': email,
        'role': backendRole,
        'name': name,
      },
    );

    return _handleResponse(response, (body) {
      _assertMap(body, 'register');
      final user = User.fromLoginResponse(
        body as Map<String, dynamic>,
        email: email,
        name: name,
      );
      if (user.token.isEmpty) throw Exception('No access token in response');
      return user;
    });
  }

  /// Fetches the authenticated user's full profile from GET /auth/me.
  ///
  /// Uses [token] directly so this can be called before the token is
  /// stored (e.g. to validate it on app startup).
  Future<User> getMe(String token) async {
    final response = await _client.get(
      _buildUri(AppConstants.AUTH_ME),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return _handleResponse(response, (body) {
      _assertMap(body, '/auth/me');
      return User.fromMeResponse(
        body as Map<String, dynamic>,
        token: token,
      );
    });
  }

  // ── Trips ──────────────────────────────────────────────────────────────────

  Future<Trip> createTrip(
    String origin,
    String destination,
    DateTime date,
    double maxWeight,
    double maxVolume,
  ) async {
    final response = await _post(
      AppConstants.TRIPS,
      {
        'origin': origin,
        'destination': destination,
        'date': date.toIso8601String(),
        'maxWeight': maxWeight,
        'maxVolume': maxVolume,
      },
    );

    return _handleResponse(response, (body) {
      final data = _extractMap(body, ['trip', 'data'], entityName: 'trip');
      return Trip.fromJson(data);
    });
  }

  Future<Trip?> getActiveTrip() async {
    final response = await _client.get(
      _buildUri('${AppConstants.TRIPS}/active'),
      headers: await _headers(),
    );

    if (response.statusCode == 204 || response.statusCode == 404) {
      return null;
    }

    return _handleResponse(response, (body) {
      if (body == null) return null;

      if (body is Map<String, dynamic>) {
        final trip = body['trip'];
        if (trip is Map<String, dynamic>) return Trip.fromJson(trip);

        final activeTrip = body['activeTrip'];
        if (activeTrip is Map<String, dynamic>) return Trip.fromJson(activeTrip);

        if (body.isNotEmpty) return Trip.fromJson(body);
      }

      return null;
    });
  }

  Future<List<ShipmentRequest>> getIncomingRequests(String tripId) async {
    final response = await _get('${AppConstants.TRIPS}/$tripId/requests');

    return _handleResponse(response, (body) {
      final list = _extractList(body, ['requests', 'data', 'items']);
      return list
          .map((item) => ShipmentRequest.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
    });
  }

  Future<List<ShipmentRequest>> getTripShipments(String tripId) async {
    final response = await _get('${AppConstants.TRIPS}/$tripId/shipments');

    return _handleResponse(response, (body) {
      final list = _extractList(body, ['shipments', 'data', 'items']);
      return list
          .map((item) => ShipmentRequest.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
    });
  }

  Future<void> acceptRequest(String shipmentId) async {
    final response = await _post(
      '${AppConstants.BOOKINGS}/$shipmentId/accept',
      {},
    );
    _handleResponse(response, (_) => null);
  }

  Future<void> rejectRequest(String shipmentId) async {
    final response = await _post(
      '${AppConstants.BOOKINGS}/$shipmentId/reject',
      {},
    );
    _handleResponse(response, (_) => null);
  }

  Future<void> updateShipmentStatus(String shipmentId, String status) async {
    final response = await _patch(
      '${AppConstants.SHIPMENTS}/$shipmentId/status',
      {'status': status},
    );
    _handleResponse(response, (_) => null);
  }

  Future<ShipmentRequest> createShipment(
    String pickupLocation,
    String dropoffLocation,
    double weight,
    double volume,
    String cargoCategory,
  ) async {
    final response = await _post(
      AppConstants.SHIPMENTS,
      {
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'weight': weight,
        'volume': volume,
        'cargoCategory': cargoCategory,
      },
    );

    return _handleResponse(response, (body) {
      final data =
          _extractMap(body, ['shipment', 'data'], entityName: 'shipment');
      return ShipmentRequest.fromJson(data);
    });
  }

  Future<ShipmentRequest> confirmBooking(String shipmentId) async {
    final response = await _post(
      '${AppConstants.BOOKINGS}/$shipmentId/confirm',
      {},
    );

    return _handleResponse(response, (body) {
      final data = _extractMap(
        body,
        ['shipment', 'booking', 'data'],
        entityName: 'booking',
      );
      return ShipmentRequest.fromJson(data);
    });
  }

  Future<ShipmentRequest> getShipmentStatus(String shipmentId) async {
    final response = await _get('${AppConstants.SHIPMENTS}/$shipmentId');

    return _handleResponse(response, (body) {
      final data =
          _extractMap(body, ['shipment', 'data'], entityName: 'shipment');
      return ShipmentRequest.fromJson(data);
    });
  }

  // ── HTTP helpers ───────────────────────────────────────────────────────────

  Future<http.Response> _get(String path) async {
    return _client.get(
      _buildUri(path),
      headers: await _headers(),
    );
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    return _client.post(
      _buildUri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _patch(String path, Map<String, dynamic> body) async {
    return _client.patch(
      _buildUri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      return AppConstants.headers(token);
    }
    return {'Content-Type': 'application/json'};
  }

  Uri _buildUri(String path) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final segment = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$segment');
  }

  // ── Response handling ──────────────────────────────────────────────────────

  T _handleResponse<T>(
      http.Response response, T Function(dynamic body) parser) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = _decodeBody(response.body);
      return parser(decoded);
    }

    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }

    throw _buildHttpException(response);
  }

  dynamic _decodeBody(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  Exception _buildHttpException(http.Response response) {
    final decoded = _decodeBody(response.body);
    final message = _extractErrorMessage(decoded) ??
        'Request failed with status ${response.statusCode}: '
            '${response.reasonPhrase ?? 'Unknown error'}';
    return Exception(message);
  }

  String? _extractErrorMessage(dynamic decoded) {
    if (decoded is String && decoded.trim().isNotEmpty) {
      return decoded.trim();
    }
    if (decoded is Map<String, dynamic>) {
      for (final key in ['message', 'error', 'detail', 'errors']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is List && value.isNotEmpty) return value.join(', ');
      }
    }
    return null;
  }

  // ── Data extraction helpers ────────────────────────────────────────────────

  void _assertMap(dynamic body, String context) {
    if (body is! Map<String, dynamic>) {
      throw Exception('Unexpected $context response format');
    }
  }

  Map<String, dynamic> _extractMap(
    dynamic body,
    List<String> nestedKeys, {
    required String entityName,
  }) {
    if (body is Map<String, dynamic>) {
      for (final key in nestedKeys) {
        final nested = body[key];
        if (nested is Map<String, dynamic>) return nested;
      }
      return body;
    }
    throw Exception('Unexpected $entityName response format');
  }

  List<dynamic> _extractList(dynamic body, List<String> nestedKeys) {
    if (body is List) return body;
    if (body is Map<String, dynamic>) {
      for (final key in nestedKeys) {
        final nested = body[key];
        if (nested is List) return nested;
      }
    }
    return const [];
  }

  // ── ID / name derivation ───────────────────────────────────────────────────

  /// Creates a stable, backend-compatible user ID from an email address.
  ///
  /// Example: `arjun.driver@mail.com` → `arjun_driver_mail_com`
  static String _deriveUserId(String email) {
    return email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  /// Derives a display name from the local part of an email address.
  ///
  /// Example: `arjun.driver@mail.com` → `Arjun Driver`
  static String _deriveName(String email) {
    final local = email.split('@').first;
    return local
        .split(RegExp(r'[._\-+]'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }
}

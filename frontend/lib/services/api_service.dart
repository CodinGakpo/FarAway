import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/shipment_request.dart';
import '../models/trip.dart';
import '../models/user.dart';
import '../models/agent_models.dart';

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
    try {
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
    } catch (e) {
      throw _handleNetworkError(e);
    }
  }

  /// Syncs the authenticated user's profile info (name, email, role) with the backend.
  Future<User> syncUser({
    required String name,
    required String email,
    required String role,
  }) async {
    final backendRole = (role == 'customer') ? 'shipper' : role;
    final token = await getToken() ?? '';

    final response = await _post(
      AppConstants.AUTH_SYNC,
      {
        'name': name,
        'email': email,
        'role': backendRole,
      },
    );

    return _handleResponse(response, (body) {
      _assertMap(body, 'syncUser');
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
        'origin_name': origin,
        'destination_name': destination,
        'departure_time': date.toIso8601String(),
        'max_weight_capacity': maxWeight,
        'max_volume_capacity': maxVolume,
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

  Future<List<Trip>> getTripHistory() async {
    final response = await _get('${AppConstants.TRIPS}/history');

    return _handleResponse(response, (body) {
      if (body is List) {
        return body
            .map((item) => Trip.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      if (body is Map<String, dynamic>) {
        final list = _extractList(body, ['trips', 'history', 'data']);
        return list
            .map((item) => Trip.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return const [];
    });
  }

  Future<void> acceptRequest(String shipmentId) async {
    final response = await _patch(
      '${AppConstants.SHIPMENTS}/$shipmentId/status',
      {'status': 'ACCEPTED'},
    );
    _handleResponse(response, (_) => null);
  }

  Future<void> rejectRequest(String shipmentId) async {
    final response = await _patch(
      '${AppConstants.SHIPMENTS}/$shipmentId/status',
      {'status': 'REJECTED'},
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
    String tripId,
    String pickupLocation,
    String dropoffLocation,
    double weight,
    double volume,
    String cargoCategory,
  ) async {
    final response = await _post(
      AppConstants.SHIPMENTS,
      {
        'tripId': int.parse(tripId),
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'weight': weight,
        'volume': volume > 0 ? volume : 0.001,
        'cargoCategory': cargoCategory,
      },
    );

    return _handleResponse(response, (body) {
      if (body is Map<String, dynamic>) return ShipmentRequest.fromJson(body);
      final data =
          _extractMap(body, ['shipment', 'data'], entityName: 'shipment');
      return ShipmentRequest.fromJson(data);
    });
  }

  /// Confirms a DRAFT shipment → moves it to PENDING status.
  /// Calls POST /shipments/{id}/confirm.
  Future<ShipmentRequest> confirmShipment(String shipmentId) async {
    final response = await _post(
      '${AppConstants.SHIPMENTS}/$shipmentId/confirm',
      {},
    );

    return _handleResponse(response, (body) {
      if (body is Map<String, dynamic>) return ShipmentRequest.fromJson(body);
      final data = _extractMap(
        body,
        ['shipment', 'data'],
        entityName: 'shipment',
      );
      return ShipmentRequest.fromJson(data);
    });
  }

  /// Returns all ACTIVE trips — used by shippers to browse available freight routes.
  Future<List<Trip>> getActiveTrips() async {
    final response = await _get('${AppConstants.TRIPS}?status=ACTIVE');

    return _handleResponse(response, (body) {
      if (body is List) {
        return body
            .map((item) =>
                Trip.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      final list = _extractList(body, ['trips', 'data']);
      return list
          .map((item) =>
              Trip.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
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

  // ── Agent Tools ────────────────────────────────────────────────────────────

  Future<FindTripsResponse> findCandidateTrips(
    GeoPoint pickup,
    GeoPoint dropoff,
    double weightKg,
    double volumeM3, {
    double searchRadiusKm = 50.0,
  }) async {
    final response = await _post(
      '/agent/tools/find-trips',
      {
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'weight_kg': weightKg,
        'volume_m3': volumeM3,
        'search_radius_km': searchRadiusKm,
      },
    );
    return _handleResponse(response, (body) {
      return FindTripsResponse.fromJson(body as Map<String, dynamic>);
    });
  }

  Future<AnalyzeRouteResponse> analyzeRoute(
    String tripId,
    GeoPoint pickup,
    GeoPoint dropoff,
  ) async {
    final response = await _post(
      '/agent/tools/analyze-route',
      {
        'trip_id': tripId,
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
      },
    );
    return _handleResponse(response, (body) {
      return AnalyzeRouteResponse.fromJson(body as Map<String, dynamic>);
    });
  }

  Future<CheckCapacityResponse> checkCapacity(
    String tripId,
    double weightKg,
    double volumeM3,
  ) async {
    final response = await _post(
      '/agent/tools/check-capacity',
      {
        'trip_id': tripId,
        'weight_kg': weightKg,
        'volume_m3': volumeM3,
      },
    );
    return _handleResponse(response, (body) {
      return CheckCapacityResponse.fromJson(body as Map<String, dynamic>);
    });
  }

  Future<AgentEvaluationResponse> evaluateShipment(
    String tripId,
    String pickupLocation,
    String dropoffLocation,
    double weightKg,
    double volumeM3,
    String cargoCategory,
  ) async {
    final response = await _post(
      '/agent/evaluate',
      {
        'trip_id': int.parse(tripId),
        'pickup_location': pickupLocation,
        'dropoff_location': dropoffLocation,
        'weight': weightKg,
        'volume': volumeM3,
        'cargo_category': cargoCategory,
      },
    );
    return _handleResponse(response, (body) {
      return AgentEvaluationResponse.fromJson(body as Map<String, dynamic>);
    });
  }

  Future<CalculatePriceResponse> calculatePrice(
    String tripId,
    double shipmentDistanceKm,
    double weightKg,
    double volumeM3,
    double detourDistanceKm,
    double utilizationPct, {
    String goodsType = 'general',
  }) async {
    final response = await _post(
      '/agent/tools/calculate-price',
      {
        'trip_id': tripId,
        'shipment_distance_km': shipmentDistanceKm,
        'weight_kg': weightKg,
        'volume_m3': volumeM3,
        'goods_type': goodsType,
        'detour_distance_km': detourDistanceKm,
        'utilization_pct': utilizationPct,
      },
    );
    return _handleResponse(response, (body) {
      return CalculatePriceResponse.fromJson(body as Map<String, dynamic>);
    });
  }

  Future<HoldCapacityResponse> holdCapacity(
    String tripId,
    String shipmentId,
    double weightKg,
    double volumeM3,
    double priceAmount,
    Map<String, dynamic> priceBreakdown,
    double detourDistanceKm,
    double detourDurationMin,
  ) async {
    final response = await _post(
      '/agent/tools/hold-capacity',
      {
        'trip_id': tripId,
        'shipment_id': shipmentId,
        'weight_kg': weightKg,
        'volume_m3': volumeM3,
        'price_amount': priceAmount,
        'price_breakdown': priceBreakdown,
        'detour_distance_km': detourDistanceKm,
        'detour_duration_min': detourDurationMin,
      },
    );
    return _handleResponse(response, (body) {
      return HoldCapacityResponse.fromJson(body as Map<String, dynamic>);
    });
  }

  Future<bool> confirmBookingAgent(String bookingId) async {
    final response = await _post(
      '/agent/tools/confirm-booking',
      {
        'booking_id': bookingId,
      },
    );
    return _handleResponse(response, (body) {
      return (body as Map<String, dynamic>)['success'] == true;
    });
  }

  // ── HTTP helpers ───────────────────────────────────────────────────────────

  Future<http.Response> _get(String path) async {
    try {
      return await _client.get(
        _buildUri(path),
        headers: await _headers(),
      );
    } catch (e) {
      throw _handleNetworkError(e);
    }
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await _client.post(
        _buildUri(path),
        headers: await _headers(),
        body: jsonEncode(body),
      );
    } catch (e) {
      throw _handleNetworkError(e);
    }
  }

  Future<http.Response> _patch(String path, Map<String, dynamic> body) async {
    try {
      return await _client.patch(
        _buildUri(path),
        headers: await _headers(),
        body: jsonEncode(body),
      );
    } catch (e) {
      throw _handleNetworkError(e);
    }
  }

  Exception _handleNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('connection closed before full header')) {
      return Exception(
        'Unable to connect to the backend server. Please verify:\n'
        '1. The backend server is running.\n'
        '2. The BASE_URL in your .env file is configured correctly.\n'
        '   (Note: Use http://10.0.2.2:8000 for Android Emulator instead of localhost).'
      );
    }
    return Exception('Connection error: $error');
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

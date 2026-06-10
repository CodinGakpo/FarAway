import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/shipment_request.dart';
import '../models/trip.dart';
import '../models/user.dart';

class ApiService {
  ApiService._internal();

  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;

  final http.Client _client = http.Client();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _tokenKey = 'jwt_token';

  String get _baseUrl => AppConstants.BASE_URL;

  Future<String?> getToken() {
    return _secureStorage.read(key: _tokenKey);
  }

  Future<void> saveToken(String token) {
    return _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() {
    return _secureStorage.delete(key: _tokenKey);
  }

  Future<User> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    final response = await _post(
      AppConstants.AUTH_REGISTER,
      {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      },
    );

    final user = _handleResponse(response, _parseUser);
    await saveToken(user.token);
    return user;
  }

  Future<User> login(String email, String password) async {
    final response = await _post(
      AppConstants.AUTH_LOGIN,
      {
        'email': email,
        'password': password,
      },
    );

    final user = _handleResponse(response, _parseUser);
    await saveToken(user.token);
    return user;
  }

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
      if (body == null) {
        return null;
      }

      if (body is Map<String, dynamic>) {
        final data = body['trip'];
        if (data is Map<String, dynamic>) {
          return Trip.fromJson(data);
        }

        final activeTrip = body['activeTrip'];
        if (activeTrip is Map<String, dynamic>) {
          return Trip.fromJson(activeTrip);
        }

        if (body.isNotEmpty) {
          return Trip.fromJson(body);
        }
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
      final data = _extractMap(body, ['shipment', 'data'], entityName: 'shipment');
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
      final data = _extractMap(body, ['shipment', 'data'], entityName: 'shipment');
      return ShipmentRequest.fromJson(data);
    });
  }

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
    final normalizedBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  T _handleResponse<T>(http.Response response, T Function(dynamic body) parser) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = _decodeBody(response.body);
      return parser(decoded);
    }

    throw _buildHttpException(response);
  }

  dynamic _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  Exception _buildHttpException(http.Response response) {
    final decoded = _decodeBody(response.body);
    final messageFromBody = _extractErrorMessage(decoded);
    final message = messageFromBody ??
        'Request failed with status ${response.statusCode}: ${response.reasonPhrase ?? 'Unknown error'}';
    return Exception(message);
  }

  String? _extractErrorMessage(dynamic decoded) {
    if (decoded is String && decoded.trim().isNotEmpty) {
      return decoded.trim();
    }

    if (decoded is Map<String, dynamic>) {
      final candidates = ['message', 'error', 'detail', 'errors'];
      for (final key in candidates) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
        if (value is List && value.isNotEmpty) {
          return value.join(', ');
        }
      }
    }

    return null;
  }

  User _parseUser(dynamic body) {
    final data = _extractMap(body, ['user', 'data'], entityName: 'user');
    final token = (body is Map<String, dynamic>)
        ? (body['token'] ?? body['jwt'] ?? data['token'])
        : data['token'];

    final userJson = Map<String, dynamic>.from(data);
    userJson['token'] = token;

    return User.fromJson(userJson);
  }

  Map<String, dynamic> _extractMap(
    dynamic body,
    List<String> nestedKeys, {
    required String entityName,
  }) {
    if (body is Map<String, dynamic>) {
      for (final key in nestedKeys) {
        final nested = body[key];
        if (nested is Map<String, dynamic>) {
          return nested;
        }
      }
      return body;
    }

    throw Exception('Unexpected $entityName response format');
  }

  List<dynamic> _extractList(dynamic body, List<String> nestedKeys) {
    if (body is List) {
      return body;
    }

    if (body is Map<String, dynamic>) {
      for (final key in nestedKeys) {
        final nested = body[key];
        if (nested is List) {
          return nested;
        }
      }
    }

    return const [];
  }
}

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/location_point.dart';

// ── Shared result type ─────────────────────────────────────────────────────────

class LocationResult {
  final String shortAddress;
  final String fullAddress;
  final LatLng latLng;

  const LocationResult({
    required this.shortAddress,
    required this.fullAddress,
    required this.latLng,
  });

  LocationPoint toLocationPoint() => LocationPoint(
        address: fullAddress,
        shortAddress: shortAddress,
        latLng: latLng,
      );
}

// ── Places API (New) ───────────────────────────────────────────────────────────

/// Uses the Google Places API (New) for location autocomplete.
///
/// Cost-saving design:
///   1. Autocomplete requests are cheap per-call ($0.003 each).
///   2. We only call Place Details ($0.017) when the user *selects* a suggestion.
///   3. A session token groups all autocomplete calls + the single Place Details
///      call into one billable session ($0.017 total).  Generate a new token
///      when a picker session opens; discard it after Place Details is fetched.
class PlacesService {
  static const _baseUrl = 'https://places.googleapis.com/v1';

  static String get _apiKey => dotenv.env['MAPS_API_KEY'] ?? '';

  // ── Session token ────────────────────────────────────────────────────────────

  /// Call once when the picker sheet opens. Pass the returned token to every
  /// [autocomplete] call and to [placeDetails]. The token is consumed after
  /// Place Details is fetched — do not reuse across picker sessions.
  static String newSessionToken() =>
      'faraway_${DateTime.now().millisecondsSinceEpoch}';

  // ── Autocomplete ─────────────────────────────────────────────────────────────

  /// Returns place predictions for [input] biased to India.
  /// Returns an empty list on any error so the UI degrades gracefully.
  static Future<List<PlacePrediction>> autocomplete(
    String input,
    String sessionToken,
  ) async {
    if (input.trim().length < 2) return const [];

    final uri = Uri.parse('$_baseUrl/places:autocomplete');
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              // Only fetch the fields we actually use — minimises response size
              'X-Goog-FieldMask':
                  'suggestions.placePrediction.text,'
                  'suggestions.placePrediction.placeId',
            },
            body: jsonEncode({
              'input': input.trim(),
              'includedRegionCodes': ['in'],
              'sessionToken': sessionToken,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = body['suggestions'] as List<dynamic>? ?? [];
      return suggestions
          .map((s) => PlacePrediction._fromJson(
              s['placePrediction'] as Map<String, dynamic>))
          .whereType<PlacePrediction>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Place Details ────────────────────────────────────────────────────────────

  /// Fetches coordinates + address for [placeId].
  /// Pass the same [sessionToken] used during autocomplete — this finalises
  /// the session and consolidates billing.
  static Future<LocationResult?> placeDetails(
    String placeId,
    String sessionToken,
  ) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId').replace(
      queryParameters: {'sessionToken': sessionToken},
    );
    try {
      final response = await http
          .get(
            uri,
            headers: {
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'id,displayName,formattedAddress,location',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseDetails(body);
    } catch (_) {
      return null;
    }
  }

  static LocationResult? _parseDetails(Map<String, dynamic> body) {
    final loc = body['location'] as Map<String, dynamic>?;
    if (loc == null) return null;
    final lat = (loc['latitude'] as num?)?.toDouble();
    final lng = (loc['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final displayName =
        (body['displayName'] as Map<String, dynamic>?)?['text'] as String? ??
            '';
    final formattedAddress = body['formattedAddress'] as String? ?? displayName;

    return LocationResult(
      shortAddress: displayName.isNotEmpty ? displayName : formattedAddress,
      fullAddress: formattedAddress,
      latLng: LatLng(lat, lng),
    );
  }
}

// ── Supporting types ───────────────────────────────────────────────────────────

class PlacePrediction {
  final String placeId;
  final String text;

  const PlacePrediction({required this.placeId, required this.text});

  static PlacePrediction? _fromJson(Map<String, dynamic> json) {
    final placeId = json['placeId'] as String?;
    final textMap = json['text'] as Map<String, dynamic>?;
    final text = textMap?['text'] as String?;
    if (placeId == null || text == null) return null;
    return PlacePrediction(placeId: placeId, text: text);
  }
}

// ── Device GPS ────────────────────────────────────────────────────────────────

/// Handles runtime permission and device GPS retrieval.
/// Uses the device OS location — does NOT call any Google API.
class GpsService {
  /// Returns the current device location, or null if permission is denied
  /// or if the device position cannot be determined.
  static Future<LocationResult?> currentLocation() async {
    // 1. Check/request permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    // 2. Confirm location services are enabled
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    // 3. Get position
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // 4. Reverse-geocode to a human address (single free Nominatim call)
      final address = await _reverseGeocode(pos.latitude, pos.longitude);
      return LocationResult(
        shortAddress: address ?? 'Current Location',
        fullAddress:
            address ?? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
        latLng: LatLng(pos.latitude, pos.longitude),
      );
    } catch (_) {
      return null;
    }
  }

  /// Single Nominatim reverse-geocode call — only triggered when user taps
  /// "Use current location", so it does not affect autocomplete billing.
  static Future<String?> _reverseGeocode(double lat, double lng) async {
    final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&zoom=14');
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'FarAway/1.0 (freight-sharing-app)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = body['address'] as Map<String, dynamic>?;
      if (addr != null) {
        final parts = <String>[
          if (addr['suburb'] is String) addr['suburb'] as String,
          if (addr['city'] is String)
            addr['city'] as String
          else if (addr['town'] is String)
            addr['town'] as String,
        ].where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
      return body['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }
}

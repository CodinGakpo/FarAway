import 'dart:convert';
import 'package:flutter/foundation.dart';
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

/// Wraps the Google Places API (New) for location autocomplete.
///
/// Cost design:
///   • Autocomplete calls are batched per session token.
///   • Place Details (one per user tap) closes the session.
///   • Total cost per selection = one billable session = $0.017.
///
/// Billing reference:
///   https://developers.google.com/maps/documentation/places/web-service/usage-and-billing
class PlacesService {
  static const _baseUrl = 'https://places.googleapis.com/v1';

  static String get _apiKey => dotenv.env['MAPS_API_KEY'] ?? '';

  // ── Session token ────────────────────────────────────────────────────────────

  /// Generate once when the picker sheet opens.
  /// Reuse for every autocomplete call within the session.
  /// Pass the same token to [placeDetails] — this finalises the session.
  static String newSessionToken() {
    // URL-safe token that is unique per picker session.
    // Using milliseconds + microseconds avoids collisions when the picker
    // is opened and closed in rapid succession.
    return 'fa_${DateTime.now().microsecondsSinceEpoch}';
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────────

  /// Returns place predictions for [input], biased to India.
  ///
  /// Returns ([predictions], [error]) — error is non-null on API failure.
  /// The caller can distinguish "no results" from "API down".
  static Future<(List<PlacePrediction>, String?)> autocomplete(
    String input,
    String sessionToken,
  ) async {
    if (input.trim().length < 2) return (const <PlacePrediction>[], null);

    final uri = Uri.parse('$_baseUrl/places:autocomplete');
    try {
      final sw = Stopwatch()..start();
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              // Request only what the UI renders — minimises response size and cost.
              // structuredFormat gives mainText/secondaryText for the two-line display.
              'X-Goog-FieldMask': 'suggestions.placePrediction.placeId,'
                  'suggestions.placePrediction.structuredFormat.mainText.text,'
                  'suggestions.placePrediction.structuredFormat.secondaryText.text',
            },
            body: jsonEncode({
              'input': input.trim(),
              'languageCode': 'en',
              'includedRegionCodes': ['in'],
              // locationBias intentionally omitted.
              // Google Places API (New) caps circle radius at 50,000 m — too small
              // to bias all of India (3,300 km wide) without restricting results.
              // Future: pass device GPS + radius ≤ 50000 when location is available.
              'sessionToken': sessionToken,
            }),
          )
          .timeout(const Duration(seconds: 8));

      debugPrint('[Places] autocomplete "$input" → '
          'HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms');

      if (response.statusCode != 200) {
        final msg = _extractError(response.body, response.statusCode);
        debugPrint('[Places] autocomplete error: $msg');
        return (const <PlacePrediction>[], msg);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = body['suggestions'] as List<dynamic>? ?? [];
      debugPrint('[Places] autocomplete "$input" → ${raw.length} suggestions');

      final predictions = <PlacePrediction>[];
      for (final s in raw) {
        // FIX: safe null-check — avoids crashing the whole batch when
        // a query-suggestion entry has no placePrediction field.
        if (s is! Map<String, dynamic>) continue;
        final pred = s['placePrediction'];
        if (pred is! Map<String, dynamic>) continue;
        final p = PlacePrediction._fromJson(pred);
        if (p != null) predictions.add(p);
      }
      return (predictions, null);
    } on Exception catch (e) {
      debugPrint('[Places] autocomplete exception: $e');
      return (const <PlacePrediction>[], 'Network error. Check your connection.');
    }
  }

  // ── Place Details ────────────────────────────────────────────────────────────

  /// Fetches coordinates and address for the selected [placeId].
  /// Passing [sessionToken] closes the billing session started during autocomplete.
  ///
  /// Returns ([result], [error]).
  static Future<(LocationResult?, String?)> placeDetails(
    String placeId,
    String sessionToken,
  ) async {
    // Session token closes the billing session when passed here.
    final uri = Uri.parse('$_baseUrl/places/$placeId')
        .replace(queryParameters: {'sessionToken': sessionToken});
    try {
      final sw = Stopwatch()..start();
      final response = await http
          .get(
            uri,
            headers: {
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'id,displayName,formattedAddress,location',
            },
          )
          .timeout(const Duration(seconds: 8));

      debugPrint('[Places] placeDetails $placeId → '
          'HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms');

      if (response.statusCode != 200) {
        final msg = _extractError(response.body, response.statusCode);
        debugPrint('[Places] placeDetails error: $msg');
        return (null, msg);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = _parseDetails(body);
      if (result == null) {
        debugPrint('[Places] placeDetails: could not parse location from $body');
        return (null, 'Location data not available for this place.');
      }
      return (result, null);
    } on Exception catch (e) {
      debugPrint('[Places] placeDetails exception: $e');
      return (null, 'Network error. Check your connection.');
    }
  }

  static LocationResult? _parseDetails(Map<String, dynamic> body) {
    final loc = body['location'] as Map<String, dynamic>?;
    if (loc == null) return null;
    final lat = (loc['latitude'] as num?)?.toDouble();
    final lng = (loc['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final displayName =
        (body['displayName'] as Map<String, dynamic>?)?['text'] as String? ?? '';
    final formattedAddress =
        body['formattedAddress'] as String? ?? displayName;

    return LocationResult(
      shortAddress: displayName.isNotEmpty ? displayName : formattedAddress,
      fullAddress: formattedAddress,
      latLng: LatLng(lat, lng),
    );
  }

  static String _extractError(String body, int statusCode) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String?;
      if (message != null) return '($statusCode) $message';
    } catch (_) {}
    if (statusCode == 403) {
      return 'Places API access denied (403). '
          'Verify the API key and that Places API (New) is enabled in Google Cloud.';
    }
    if (statusCode == 400) {
      return 'Bad request (400). Check the field mask and request body.';
    }
    return 'HTTP $statusCode error';
  }
}

// ── Supporting types ───────────────────────────────────────────────────────────

class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  /// Full display string — used where a single-line label is needed.
  String get fullText =>
      secondaryText.isNotEmpty ? '$mainText, $secondaryText' : mainText;

  static PlacePrediction? _fromJson(Map<String, dynamic> json) {
    final placeId = json['placeId'] as String?;
    if (placeId == null) return null;

    final fmt = json['structuredFormat'] as Map<String, dynamic>?;
    // FIX: parse from structuredFormat for proper main/secondary display.
    final mainText = (fmt?['mainText'] as Map<String, dynamic>?)?['text']
            as String? ??
        '';
    final secondaryText =
        (fmt?['secondaryText'] as Map<String, dynamic>?)?['text'] as String? ??
            '';

    if (mainText.isEmpty) return null;
    return PlacePrediction(
      placeId: placeId,
      mainText: mainText,
      secondaryText: secondaryText,
    );
  }
}

// ── Device GPS ────────────────────────────────────────────────────────────────

/// Handles device GPS via the geolocator package.
/// Does NOT consume any Google Cloud API.
class GpsService {
  static Future<LocationResult?> currentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final address = await _reverseGeocode(pos.latitude, pos.longitude);
      return LocationResult(
        shortAddress: address ?? 'Current Location',
        fullAddress: address ??
            '${pos.latitude.toStringAsFixed(4)}, '
                '${pos.longitude.toStringAsFixed(4)}',
        latLng: LatLng(pos.latitude, pos.longitude),
      );
    } catch (e) {
      debugPrint('[GPS] currentLocation error: $e');
      return null;
    }
  }

  /// Single Nominatim reverse-geocode — only called once when the user taps
  /// "Use current location". Not on the autocomplete path.
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

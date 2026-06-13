import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/location_point.dart';

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

class LocationService {
  static const _nominatimBase = 'https://nominatim.openstreetmap.org';
  static const _headers = {
    'User-Agent': 'FarAway/1.0 (freight-sharing-app)',
    'Accept-Language': 'en',
  };

  /// Searches for places matching [query] in India.
  /// Returns an empty list on failure instead of throwing, so the UI
  /// can treat errors as "no results" gracefully.
  static Future<List<LocationResult>> search(String query) async {
    if (query.trim().length < 2) return const [];

    final uri = Uri.parse('$_nominatimBase/search').replace(queryParameters: {
      'q': query.trim(),
      'format': 'json',
      'countrycodes': 'in',
      'limit': '8',
      'addressdetails': '1',
    });

    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return const [];

      final List<dynamic> results = jsonDecode(response.body) as List;
      return results
          .map((item) => _parse(item as Map<String, dynamic>))
          .whereType<LocationResult>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static LocationResult? _parse(Map<String, dynamic> item) {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;

    final displayName = item['display_name'] as String? ?? '';
    final name = item['name'] as String?;

    // Derive a short address: use the name field if present,
    // otherwise take the first two comma-separated parts of display_name.
    final short = (name != null && name.isNotEmpty)
        ? name
        : displayName.split(',').take(2).join(',').trim();

    return LocationResult(
      shortAddress: short,
      fullAddress: displayName,
      latLng: LatLng(lat, lon),
    );
  }
}

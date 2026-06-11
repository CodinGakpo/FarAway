import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static final String BASE_URL =
      dotenv.env['BASE_URL'] ?? 'http://localhost:8000';

  // Auth endpoints
  static const String AUTH_LOGIN = '/auth/login';
  static const String AUTH_ME = '/auth/me';
  static const String AUTH_SYNC = '/auth/sync';

  // Domain endpoints (kept for non-auth screens)
  static const String TRIPS = '/trips';
  static const String LOADS = '/loads';
  static const String MATCHES = '/matches';
  static const String SHIPMENTS = '/shipments';
  static const String BOOKINGS = '/bookings';

  static Map<String, String> headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}

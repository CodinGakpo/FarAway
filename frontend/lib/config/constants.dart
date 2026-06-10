import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static final String BASE_URL = dotenv.env['BASE_URL'] ?? '';

  static const String AUTH_REGISTER = '/auth/register';
  static const String AUTH_LOGIN = '/auth/login';
  static const String TRIPS = '/trips';
  static const String SHIPMENTS = '/shipments';
  static const String BOOKINGS = '/bookings';

  static Map<String, String> headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}

import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationPoint {
  final String address;
  final String shortAddress;
  final LatLng latLng;

  const LocationPoint({
    required this.address,
    required this.shortAddress,
    required this.latLng,
  });

  @override
  bool operator ==(Object other) =>
      other is LocationPoint && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

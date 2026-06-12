import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'location_point.dart';
import 'truck_option.dart';

class ShipmentDraft {
  final LocationPoint? pickup;
  final LocationPoint? drop;
  final String cargoName;
  final String cargoCategory;
  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final double declaredValue;
  final String specialInstructions;
  final TruckOption? selectedTruck;

  const ShipmentDraft({
    this.pickup,
    this.drop,
    this.cargoName = '',
    this.cargoCategory = '',
    this.weightKg = 0,
    this.lengthCm = 0,
    this.widthCm = 0,
    this.heightCm = 0,
    this.declaredValue = 0,
    this.specialInstructions = '',
    this.selectedTruck,
  });

  double get volumeCm3 => lengthCm * widthCm * heightCm;

  double get distanceKm {
    if (pickup == null || drop == null) return 0;
    return _haversineKm(pickup!.latLng, drop!.latLng);
  }

  double get durationMin => distanceKm > 0 ? distanceKm * 2.4 : 0;

  double get estimatedPrice {
    if (selectedTruck == null) return 0;
    return selectedTruck!.estimatedTotal(distanceKm);
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  ShipmentDraft copyWith({
    LocationPoint? pickup,
    LocationPoint? drop,
    String? cargoName,
    String? cargoCategory,
    double? weightKg,
    double? lengthCm,
    double? widthCm,
    double? heightCm,
    double? declaredValue,
    String? specialInstructions,
    TruckOption? selectedTruck,
  }) =>
      ShipmentDraft(
        pickup: pickup ?? this.pickup,
        drop: drop ?? this.drop,
        cargoName: cargoName ?? this.cargoName,
        cargoCategory: cargoCategory ?? this.cargoCategory,
        weightKg: weightKg ?? this.weightKg,
        lengthCm: lengthCm ?? this.lengthCm,
        widthCm: widthCm ?? this.widthCm,
        heightCm: heightCm ?? this.heightCm,
        declaredValue: declaredValue ?? this.declaredValue,
        specialInstructions: specialInstructions ?? this.specialInstructions,
        selectedTruck: selectedTruck ?? this.selectedTruck,
      );
}

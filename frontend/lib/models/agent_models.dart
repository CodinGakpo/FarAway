class GeoPoint {
  final double lat;
  final double lng;

  GeoPoint({required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

// ── Find Trips ────────────────────────────────────────────────────────

class TripSummary {
  final String tripId;
  final DateTime departureAt;
  final double baseDistanceKm;
  final double maxDetourKm;
  final double distPickupKm;
  final double distDropoffKm;

  TripSummary.fromJson(Map<String, dynamic> json)
      : tripId = json['trip_id'],
        departureAt = DateTime.parse(json['departure_at']),
        baseDistanceKm = (json['base_distance_km'] as num).toDouble(),
        maxDetourKm = (json['max_detour_km'] as num).toDouble(),
        distPickupKm = (json['dist_pickup_km'] as num).toDouble(),
        distDropoffKm = (json['dist_dropoff_km'] as num).toDouble();
}

class FindTripsResponse {
  final List<TripSummary> trips;
  final int totalFound;

  FindTripsResponse.fromJson(Map<String, dynamic> json)
      : trips = (json['trips'] as List)
            .map((item) => TripSummary.fromJson(item))
            .toList(),
        totalFound = json['total_found'];
}

// ── Analyze Route ─────────────────────────────────────────────────────

class AnalyzeRouteResponse {
  final bool feasible;
  final String tripId;
  final double detourDistanceKm;
  final double detourDurationMin;
  final double detourPercentage;
  final double routeFitScore;
  final String? rejectionReason;

  AnalyzeRouteResponse.fromJson(Map<String, dynamic> json)
      : feasible = json['feasible'],
        tripId = json['trip_id'],
        detourDistanceKm = (json['detour_distance_km'] as num).toDouble(),
        detourDurationMin = (json['detour_duration_min'] as num).toDouble(),
        detourPercentage = (json['detour_percentage'] as num).toDouble(),
        routeFitScore = (json['route_fit_score'] as num).toDouble(),
        rejectionReason = json['rejection_reason'];
}

// ── Check Capacity ────────────────────────────────────────────────────

class CheckCapacityResponse {
  final bool available;
  final double remainingWeightKg;
  final double remainingVolumeM3;
  final double utilizationPct;
  final String? rejectionReason;

  CheckCapacityResponse.fromJson(Map<String, dynamic> json)
      : available = json['available'],
        remainingWeightKg = (json['remaining_weight_kg'] as num).toDouble(),
        remainingVolumeM3 = (json['remaining_volume_m3'] as num).toDouble(),
        utilizationPct = (json['utilization_pct'] as num).toDouble(),
        rejectionReason = json['rejection_reason'];
}

// ── Calculate Price ───────────────────────────────────────────────────

class PriceBreakdown {
  final double baseFare;
  final double weightCharge;
  final double volumeCharge;
  final double detourSurcharge;
  final double declaredValueInsurance;
  final double goodsTypeMultiplier;
  final double utilizationSurge;
  final double platformFee;
  final double profitabilityFloor;
  final bool isFloorApplied;

  PriceBreakdown.fromJson(Map<String, dynamic> json)
      : baseFare = (json['base_fare'] as num).toDouble(),
        weightCharge = (json['weight_charge'] as num).toDouble(),
        volumeCharge = (json['volume_charge'] as num).toDouble(),
        detourSurcharge = (json['detour_surcharge'] as num).toDouble(),
        declaredValueInsurance = (json['declared_value_insurance'] as num).toDouble(),
        goodsTypeMultiplier = (json['goods_type_multiplier'] as num).toDouble(),
        utilizationSurge = (json['utilization_surge'] as num).toDouble(),
        platformFee = (json['platform_fee'] as num).toDouble(),
        profitabilityFloor = (json['profitability_floor'] as num).toDouble(),
        isFloorApplied = json['is_floor_applied'];
}

class CalculatePriceResponse {
  final double finalPrice;
  final String currency;
  final PriceBreakdown breakdown;
  final bool isProfitable;

  CalculatePriceResponse.fromJson(Map<String, dynamic> json)
      : finalPrice = (json['final_price'] as num).toDouble(),
        currency = json['currency'],
        breakdown = PriceBreakdown.fromJson(json['breakdown']),
        isProfitable = json['is_profitable'];
}

// ── Hold Capacity ─────────────────────────────────────────────────────

class HoldCapacityResponse {
  final bool success;
  final String? bookingId;
  final DateTime? holdExpiresAt;
  final String? rejectionReason;

  HoldCapacityResponse.fromJson(Map<String, dynamic> json)
      : success = json['success'],
        bookingId = json['booking_id'],
        holdExpiresAt = json['hold_expires_at'] != null 
            ? DateTime.parse(json['hold_expires_at']) 
            : null,
        rejectionReason = json['rejection_reason'];
}

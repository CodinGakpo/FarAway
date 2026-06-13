class ShipmentRequest {
  final String id;
  final String customerId;
  final String pickupLocation;
  final String dropoffLocation;
  final double weight;
  final double volume;
  final String cargoCategory;
  final String status;
  final double? price;
  final String? tripId;
  final bool feasibilityStatus;
  final String? feasibilityTrace;

  ShipmentRequest({
    required this.id,
    required this.customerId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.weight,
    required this.volume,
    required this.cargoCategory,
    required this.status,
    this.price,
    this.tripId,
    this.feasibilityStatus = false,
    this.feasibilityTrace,
  });

  factory ShipmentRequest.fromJson(Map<String, dynamic> json) {
    return ShipmentRequest(
      id: json['id']?.toString() ?? '',
      // Accept both snake_case (backend) and camelCase (legacy)
      customerId: json['customer_id']?.toString() ??
          json['customerId']?.toString() ??
          '',
      pickupLocation: json['pickup_location'] as String? ??
          json['pickupLocation'] as String? ??
          '',
      dropoffLocation: json['dropoff_location'] as String? ??
          json['dropoffLocation'] as String? ??
          '',
      weight: (json['weight'] as num).toDouble(),
      volume: (json['volume'] as num).toDouble(),
      cargoCategory: json['cargo_category'] as String? ??
          json['cargoCategory'] as String? ??
          '',
      status: json['status'] as String? ?? '',
      price: json['price'] == null ? null : (json['price'] as num).toDouble(),
      tripId: (json['trip_id'] ?? json['tripId'])?.toString(),
      feasibilityStatus: json['feasibility_status'] as bool? ?? false,
      feasibilityTrace: json['feasibility_trace'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerId': customerId,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'weight': weight,
      'volume': volume,
      'cargoCategory': cargoCategory,
      'status': status,
      'price': price,
      'tripId': tripId,
    };
  }
}

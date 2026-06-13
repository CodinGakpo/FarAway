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
      customerId: (json['customerId'] ?? json['customer_id'])?.toString() ?? '',
      pickupLocation: (json['pickupLocation'] ?? json['pickup_location']) as String,
      dropoffLocation: (json['dropoffLocation'] ?? json['dropoff_location']) as String,
      weight: (json['weight'] as num).toDouble(),
      volume: (json['volume'] as num).toDouble(),
      cargoCategory: (json['cargoCategory'] ?? json['cargo_category']) as String,
      status: json['status'] as String,
      price: json['price'] == null ? null : (json['price'] as num).toDouble(),
      tripId: (json['tripId'] ?? json['trip_id'])?.toString(),
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

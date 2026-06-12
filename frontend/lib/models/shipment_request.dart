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
  });

  factory ShipmentRequest.fromJson(Map<String, dynamic> json) {
    return ShipmentRequest(
      id: json['id']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      pickupLocation: json['pickupLocation'] as String,
      dropoffLocation: json['dropoffLocation'] as String,
      weight: (json['weight'] as num).toDouble(),
      volume: (json['volume'] as num).toDouble(),
      cargoCategory: json['cargoCategory'] as String,
      status: json['status'] as String,
      price: json['price'] == null ? null : (json['price'] as num).toDouble(),
      tripId: json['tripId']?.toString(),
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

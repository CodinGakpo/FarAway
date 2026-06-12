class TruckOption {
  final String id;
  final String type;
  final String capacityLabel;
  final String pickupEta;
  final double basePrice;
  final double pricePerKm;
  final double rating;
  final int reviewCount;
  final String driverName;
  final String truckNumber;
  final String description;

  const TruckOption({
    required this.id,
    required this.type,
    required this.capacityLabel,
    required this.pickupEta,
    required this.basePrice,
    required this.pricePerKm,
    required this.rating,
    required this.reviewCount,
    required this.driverName,
    required this.truckNumber,
    required this.description,
  });

  double estimatedTotal(double distanceKm) =>
      (basePrice + pricePerKm * distanceKm).ceilToDouble();
}

class ShipmentHistoryItem {
  final String id;
  final String pickupAddress;
  final String dropAddress;
  final DateTime date;
  final double price;
  final String status;
  final String truckType;
  final String cargoName;
  final double distanceKm;

  const ShipmentHistoryItem({
    required this.id,
    required this.pickupAddress,
    required this.dropAddress,
    required this.date,
    required this.price,
    required this.status,
    required this.truckType,
    required this.cargoName,
    required this.distanceKm,
  });
}

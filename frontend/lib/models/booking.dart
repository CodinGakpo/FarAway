import 'shipment_draft.dart';

enum BookingStatus {
  confirmed,
  driverAssigned,
  pickupInProgress,
  cargoLoaded,
  inTransit,
  nearDestination,
  delivered,
}

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.confirmed:
        return 'Booking Confirmed';
      case BookingStatus.driverAssigned:
        return 'Driver Assigned';
      case BookingStatus.pickupInProgress:
        return 'Pickup In Progress';
      case BookingStatus.cargoLoaded:
        return 'Cargo Loaded';
      case BookingStatus.inTransit:
        return 'In Transit';
      case BookingStatus.nearDestination:
        return 'Near Destination';
      case BookingStatus.delivered:
        return 'Delivered';
    }
  }

  String get description {
    switch (this) {
      case BookingStatus.confirmed:
        return 'Your booking is confirmed. A driver will be assigned shortly.';
      case BookingStatus.driverAssigned:
        return 'Driver is on the way to your pickup location.';
      case BookingStatus.pickupInProgress:
        return 'Driver has arrived at the pickup location.';
      case BookingStatus.cargoLoaded:
        return 'Cargo has been loaded and verified.';
      case BookingStatus.inTransit:
        return 'Your cargo is on its way to the destination.';
      case BookingStatus.nearDestination:
        return 'Almost there! Driver is near the drop location.';
      case BookingStatus.delivered:
        return 'Your cargo has been delivered successfully!';
    }
  }

  bool get isActive => this != BookingStatus.delivered;

  double get progressFraction => index / (BookingStatus.values.length - 1);
}

class Booking {
  final String id;
  final ShipmentDraft draft;
  final BookingStatus status;
  final DateTime createdAt;
  final double finalPrice;

  const Booking({
    required this.id,
    required this.draft,
    required this.status,
    required this.createdAt,
    required this.finalPrice,
  });

  Booking copyWith({BookingStatus? status}) => Booking(
        id: id,
        draft: draft,
        status: status ?? this.status,
        createdAt: createdAt,
        finalPrice: finalPrice,
      );
}

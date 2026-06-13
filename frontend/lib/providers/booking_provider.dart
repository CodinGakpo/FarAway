import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/booking.dart';
import '../models/shipment_draft.dart';
import '../models/shipment_history_item.dart';
import '../services/mock_data_service.dart';
import '../services/api_service.dart';

class BookingProvider extends ChangeNotifier {
  Booking? _activeBooking;

  Booking? get activeBooking => _activeBooking;
  bool get hasActiveBooking =>
      _activeBooking != null && _activeBooking!.status.isActive;

  Future<Booking> createBooking(ShipmentDraft draft) async {
    final shipment = await ApiService().createShipment(
      draft.selectedTruck!.id,
      draft.pickup?.shortAddress ?? '',
      draft.drop?.shortAddress ?? '',
      draft.weightKg,
      draft.volumeCm3 / 1000000,
      draft.cargoCategory,
      estimatedPrice: draft.estimatedPrice,
      feasibilityTrace: draft.selectedTruck!.description,
    );

    await ApiService().confirmBooking(shipment.id);

    final booking = Booking(
      id: shipment.id,
      draft: draft,
      status: BookingStatus.confirmed,
      createdAt: DateTime.now(),
      finalPrice: draft.estimatedPrice,
    );
    _activeBooking = booking;
    notifyListeners();
    return booking;
  }

  void advanceStatus() {
    if (_activeBooking == null) return;
    final statuses = BookingStatus.values;
    final idx = statuses.indexOf(_activeBooking!.status);
    if (idx < statuses.length - 1) {
      _activeBooking =
          _activeBooking!.copyWith(status: statuses[idx + 1]);
      notifyListeners();
    }
  }

  void completeAndArchive() {
    _activeBooking = null;
    notifyListeners();
  }
}

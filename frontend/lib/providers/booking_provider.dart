import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/booking.dart';
import '../models/shipment_draft.dart';
import '../models/shipment_history_item.dart';
import '../services/mock_data_service.dart';

class BookingProvider extends ChangeNotifier {
  Booking? _activeBooking;
  final List<ShipmentHistoryItem> _history =
      List.of(MockDataService.history);

  Booking? get activeBooking => _activeBooking;
  bool get hasActiveBooking =>
      _activeBooking != null && _activeBooking!.status.isActive;
  List<ShipmentHistoryItem> get history => List.unmodifiable(_history);

  Future<Booking> createBooking(ShipmentDraft draft) async {
    await Future.delayed(const Duration(milliseconds: 1600));
    final booking = Booking(
      id: 'FB${1000 + Random().nextInt(8999)}',
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
    if (_activeBooking == null) return;
    final b = _activeBooking!;
    final pickup = b.draft.pickup;
    final drop = b.draft.drop;
    if (pickup != null && drop != null) {
      _history.insert(
        0,
        ShipmentHistoryItem(
          id: b.id,
          pickupAddress: pickup.shortAddress,
          dropAddress: drop.shortAddress,
          date: b.createdAt,
          price: b.finalPrice,
          status: 'Delivered',
          truckType: b.draft.selectedTruck?.type ?? 'Truck',
          cargoName: b.draft.cargoName.isNotEmpty
              ? b.draft.cargoName
              : 'Cargo',
          distanceKm: b.draft.distanceKm,
        ),
      );
    }
    _activeBooking = null;
    notifyListeners();
  }
}

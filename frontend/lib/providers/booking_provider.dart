import 'package:flutter/foundation.dart';
import '../models/booking.dart';
import '../models/shipment_draft.dart';
import '../models/shipment_history_item.dart';
import '../services/api_service.dart';

class BookingProvider extends ChangeNotifier {
  Booking? _activeBooking;
  // In-session archive only: holds the most recently completed booking
  // so it can appear immediately in the history tab without a refresh.
  // The authoritative history is fetched live from GET /shipments.
  final List<ShipmentHistoryItem> _sessionArchive = [];

  Booking? get activeBooking => _activeBooking;
  bool get hasActiveBooking =>
      _activeBooking != null && _activeBooking!.status.isActive;
  List<ShipmentHistoryItem> get sessionArchive =>
      List.unmodifiable(_sessionArchive);

  /// Creates a real shipment via the backend:
  /// 1. POST /shipments  — creates + runs AI evaluation
  /// 2. POST /shipments/{id}/confirm — moves DRAFT → PENDING
  Future<Booking> createBooking(ShipmentDraft draft) async {
    if (draft.selectedTripId == null) {
      throw Exception('No trip selected. Please select a freight trip first.');
    }
    if (draft.pickup == null || draft.drop == null) {
      throw Exception('Pickup and drop locations are required.');
    }
    if (draft.weightKg <= 0) {
      throw Exception('Cargo weight must be greater than zero.');
    }

    final api = ApiService();

    // Step 1: Create shipment — backend runs AI feasibility + pricing
    final shipment = await api.createShipment(
      draft.selectedTripId.toString(),
      draft.pickup!.address,
      draft.drop!.address,
      draft.weightKg,
      draft.volumeCm3 / 1000000, // cm³ → m³
      draft.cargoCategory.isNotEmpty ? draft.cargoCategory : 'general',
    );

    // Step 2: Check if AI determined this route is feasible
    if (!shipment.feasibilityStatus) {
      final reason = shipment.feasibilityTrace
              ?.split('\n')
              .where((l) => l.trim().isNotEmpty)
              .take(2)
              .join(' ') ??
          'Route or capacity check failed.';
      throw Exception(reason);
    }

    // Step 3: Confirm — moves status DRAFT → PENDING
    final confirmed = await api.confirmShipment(shipment.id);

    final booking = Booking(
      id: confirmed.id,
      draft: draft,
      status: BookingStatus.confirmed,
      createdAt: DateTime.now(),
      finalPrice: confirmed.price ?? shipment.price ?? 0.0,
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
      _sessionArchive.insert(
        0,
        ShipmentHistoryItem(
          id: b.id,
          pickupAddress: pickup.shortAddress,
          dropAddress: drop.shortAddress,
          date: b.createdAt,
          price: b.finalPrice,
          status: 'Delivered',
          truckType: b.draft.selectedTruck?.type ?? 'Freight Truck',
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

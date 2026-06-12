import 'package:flutter/foundation.dart';
import '../models/location_point.dart';
import '../models/shipment_draft.dart';
import '../models/truck_option.dart';

class ShipmentProvider extends ChangeNotifier {
  ShipmentDraft _draft = const ShipmentDraft();

  ShipmentDraft get draft => _draft;

  bool get hasRoute => _draft.pickup != null && _draft.drop != null;

  void setPickup(LocationPoint pickup) {
    _draft = _draft.copyWith(pickup: pickup);
    notifyListeners();
  }

  void setDrop(LocationPoint drop) {
    _draft = _draft.copyWith(drop: drop);
    notifyListeners();
  }

  void updateCargoDetails({
    required String cargoName,
    required String cargoCategory,
    required double weightKg,
    required double lengthCm,
    required double widthCm,
    required double heightCm,
    required double declaredValue,
    required String specialInstructions,
  }) {
    _draft = _draft.copyWith(
      cargoName: cargoName,
      cargoCategory: cargoCategory,
      weightKg: weightKg,
      lengthCm: lengthCm,
      widthCm: widthCm,
      heightCm: heightCm,
      declaredValue: declaredValue,
      specialInstructions: specialInstructions,
    );
    notifyListeners();
  }

  void selectTruck(TruckOption truck) {
    _draft = _draft.copyWith(selectedTruck: truck);
    notifyListeners();
  }

  void reset() {
    _draft = const ShipmentDraft();
    notifyListeners();
  }
}

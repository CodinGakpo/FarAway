import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/location_point.dart';
import '../models/truck_option.dart';
import '../models/shipment_history_item.dart';

abstract class MockDataService {
  static const LatLng defaultCenter = LatLng(19.0595, 72.8295);

  static const List<LocationPoint> pickupLocations = [
    LocationPoint(
      address: 'Current Location — Bandra West, Mumbai 400050',
      shortAddress: 'Bandra West, Mumbai',
      latLng: LatLng(19.0595, 72.8295),
    ),
    LocationPoint(
      address: 'Bandra Kurla Complex (BKC), Mumbai 400051',
      shortAddress: 'BKC, Mumbai',
      latLng: LatLng(19.0663, 72.8680),
    ),
    LocationPoint(
      address: 'Andheri East, Mumbai 400069',
      shortAddress: 'Andheri East',
      latLng: LatLng(19.1197, 72.8469),
    ),
    LocationPoint(
      address: 'Hiranandani Gardens, Powai, Mumbai 400076',
      shortAddress: 'Powai, Mumbai',
      latLng: LatLng(19.1176, 72.9060),
    ),
    LocationPoint(
      address: 'Worli Sea Face, Mumbai 400018',
      shortAddress: 'Worli, Mumbai',
      latLng: LatLng(19.0177, 72.8182),
    ),
    LocationPoint(
      address: 'Dadar TT Circle, Mumbai 400014',
      shortAddress: 'Dadar, Mumbai',
      latLng: LatLng(19.0186, 72.8425),
    ),
    LocationPoint(
      address: 'Malad West, Mumbai 400064',
      shortAddress: 'Malad West',
      latLng: LatLng(19.1872, 72.8483),
    ),
  ];

  static const List<LocationPoint> dropLocations = [
    LocationPoint(
      address: 'Vashi Sector 17, Navi Mumbai 400703',
      shortAddress: 'Vashi, Navi Mumbai',
      latLng: LatLng(19.0759, 73.0078),
    ),
    LocationPoint(
      address: 'Thane West, Thane 400601',
      shortAddress: 'Thane West',
      latLng: LatLng(19.2183, 72.9781),
    ),
    LocationPoint(
      address: 'Shivajinagar, Pune 411005',
      shortAddress: 'Shivajinagar, Pune',
      latLng: LatLng(18.5204, 73.8567),
    ),
    LocationPoint(
      address: 'Nashik Road, Nashik 422101',
      shortAddress: 'Nashik',
      latLng: LatLng(19.9975, 73.7898),
    ),
    LocationPoint(
      address: 'MIDC Turbhe, Navi Mumbai 400705',
      shortAddress: 'Turbhe MIDC',
      latLng: LatLng(19.0878, 73.0143),
    ),
    LocationPoint(
      address: 'Bhiwandi Logistics Park, Thane 421302',
      shortAddress: 'Bhiwandi',
      latLng: LatLng(19.3001, 73.0637),
    ),
    LocationPoint(
      address: 'Panvel, Navi Mumbai 410206',
      shortAddress: 'Panvel',
      latLng: LatLng(18.9894, 73.1175),
    ),
  ];

  static const List<TruckOption> trucks = [
    TruckOption(
      id: 'mini',
      type: 'Mini Truck',
      capacityLabel: 'Up to 1 Ton',
      pickupEta: '12–18 min',
      basePrice: 800,
      pricePerKm: 15,
      rating: 4.8,
      reviewCount: 312,
      driverName: 'Rajesh Kumar',
      truckNumber: 'MH-01-AB-1234',
      description: 'Best for small loads — electronics, documents, parcels.',
    ),
    TruckOption(
      id: 'pickup',
      type: 'Pickup Truck',
      capacityLabel: 'Up to 2 Tons',
      pickupEta: '10–15 min',
      basePrice: 1200,
      pricePerKm: 22,
      rating: 4.6,
      reviewCount: 218,
      driverName: 'Suresh Patil',
      truckNumber: 'MH-02-CD-5678',
      description: 'Ideal for furniture, appliances & mid-size cargo.',
    ),
    TruckOption(
      id: 'medium',
      type: 'Medium Cargo Truck',
      capacityLabel: 'Up to 5 Tons',
      pickupEta: '20–30 min',
      basePrice: 2200,
      pricePerKm: 38,
      rating: 4.7,
      reviewCount: 174,
      driverName: 'Vikram Sharma',
      truckNumber: 'MH-04-EF-9012',
      description: 'Perfect for bulk goods, machinery & retail stock.',
    ),
    TruckOption(
      id: 'heavy',
      type: 'Heavy Truck',
      capacityLabel: 'Up to 15 Tons',
      pickupEta: '30–45 min',
      basePrice: 4500,
      pricePerKm: 65,
      rating: 4.5,
      reviewCount: 96,
      driverName: 'Amit Desai',
      truckNumber: 'MH-09-GH-3456',
      description: 'For heavy industrial loads, factory goods & ODC cargo.',
    ),
  ];

  static List<ShipmentHistoryItem> get history => [
        ShipmentHistoryItem(
          id: 'FB4821',
          pickupAddress: 'BKC, Mumbai',
          dropAddress: 'Vashi, Navi Mumbai',
          date: DateTime.now().subtract(const Duration(days: 1)),
          price: 1842,
          status: 'Delivered',
          truckType: 'Pickup Truck',
          cargoName: 'Office Furniture',
          distanceKm: 27.4,
        ),
        ShipmentHistoryItem(
          id: 'FB3967',
          pickupAddress: 'Andheri East',
          dropAddress: 'Shivajinagar, Pune',
          date: DateTime.now().subtract(const Duration(days: 4)),
          price: 6480,
          status: 'Delivered',
          truckType: 'Medium Cargo Truck',
          cargoName: 'Industrial Equipment',
          distanceKm: 152.8,
        ),
        ShipmentHistoryItem(
          id: 'FB3412',
          pickupAddress: 'Worli, Mumbai',
          dropAddress: 'Thane West',
          date: DateTime.now().subtract(const Duration(days: 8)),
          price: 1210,
          status: 'Delivered',
          truckType: 'Mini Truck',
          cargoName: 'Consumer Electronics',
          distanceKm: 28.1,
        ),
        ShipmentHistoryItem(
          id: 'FB2889',
          pickupAddress: 'Powai, Mumbai',
          dropAddress: 'Bhiwandi',
          date: DateTime.now().subtract(const Duration(days: 15)),
          price: 2750,
          status: 'Delivered',
          truckType: 'Pickup Truck',
          cargoName: 'Textile Goods',
          distanceKm: 44.6,
        ),
        ShipmentHistoryItem(
          id: 'FB2105',
          pickupAddress: 'Dadar, Mumbai',
          dropAddress: 'Panvel',
          date: DateTime.now().subtract(const Duration(days: 23)),
          price: 4920,
          status: 'Delivered',
          truckType: 'Medium Cargo Truck',
          cargoName: 'Construction Material',
          distanceKm: 55.3,
        ),
      ];
}

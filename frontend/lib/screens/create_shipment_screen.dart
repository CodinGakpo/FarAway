import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/agent_models.dart';

class CreateShipmentScreen extends StatefulWidget {
  const CreateShipmentScreen({super.key});

  @override
  State<CreateShipmentScreen> createState() => _CreateShipmentScreenState();
}

class _CreateShipmentScreenState extends State<CreateShipmentScreen> {
  final ApiService _api = ApiService();
  final List<String> _logs = [];

  // Hardcoded coordinates for testing
  final _pickupLat = TextEditingController(text: '12.9716');
  final _pickupLng = TextEditingController(text: '77.5946');
  final _dropoffLat = TextEditingController(text: '13.0827');
  final _dropoffLng = TextEditingController(text: '80.2707');
  final _weight = TextEditingController(text: '500');
  final _volume = TextEditingController(text: '2.5');

  bool _isRunning = false;

  void _log(String message) {
    setState(() {
      _logs.add(message);
    });
  }

  Future<void> _runAgentFlow() async {
    setState(() {
      _logs.clear();
      _isRunning = true;
    });

    try {
      final pickup = GeoPoint(
          lat: double.parse(_pickupLat.text),
          lng: double.parse(_pickupLng.text));
      final dropoff = GeoPoint(
          lat: double.parse(_dropoffLat.text),
          lng: double.parse(_dropoffLng.text));
      final weight = double.parse(_weight.text);
      final volume = double.parse(_volume.text);

      _log('🤖 Starting AI Agent Flow...');
      
      // 1. Find Trips
      _log('📍 Step 1: Finding candidate trips...');
      final findTripsResponse = await _api.findCandidateTrips(
          pickup, dropoff, weight, volume);
      
      if (findTripsResponse.trips.isEmpty) {
        _log('❌ No trips found nearby.');
        return;
      }
      
      final trip = findTripsResponse.trips.first;
      _log('✅ Found Trip: ${trip.tripId} (Distance: ${trip.baseDistanceKm}km)');

      // 2. Analyze Route
      _log('🗺️ Step 2: Analyzing route feasibility...');
      final analyzeResponse = await _api.analyzeRoute(trip.tripId, pickup, dropoff);
      
      if (!analyzeResponse.feasible) {
        _log('❌ Route not feasible: ${analyzeResponse.rejectionReason}');
        return;
      }
      _log('✅ Route feasible! Detour: ${analyzeResponse.detourDistanceKm}km (${analyzeResponse.detourDurationMin}min)');

      // 3. Check Capacity
      _log('📦 Step 3: Checking truck capacity...');
      final capacityResponse = await _api.checkCapacity(trip.tripId, weight, volume);
      
      if (!capacityResponse.available) {
        _log('❌ Capacity unavailable: ${capacityResponse.rejectionReason}');
        return;
      }
      _log('✅ Capacity available. Utilization will be ${(capacityResponse.utilizationPct * 100).toStringAsFixed(1)}%');

      // 4. Calculate Price
      _log('💰 Step 4: Calculating dynamic price...');
      final priceResponse = await _api.calculatePrice(
        trip.tripId,
        trip.baseDistanceKm, // Using base distance as proxy for shipment distance
        weight,
        volume,
        analyzeResponse.detourDistanceKm,
        capacityResponse.utilizationPct,
      );
      
      _log('✅ Price calculated: ${priceResponse.currency} ${priceResponse.finalPrice}');
      _log('   Base fare: ${priceResponse.breakdown.baseFare}');
      _log('   Detour surcharge: ${priceResponse.breakdown.detourSurcharge}');
      _log('   Platform fee: ${priceResponse.breakdown.platformFee}');
      
      if (priceResponse.isProfitable) {
        _log('✅ Route is highly profitable for the driver.');
      } else {
        _log('⚠️ Price hit the profitability floor to ensure driver earnings.');
      }

      _log('🎉 AI Agent Evaluation Complete! You can now Hold/Confirm Capacity.');

    } catch (e) {
      _log('❌ Error: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent Testing Harness')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: _pickupLat, decoration: const InputDecoration(labelText: 'Pickup Lat'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _pickupLng, decoration: const InputDecoration(labelText: 'Pickup Lng'))),
              ],
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _dropoffLat, decoration: const InputDecoration(labelText: 'Dropoff Lat'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _dropoffLng, decoration: const InputDecoration(labelText: 'Dropoff Lng'))),
              ],
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _weight, decoration: const InputDecoration(labelText: 'Weight (kg)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _volume, decoration: const InputDecoration(labelText: 'Volume (m3)'))),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isRunning ? null : _runAgentFlow,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white),
              child: _isRunning ? const CircularProgressIndicator(color: Colors.white) : const Text('Run Agent Flow'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(_logs[index], style: const TextStyle(fontFamily: 'monospace')),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

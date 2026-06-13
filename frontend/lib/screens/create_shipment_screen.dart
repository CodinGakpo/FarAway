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

  // Hardcoded coordinates and cities for testing Niranjan's logic
  final _pickupLat = TextEditingController(text: '12.9165');
  final _pickupLng = TextEditingController(text: '79.1325');
  final _pickupCity = TextEditingController(text: 'Vellore');
  final _dropoffLat = TextEditingController(text: '12.9716');
  final _dropoffLng = TextEditingController(text: '77.5946');
  final _dropoffCity = TextEditingController(text: 'Bangalore');
  final _weight = TextEditingController(text: '500');
  final _volume = TextEditingController(text: '2.5');
  final _cargoCategory = TextEditingController(text: 'fragile');

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

      // 2. Niranjan's AI Agent Evaluation
      _log("🤖 Step 2: Running Niranjan's AI Agent Evaluation...");
      
      final evalResponse = await _api.evaluateShipment(
        trip.tripId,
        _pickupCity.text,
        _dropoffCity.text,
        weight,
        volume,
        _cargoCategory.text,
      );
      
      if (!evalResponse.feasible) {
        _log('❌ Shipment Not Feasible.');
      } else {
        _log('✅ Shipment Feasible!');
        _log('💰 Proposed Price: ₹${evalResponse.price}');
      }
      _log('\\n--- Agent Reasoning Trace ---');
      _log(evalResponse.trace);
      _log('------------------------------');

      _log('🎉 AI Agent Evaluation Complete!');

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
                Expanded(child: TextField(controller: _pickupCity, decoration: const InputDecoration(labelText: 'Pickup City'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _dropoffCity, decoration: const InputDecoration(labelText: 'Dropoff City'))),
              ],
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _weight, decoration: const InputDecoration(labelText: 'Weight (kg)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _volume, decoration: const InputDecoration(labelText: 'Volume (m3)'))),
              ],
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _cargoCategory, decoration: const InputDecoration(labelText: 'Category (e.g. fragile)'))),
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

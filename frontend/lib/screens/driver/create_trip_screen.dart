import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../services/api_service.dart';
import '../../widgets/loading_button.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _weightController = TextEditingController();
  final _volumeController = TextEditingController();
  final _dateController = TextEditingController();

  final ApiService _apiService = ApiService();

  DateTime? _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _originController.addListener(_onLocationChanged);
    _destinationController.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _originController.removeListener(_onLocationChanged);
    _destinationController.removeListener(_onLocationChanged);
    _originController.dispose();
    _destinationController.dispose();
    _weightController.dispose();
    _volumeController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1D9E75),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF173B2F),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a trip date')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.createTrip(
        _originController.text.trim(),
        _destinationController.text.trim(),
        _selectedDate!,
        double.parse(_weightController.text.trim()),
        double.parse(_volumeController.text.trim()),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1D9E75);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Trip')),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TripMap(
                  origin: _originController.text.trim(),
                  destination: _destinationController.text.trim(),
                ),
                const SizedBox(height: 24),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _originController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Origin city',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: green, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter origin city';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _destinationController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Destination city',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: green, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter destination city';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        readOnly: true,
                        controller: _dateController,
                        onTap: _pickDate,
                        decoration: InputDecoration(
                          labelText: 'Trip date',
                          hintText: 'Tap to select date',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: green, width: 2),
                          ),
                          suffixIcon: const Icon(Icons.calendar_month_outlined),
                        ),
                        validator: (_) {
                          if (_selectedDate == null) {
                            return 'Select a trip date';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Max weight (kg)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: green, width: 2),
                          ),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null) {
                            return 'Enter a valid weight';
                          }
                          if (parsed <= 0) {
                            return 'Weight must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _volumeController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Max volume (cubic ft)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: green, width: 2),
                          ),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null) {
                            return 'Enter a valid volume';
                          }
                          if (parsed <= 0) {
                            return 'Volume must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      LoadingButton(
                        label: 'Submit Trip',
                        onPressed: _submit,
                        isLoading: _isLoading,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }
}

class _TripMap extends StatelessWidget {
  const _TripMap({required this.origin, required this.destination});

  final String origin;
  final String destination;

  static const LatLng _indiaCenter = LatLng(22.9734, 78.6569);

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};

    if (origin.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _offsetFor(origin, true),
          infoWindow: InfoWindow(title: 'Origin', snippet: origin),
        ),
      );
    }

    if (destination.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _offsetFor(destination, false),
          infoWindow: InfoWindow(title: 'Destination', snippet: destination),
        ),
      );
    }

    final routePoints = <LatLng>[];
    if (origin.isNotEmpty) {
      routePoints.add(_offsetFor(origin, true));
    }
    if (destination.isNotEmpty) {
      routePoints.add(_offsetFor(destination, false));
    }

    final routePolyline = routePoints.length == 2
        ? {
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: const Color(0xFF1D9E75),
              width: 4,
            ),
          }
        : <Polyline>{};

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 240,
        child: GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: _indiaCenter,
            zoom: 4.5,
          ),
          markers: markers,
          polylines: routePolyline,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          tiltGesturesEnabled: false,
          rotateGesturesEnabled: false,
        ),
      ),
    );
  }

  LatLng _offsetFor(String seed, bool isOrigin) {
    final hash = seed.hashCode.abs();
    final latOffset = ((hash % 700) / 1000) + (isOrigin ? 0.15 : -0.15);
    final lngOffset = (((hash ~/ 700) % 700) / 1000) + (isOrigin ? -0.25 : 0.25);
    return LatLng(
      (_indiaCenter.latitude + latOffset).clamp(8.0, 35.0),
      (_indiaCenter.longitude + lngOffset).clamp(68.0, 97.0),
    );
  }
}

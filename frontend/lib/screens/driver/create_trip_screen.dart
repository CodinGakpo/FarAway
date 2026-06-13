import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/app_theme.dart';
import '../../models/location_point.dart';
import '../../services/api_service.dart';
import '../../widgets/live_map.dart';
import '../customer/location_picker_screen.dart';

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

  LocationPoint? _startLocation;
  LocationPoint? _endLocation;
  DateTime? _selectedDate;
  String? _selectedVehicle = 'Mini Truck';
  bool _isLoading = false;

  final List<String> _vehicles = [
    'Mini Truck',
    'Pickup Truck',
    'Medium Cargo Truck',
  ];

  @override
  void initState() {
    super.initState();
    _weightController.addListener(_updateUI);
  }

  @override
  void dispose() {
    _weightController.removeListener(_updateUI);
    _originController.dispose();
    _destinationController.dispose();
    _weightController.dispose();
    _volumeController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  Future<void> _selectStartLocation() async {
    final loc = await LocationPickerSheet.showPickup(context);
    if (loc == null || !mounted) return;
    setState(() {
      _startLocation = loc;
      _originController.text = loc.shortAddress;
    });
  }

  Future<void> _selectEndLocation() async {
    final loc = await LocationPickerSheet.showDrop(context);
    if (loc == null || !mounted) return;
    setState(() {
      _endLocation = loc;
      _destinationController.text = loc.shortAddress;
    });
  }

  double get _distanceKm {
    if (_startLocation == null || _endLocation == null) return 0;
    return _haversineKm(_startLocation!.latLng, _endLocation!.latLng);
  }

  double get _durationMin => _distanceKm > 0 ? _distanceKm * 2.4 : 0;

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  String _fmt(double km) => km >= 10
      ? '${km.toStringAsFixed(0)} km'
      : '${km.toStringAsFixed(1)} km';

  String _fmtTime(double min) {
    if (min < 60) return '${min.toStringAsFixed(0)} min';
    final h = (min / 60).floor();
    final m = (min % 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
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
    if (_startLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start location')),
      );
      return;
    }
    if (_endLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an end location')),
      );
      return;
    }

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

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
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
    final hasRoute = _startLocation != null && _endLocation != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Trip'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fallback map preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 180,
                      child: LiveMapWidget(
                        pickupLocation: _startLocation?.latLng,
                        dropLocation: _endLocation?.latLng,
                        showLogoPill: false,
                        height: 180,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Location fields card (styled like customer side)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LocationTile(
                          icon: Icons.radio_button_checked,
                          iconColor: AppColors.primary,
                          label: _startLocation?.shortAddress ?? 'Select Start Location',
                          isSet: _startLocation != null,
                          onTap: _selectStartLocation,
                        ),
                        const SizedBox(height: 1),
                        _DotConnector(),
                        const SizedBox(height: 1),
                        _LocationTile(
                          icon: Icons.location_on,
                          iconColor: AppColors.orange,
                          label: _endLocation?.shortAddress ?? 'Select End Location',
                          isSet: _endLocation != null,
                          onTap: _selectEndLocation,
                        ),
                      ],
                    ),
                  ),

                  // 3-column Info Bar (shows up when both locations are chosen)
                  if (hasRoute) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _InfoBarItem(
                            icon: Icons.straighten,
                            value: _fmt(_distanceKm),
                            label: 'Distance',
                          ),
                          _divider(),
                          _InfoBarItem(
                            icon: Icons.access_time,
                            value: _fmtTime(_durationMin),
                            label: 'Est. time',
                          ),
                          _divider(),
                          _InfoBarItem(
                            icon: Icons.inventory_2_outlined,
                            value: _weightController.text.isNotEmpty
                                ? '${_weightController.text} kg'
                                : '— kg',
                            label: 'Capacity',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Vehicle Details Form Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Vehicle Type Dropdown
                        DropdownButtonFormField<String>(
                          value: _selectedVehicle,
                          decoration: InputDecoration(
                            labelText: 'Vehicle Type',
                            prefixIcon: const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
                            fillColor: const Color(0xFFF3F4F6),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: _vehicles.map((String vehicle) {
                            return DropdownMenuItem<String>(
                              value: vehicle,
                              child: Text(vehicle),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              _selectedVehicle = newValue;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Max Weight Input
                        TextFormField(
                          controller: _weightController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Max Weight Capacity (kg)',
                            prefixIcon: const Icon(Icons.fitness_center_outlined, color: AppColors.primary),
                            fillColor: const Color(0xFFF3F4F6),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            final parsed = double.tryParse((value ?? '').trim());
                            if (parsed == null || parsed <= 0) {
                              return 'Enter valid weight capacity';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Max Volume Input
                        TextFormField(
                          controller: _volumeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Max Volume Capacity (m³)',
                            prefixIcon: const Icon(Icons.grid_3x3_outlined, color: AppColors.primary),
                            fillColor: const Color(0xFFF3F4F6),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            final parsed = double.tryParse((value ?? '').trim());
                            if (parsed == null || parsed <= 0) {
                              return 'Enter valid volume capacity';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Date picker
                        TextFormField(
                          readOnly: true,
                          controller: _dateController,
                          onTap: _pickDate,
                          decoration: InputDecoration(
                            labelText: 'Trip Date',
                            prefixIcon: const Icon(Icons.calendar_month_outlined, color: AppColors.primary),
                            hintText: 'Tap to select date',
                            fillColor: const Color(0xFFF3F4F6),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (_) {
                            if (_selectedDate == null) {
                              return 'Select a trip date';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Create Trip'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.primary.withOpacity(0.2),
    );
  }

  String _formatDate(DateTime date) {
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${monthNames[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }
}

class _InfoBarItem extends StatelessWidget {
  const _InfoBarItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isSet,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSet ? FontWeight.w600 : FontWeight.normal,
                  color: isSet ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSet)
              const Icon(Icons.check_circle, size: 18, color: AppColors.primary)
            else
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DotConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            width: 2,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 1),
            color: Colors.grey.shade300,
          ),
        ),
      ),
    );
  }
}

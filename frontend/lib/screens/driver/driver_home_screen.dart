import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/trip.dart';
import '../../services/api_service.dart';

import '../../widgets/fallback_map.dart';
import 'create_trip_screen.dart';
import 'incoming_requests_screen.dart';
import 'active_trip_dashboard.dart';

class DriverHomeTab extends StatefulWidget {
  const DriverHomeTab({super.key});

  @override
  State<DriverHomeTab> createState() => _DriverHomeTabState();
}

class _DriverHomeTabState extends State<DriverHomeTab> {
  final ApiService _apiService = ApiService();
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  Trip? _activeTrip;
  bool _isLoading = true;


  @override
  void initState() {
    super.initState();
    _loadActiveTrip();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveTrip() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final trip = await _apiService.getActiveTrip();
      if (!mounted) return;
      setState(() {
        _activeTrip = trip;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // Fail silently or set to null if backend returns error
      setState(() {
        _activeTrip = null;
        _isLoading = false;
      });
    }
  }

  void _goToCreateTrip() {
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreateTripScreen(),
      ),
    )
        .then((shouldRefresh) {
      if (shouldRefresh == true && mounted) {
        _loadActiveTrip();
      }
    });
  }

  void _goToRequests() {
    if (_activeTrip == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IncomingRequestsScreen(tripId: _activeTrip!.id),
      ),
    ).then((_) {
      if (mounted) _loadActiveTrip();
    });
  }

  void _goToActiveTrip() {
    if (_activeTrip == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveTripDashboard(trip: _activeTrip!),
      ),
    ).then((_) {
      if (mounted) _loadActiveTrip();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Fallback Map background
          FallbackMap(
            pickupAddress: _activeTrip?.origin,
            dropAddress: _activeTrip?.destination,
            showLogoPill: true,
          ),

          // 2. Sliding bottom sheet
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _activeTrip == null ? 0.28 : 0.38,
            minChildSize: 0.15,
            maxChildSize: 0.70,
            snap: true,
            snapSizes: const [0.15, 0.28, 0.38, 0.70],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Handle
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _isLoading
                          ? const SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _activeTrip == null
                              ? _buildReadyToDrive()
                              : _buildActiveTripCard(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReadyToDrive() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ready to Drive?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Create a trip to start accepting shipments',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToCreateTrip,
            child: const Text('Create Trip'),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTripCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Active Trip',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            // Status Chip (Active/Green)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Trip route summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 10, color: AppColors.primary),
                  Container(
                    width: 2,
                    height: 16,
                    color: Colors.grey.shade300,
                  ),
                  const Icon(Icons.location_on, size: 14, color: AppColors.orange),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeTrip!.origin,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _activeTrip!.destination,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Route Distance',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '250 km', // Dummy route distance or dynamically computed
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToActiveTrip,
            child: const Text('View Active Trip'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _goToRequests,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('View Requests'),
          ),
        ),
      ],
    );
  }
}

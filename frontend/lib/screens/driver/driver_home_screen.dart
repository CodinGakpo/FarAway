import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_chip.dart';
import 'create_trip_screen.dart';
import 'incoming_requests_screen.dart';
import '../auth/login_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final ApiService _apiService = ApiService();

  Trip? _activeTrip;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadActiveTrip();
  }

  Future<void> _loadActiveTrip() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final trip = await _apiService.getActiveTrip();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTrip = trip;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final errorMsg = error.toString().replaceFirst('Exception: ', '');
      debugPrint('[DriverHomeScreen] Silent active trip load connection warning: $errorMsg');
      setState(() {
        _activeTrip = null;
        _errorMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await Provider.of<AuthProvider>(context, listen: false).logout();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _goToIncomingRequests() {
    if (_activeTrip == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IncomingRequestsScreen(tripId: _activeTrip!.id),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1D9E75);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FreightShare'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 20),
                            LoadingButton(
                              label: 'Retry',
                              onPressed: _loadActiveTrip,
                              isLoading: false,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _activeTrip == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const EmptyState(
                                  message: 'No active trip',
                                  icon: Icons.route_outlined,
                                ),
                                const SizedBox(height: 12),
                                LoadingButton(
                                  label: 'Create Trip',
                                  onPressed: _goToCreateTrip,
                                  isLoading: false,
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadActiveTrip,
                          child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              const SectionHeader(title: 'Active Trip'),
                              _TripCard(trip: _activeTrip!),
                              const SizedBox(height: 24),
                              LoadingButton(
                                label: 'View Incoming Requests',
                                onPressed: _goToIncomingRequests,
                                isLoading: false,
                              ),
                            ],
                          ),
                        ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final remainingWeightProgress = _progressValue(
      trip.remainingWeight,
      trip.maxWeight,
    );
    final remainingVolumeProgress = _progressValue(
      trip.remainingVolume,
      trip.maxVolume,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.origin} → ${trip.destination}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF173B2F),
                  ),
                ),
              ),
              StatusChip(status: trip.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(trip.date),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          _MetricProgress(
            label: 'Remaining weight',
            value: trip.remainingWeight,
            maxValue: trip.maxWeight,
            progress: remainingWeightProgress,
          ),
          const SizedBox(height: 16),
          _MetricProgress(
            label: 'Remaining volume',
            value: trip.remainingVolume,
            maxValue: trip.maxVolume,
            progress: remainingVolumeProgress,
          ),
        ],
      ),
    );
  }

  double _progressValue(double remaining, double max) {
    if (max <= 0) {
      return 0;
    }
    final ratio = remaining / max;
    return ratio.clamp(0.0, 1.0);
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

    final month = monthNames[date.month - 1];
    final day = date.day.toString().padLeft(2, '0');
    return '$month $day, ${date.year}';
  }
}

class _MetricProgress extends StatelessWidget {
  const _MetricProgress({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.progress,
  });

  final String label;
  final double value;
  final double maxValue;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1D9E75);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.toStringAsFixed(1)} / ${maxValue.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF173B2F),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: progress,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(green),
          ),
        ),
      ],
    );
  }
}

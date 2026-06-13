import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/booking.dart';
import '../../providers/booking_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../widgets/live_map.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {
  Timer? _movementTimer;
  Timer? _statusTimer;

  int _step = 0;
  final int _totalSteps = 60;



  List<LatLng> _routePoints = [];
  LatLng? _truckPosition;
  bool _isLoadingRoute = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _initTracking());
  }

  Future<void> _initTracking() async {
    final booking = context.read<BookingProvider>().activeBooking;
    if (booking == null) return;

    final tripId = booking.draft.selectedTruck?.id;
    if (tripId != null) {
      try {
        final trip = await ApiService().getTrip(tripId);
        if (trip.routeCoordinates != null && trip.routeCoordinates!.isNotEmpty) {
          _routePoints = trip.routeCoordinates!
              .map((c) => LatLng(c[1], c[0]))
              .toList();
        }
      } catch (e) {
        // fallback
      }
    }

    if (_routePoints.isEmpty) {
      final pickup = booking.draft.pickup?.latLng;
      final drop = booking.draft.drop?.latLng;
      if (pickup != null && drop != null) {
        _routePoints = _buildRoute(pickup, drop, _totalSteps);
      }
    }

    if (mounted && _routePoints.isNotEmpty) {
      setState(() {
        _isLoadingRoute = false;
        _truckPosition = _routePoints.first;
      });
      _startSimulation();
    }
  }

  List<LatLng> _buildRoute(LatLng a, LatLng b, int steps) {
    return List.generate(steps + 1, (i) {
      final midLat = (a.latitude + b.latitude) / 2 + 0.015;
      final midLng = (a.longitude + b.longitude) / 2 + 0.008;
      if (i <= steps ~/ 2) {
        final s = i / (steps ~/ 2);
        return LatLng(
          a.latitude + (midLat - a.latitude) * s,
          a.longitude + (midLng - a.longitude) * s,
        );
      } else {
        final s = (i - steps ~/ 2) / (steps - steps ~/ 2);
        return LatLng(
          midLat + (b.latitude - midLat) * s,
          midLng + (b.longitude - midLng) * s,
        );
      }
    });
  }

  void _startSimulation() {
    _movementTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final booking = context.read<BookingProvider>().activeBooking;
    if (booking == null) return;

    if (_step < _totalSteps && _routePoints.isNotEmpty) {
      _step++;
      
      // Map step to an index in _routePoints array
      final double progress = _step / _totalSteps;
      int idx = (progress * (_routePoints.length - 1)).round();
      if (idx >= _routePoints.length) idx = _routePoints.length - 1;
      
      _truckPosition = _routePoints[idx];

      // Advance booking status at milestones
      final currentIdx = booking.status.index;
      if (progress > 0.12 && currentIdx < BookingStatus.driverAssigned.index) {
        context.read<BookingProvider>().advanceStatus();
      } else if (progress > 0.28 &&
          currentIdx < BookingStatus.pickupInProgress.index) {
        context.read<BookingProvider>().advanceStatus();
      } else if (progress > 0.42 &&
          currentIdx < BookingStatus.cargoLoaded.index) {
        context.read<BookingProvider>().advanceStatus();
      } else if (progress > 0.55 &&
          currentIdx < BookingStatus.inTransit.index) {
        context.read<BookingProvider>().advanceStatus();
      } else if (progress > 0.85 &&
          currentIdx < BookingStatus.nearDestination.index) {
        context.read<BookingProvider>().advanceStatus();
      }

      _updateMarkers(booking);


    } else {
      // Delivery complete
      _movementTimer?.cancel();
      _showDeliveredDialog();
    }
  }

  void _updateMarkers(Booking booking) {
    setState(() {});
  }

  void _showDeliveredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Text('🎉', style: TextStyle(fontSize: 48)),
            SizedBox(height: 8),
            Text(
              'Delivered!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: const Text(
          'Your cargo has been delivered successfully.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              context.read<BookingProvider>().completeAndArchive();
              context.read<ShipmentProvider>().reset();
              Navigator.of(ctx).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    _statusTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingProvider>().activeBooking;
    if (booking == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final progress = _step / _totalSteps;

    return Scaffold(
      body: Stack(
        children: [
          if (_isLoadingRoute)
            const Center(child: CircularProgressIndicator())
          else
            // Map
            LiveMapWidget(
            pickupLocation: booking.draft.pickup?.latLng,
            dropLocation: booking.draft.drop?.latLng,
            routePoints: _routePoints,
            truckPosition: _truckPosition,
            truckLabel: booking.draft.selectedTruck?.driverName ?? 'Driver',
            truckSublabel: booking.draft.selectedTruck?.truckNumber,
            showLogoPill: false,
          ),

          // Top back button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Material(
                      color: AppColors.surface,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.arrow_back,
                              size: 22, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TrackingPanel(
              booking: booking,
              progress: progress,
              truckPosition: _truckPosition,
              pulseAnim: _pulseAnim,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _TrackingPanel extends StatelessWidget {
  const _TrackingPanel({
    required this.booking,
    required this.progress,
    required this.truckPosition,
    required this.pulseAnim,
  });

  final Booking booking;
  final double progress;
  final LatLng? truckPosition;
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    final truck = booking.draft.selectedTruck;

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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Status row
              Row(
                children: [
                  AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (context, child) => Transform.scale(
                      scale: pulseAnim.value,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: booking.status ==
                                  BookingStatus.delivered
                              ? const Color(0xFFEAF7F2)
                              : AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          booking.status == BookingStatus.delivered
                              ? Icons.check_circle
                              : Icons.local_shipping_rounded,
                          size: 24,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.status.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          booking.status.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#${booking.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress bar
              _ProgressStepper(status: booking.status),

              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 14),

              // Driver info
              if (truck != null)
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.person,
                          size: 24, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            truck.driverName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${truck.truckNumber}  •  ${truck.type}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ActionButton(
                      icon: Icons.call,
                      onTap: () => _showMockAction(context, 'Calling ${truck.driverName}…'),
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.chat_bubble_outline,
                      onTap: () => _showMockAction(context, 'Opening chat…'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMockAction(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({required this.status});
  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final statuses = BookingStatus.values;
    return Column(
      children: [
        // Step dots
        Row(
          children: List.generate(statuses.length, (i) {
            final isCompleted = i <= status.index;
            final isCurrent = i == status.index;
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: isCurrent ? 12 : 8,
                    height: isCurrent ? 12 : 8,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppColors.primary
                          : AppColors.border,
                      shape: BoxShape.circle,
                      border: isCurrent
                          ? Border.all(
                              color: AppColors.primary, width: 2)
                          : null,
                    ),
                  ),
                  if (i < statuses.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < status.index
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        // Current label
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${status.index + 1} of ${statuses.length}: ${status.label}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.primaryLight,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
        ),
      );
}

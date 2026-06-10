import 'package:flutter/material.dart';

import '../../models/shipment_request.dart';
import '../../models/trip.dart';
import '../../services/api_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_chip.dart';

class ActiveTripDashboard extends StatefulWidget {
  const ActiveTripDashboard({super.key, required this.trip});

  final Trip trip;

  @override
  State<ActiveTripDashboard> createState() => _ActiveTripDashboardState();
}

class _ActiveTripDashboardState extends State<ActiveTripDashboard> {
  final ApiService _apiService = ApiService();

  List<ShipmentRequest> _shipments = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _busyShipmentId;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _loadShipments();
  }

  Future<void> _loadShipments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final shipments = await _apiService.getTripShipments(widget.trip.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _shipments = shipments
            .where((shipment) => shipment.status != 'PENDING' && shipment.status != 'REJECTED')
            .toList();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateShipmentStatus(ShipmentRequest shipment, String status) async {
    setState(() {
      _busyShipmentId = shipment.id;
      _busyAction = status;
    });

    try {
      await _apiService.updateShipmentStatus(shipment.id, status);
      if (!mounted) {
        return;
      }
      await _loadShipments();
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
          _busyShipmentId = null;
          _busyAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1D9E75);

    return RefreshIndicator(
      onRefresh: _loadShipments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _TripSummaryCard(trip: widget.trip),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Accepted Shipments'),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
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
                      onPressed: _loadShipments,
                      isLoading: false,
                    ),
                  ],
                ),
              ),
            )
          else if (_shipments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                message: 'No accepted shipments yet',
                icon: Icons.inventory_2_outlined,
              ),
            )
          else
            ..._shipments.map(
              (shipment) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ShipmentCard(
                  shipment: shipment,
                  isLoading: _busyShipmentId == shipment.id,
                  busyAction: _busyAction,
                  onMarkPickedUp: shipment.status == 'ACCEPTED'
                      ? () => _updateShipmentStatus(shipment, 'PICKED_UP')
                      : null,
                  onMarkDelivered: shipment.status == 'PICKED_UP'
                      ? () => _updateShipmentStatus(shipment, 'DELIVERED')
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: Colors.transparent,
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Pull to refresh shipments',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final weightUsed = _usedValue(trip.maxWeight, trip.remainingWeight);
    final volumeUsed = _usedValue(trip.maxVolume, trip.remainingVolume);
    final driverName = trip.driverName?.trim().isNotEmpty == true
        ? trip.driverName!
        : trip.driverId;

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
          Text(
            '${trip.origin} → ${trip.destination}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173B2F),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(trip.date),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Driver: $driverName',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          _CapacityRow(
            label: 'Weight used',
            used: weightUsed,
            max: trip.maxWeight,
            suffix: 'kg',
          ),
          const SizedBox(height: 16),
          _CapacityRow(
            label: 'Volume used',
            used: volumeUsed,
            max: trip.maxVolume,
            suffix: 'cu ft',
          ),
        ],
      ),
    );
  }

  double _usedValue(double maxValue, double remainingValue) {
    final used = maxValue - remainingValue;
    if (maxValue <= 0) {
      return 0;
    }
    return used.clamp(0, maxValue);
  }

  String _formatDate(DateTime date) {
    const months = [
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

    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }
}

class _CapacityRow extends StatelessWidget {
  const _CapacityRow({
    required this.label,
    required this.used,
    required this.max,
    required this.suffix,
  });

  final String label;
  final double used;
  final double max;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1D9E75);
    final progress = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${used.toStringAsFixed(0)} / ${max.toStringAsFixed(0)} $suffix',
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

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.shipment,
    required this.isLoading,
    required this.busyAction,
    required this.onMarkPickedUp,
    required this.onMarkDelivered,
  });

  final ShipmentRequest shipment;
  final bool isLoading;
  final String? busyAction;
  final VoidCallback? onMarkPickedUp;
  final VoidCallback? onMarkDelivered;

  @override
  Widget build(BuildContext context) {
    final cargoMeta = _cargoMeta(shipment.cargoCategory);
    final showPickedUpButton = shipment.status == 'ACCEPTED';
    final showDeliveredButton = shipment.status == 'PICKED_UP';
    final canShowActions = showPickedUpButton || showDeliveredButton;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${shipment.pickupLocation} → ${shipment.dropoffLocation}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF173B2F),
                    ),
                  ),
                ),
                _GreenStatusChip(status: shipment.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _InfoChip(label: 'Cargo', value: cargoMeta.label, icon: cargoMeta.icon),
                _InfoChip(label: 'Weight', value: '${shipment.weight.toStringAsFixed(1)} kg'),
                _InfoChip(label: 'Volume', value: '${shipment.volume.toStringAsFixed(1)} cu ft'),
              ],
            ),
            const SizedBox(height: 12),
            if (canShowActions) ...[
              Row(
                children: [
                  if (showPickedUpButton)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading && busyAction == 'PICKED_UP'
                            ? null
                            : onMarkPickedUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D9E75),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isLoading && busyAction == 'PICKED_UP'
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Mark Picked Up'),
                      ),
                    ),
                  if (showPickedUpButton) const SizedBox(width: 12),
                  if (showDeliveredButton)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading && busyAction == 'DELIVERED'
                            ? null
                            : onMarkDelivered,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D9E75),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isLoading && busyAction == 'DELIVERED'
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Mark Delivered'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  _CargoMeta _cargoMeta(String cargoCategory) {
    switch (cargoCategory.toLowerCase()) {
      case 'fragile':
        return const _CargoMeta(Icons.warning_amber_outlined, 'Fragile');
      case 'perishable':
        return const _CargoMeta(Icons.eco_outlined, 'Perishable');
      default:
        return const _CargoMeta(Icons.inventory_2_outlined, 'General');
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: icon == null ? null : Icon(icon, size: 18, color: const Color(0xFF1D9E75)),
      label: Text('$label: $value'),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
    );
  }
}

class _GreenStatusChip extends StatelessWidget {
  const _GreenStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        status,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      backgroundColor: const Color(0xFF1D9E75),
      side: BorderSide.none,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _CargoMeta {
  const _CargoMeta(this.icon, this.label);

  final IconData icon;
  final String label;
}

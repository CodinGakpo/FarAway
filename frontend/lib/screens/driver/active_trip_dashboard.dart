import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/shipment_request.dart';
import '../../models/trip.dart';
import '../../services/api_service.dart';
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
  
  // Real-time capacity computation based on accepted/picked_up/delivered loads
  double _weightUsed = 0.0;

  @override
  void initState() {
    super.initState();
    _loadShipments();
  }

  Future<void> _loadShipments() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final shipments = await _apiService.getTripShipments(widget.trip.id);
      if (!mounted) return;

      // Filter out pending/rejected
      final activeShipments = shipments
          .where((s) => s.status != 'PENDING' && s.status != 'REJECTED')
          .toList();

      // Compute capacity used
      double wUsed = 0.0;
      for (final s in activeShipments) {
        if (s.status == 'ACCEPTED' || s.status == 'PICKED_UP' || s.status == 'DELIVERED') {
          wUsed += s.weight;
        }
      }

      setState(() {
        _shipments = activeShipments;
        _weightUsed = wUsed;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _updateShipmentStatus(ShipmentRequest shipment, String newStatus) async {
    setState(() {
      _busyShipmentId = shipment.id;
      _busyAction = newStatus;
    });

    try {
      await _apiService.updateShipmentStatus(shipment.id, newStatus);
      if (!mounted) return;
      await _loadShipments();
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
          _busyShipmentId = null;
          _busyAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Volume calculation fallback using total capacity ratios
    final double weightUsed = _weightUsed;
    final double volumeUsed = _shipments.fold(0.0, (sum, s) => sum + s.volume);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Active Trip'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadShipments,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. Route Summary Card
              _buildRouteSummaryCard(),
              const SizedBox(height: 16),

              // 2. Capacity Progress Card
              _buildCapacityCard(weightUsed, volumeUsed),
              const SizedBox(height: 24),

              // 3. Accepted Shipments section
              const Text(
                'ACCEPTED SHIPMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadShipments,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (_shipments.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 12),
                      Text(
                        'No accepted shipments yet',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _shipments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final shipment = _shipments[index];
                    final isBusy = _busyShipmentId == shipment.id;

                    return _ShipmentCard(
                      shipment: shipment,
                      isBusy: isBusy,
                      busyAction: _busyAction,
                      onUpdateStatus: (status) => _updateShipmentStatus(shipment, status),
                    );
                  },
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 8, color: AppColors.primary),
                  Container(
                    width: 2,
                    height: 20,
                    color: Colors.grey.shade300,
                  ),
                  const Icon(Icons.location_on, size: 12, color: AppColors.orange),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.trip.origin,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.trip.destination,
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
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoItem(
                icon: Icons.straighten,
                value: '250 km',
                label: 'Distance',
              ),
              _divider(),
              _InfoItem(
                icon: Icons.access_time,
                value: '4h 30m',
                label: 'Est. time',
              ),
              _divider(),
              _InfoItem(
                icon: Icons.calendar_month_outlined,
                value: _formatDate(widget.trip.date),
                label: 'Trip Date',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityCard(double weightUsed, double volumeUsed) {
    final weightLimit = widget.trip.maxWeight > 0 ? widget.trip.maxWeight : 1000.0;
    final volumeLimit = widget.trip.maxVolume > 0 ? widget.trip.maxVolume : 8.0;

    final weightProgress = (weightUsed / weightLimit).clamp(0.0, 1.0);
    final volumeProgress = (volumeUsed / volumeLimit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remaining Capacity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Weight indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Weight capacity',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  Text(
                    '${weightUsed.toStringAsFixed(0)} / ${weightLimit.toStringAsFixed(0)} kg',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: weightProgress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF3F4F6),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Volume indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Volume capacity',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  Text(
                    '${volumeUsed.toStringAsFixed(1)} / ${volumeLimit.toStringAsFixed(1)} m³',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: volumeProgress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF3F4F6),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }

  String _formatDate(DateTime date) {
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${monthNames[date.month - 1]} ${date.day}';
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.shipment,
    required this.isBusy,
    required this.busyAction,
    required this.onUpdateStatus,
  });

  final ShipmentRequest shipment;
  final bool isBusy;
  final String? busyAction;
  final ValueChanged<String> onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final isAccepted = shipment.status == 'ACCEPTED';

    final isDelivered = shipment.status == 'DELIVERED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${shipment.id}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              StatusChip(status: shipment.status),
            ],
          ),
          const SizedBox(height: 12),

          // Route dots
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 8, color: AppColors.primary),
                  Container(
                    width: 2,
                    height: 14,
                    color: Colors.grey.shade300,
                  ),
                  const Icon(Icons.location_on, size: 12, color: AppColors.orange),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shipment.pickupLocation,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      shipment.dropoffLocation,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Info Row
          Row(
            children: [
              _CargoChip(
                icon: _cargoIcon(shipment.cargoCategory),
                label: shipment.cargoCategory,
              ),
              const SizedBox(width: 8),
              _CargoChip(
                icon: Icons.fitness_center_outlined,
                label: '${shipment.weight.toStringAsFixed(0)} kg',
              ),
            ],
          ),

          // Action buttons
          if (!isDelivered) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: isAccepted
                  ? OutlinedButton(
                      onPressed: isBusy ? null : () => onUpdateStatus('PICKED_UP'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isBusy && busyAction == 'PICKED_UP'
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            )
                          : const Text('Mark Picked Up'),
                    )
                  : ElevatedButton(
                      onPressed: isBusy ? null : () => onUpdateStatus('DELIVERED'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isBusy && busyAction == 'DELIVERED'
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
        ],
      ),
    );
  }

  IconData _cargoIcon(String category) {
    switch (category.toLowerCase()) {
      case 'fragile':
        return Icons.warning_amber_outlined;
      case 'perishable':
        return Icons.eco_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }
}

class _CargoChip extends StatelessWidget {
  const _CargoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
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
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

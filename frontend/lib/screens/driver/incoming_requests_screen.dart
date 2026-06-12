import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/shipment_request.dart';
import '../../services/api_service.dart';
import '../../widgets/status_chip.dart';

class IncomingRequestsScreen extends StatefulWidget {
  const IncomingRequestsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends State<IncomingRequestsScreen> {
  final ApiService _apiService = ApiService();

  List<ShipmentRequest> _requests = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _loadingShipmentId;
  String? _loadingAction;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _apiService.getIncomingRequests(widget.tripId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _acceptRequest(ShipmentRequest request) async {
    await _performAction(request.id, 'accept', () async {
      await _apiService.acceptRequest(request.id);
    });
  }

  Future<void> _rejectRequest(ShipmentRequest request) async {
    await _performAction(request.id, 'reject', () async {
      await _apiService.rejectRequest(request.id);
    });
  }

  Future<void> _performAction(
    String shipmentId,
    String action,
    Future<void> Function() apiCall,
  ) async {
    setState(() {
      _loadingShipmentId = shipmentId;
      _loadingAction = action;
    });

    try {
      await apiCall();
      if (!mounted) return;
      await _loadRequests();
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
          _loadingShipmentId = null;
          _loadingAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shipment Requests'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRequests,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 80),
                        Icon(Icons.error_outline, size: 64, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _loadRequests,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : _requests.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 160),
                            Icon(
                              Icons.local_shipping_outlined,
                              size: 72,
                              color: Color(0xFFD1D5DB),
                            ),
                            SizedBox(height: 16),
                            Center(
                              child: Text(
                                'No pending requests',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(height: 6),
                            Center(
                              child: Text(
                                'When shippers book your trip, requests will appear here.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final request = _requests[index];
                            final isAcceptLoading = _loadingShipmentId == request.id && _loadingAction == 'accept';
                            final isRejectLoading = _loadingShipmentId == request.id && _loadingAction == 'reject';

                            return _RequestCard(
                              request: request,
                              isAcceptLoading: isAcceptLoading,
                              isRejectLoading: isRejectLoading,
                              onAccept: request.status == 'PENDING' ? () => _acceptRequest(request) : null,
                              onReject: request.status == 'PENDING' ? () => _rejectRequest(request) : null,
                            );
                          },
                        ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isAcceptLoading,
    required this.isRejectLoading,
    required this.onAccept,
    required this.onReject,
  });

  final ShipmentRequest request;
  final bool isAcceptLoading;
  final bool isRejectLoading;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final cargoIcon = _cargoIcon(request.cargoCategory);

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
          // Header: ID and status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${request.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Just now', // Standard mock time
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 16),

          // Route with vertical lines
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
                      request.pickupLocation,
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
                      request.dropoffLocation,
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

          // Cargo details & Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _CargoChip(
                      icon: cargoIcon,
                      label: request.cargoCategory,
                    ),
                    _CargoChip(
                      icon: Icons.fitness_center_outlined,
                      label: '${request.weight.toStringAsFixed(0)} kg',
                    ),
                    _CargoChip(
                      icon: Icons.grid_3x3_outlined,
                      label: '${request.volume.toStringAsFixed(1)} m³',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '₹${(request.price ?? 0.0).toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          if (request.status == 'PENDING') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                // Decline Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: isRejectLoading ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(0, 48),
                    ),
                    child: isRejectLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
                            ),
                          )
                        : const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                // Accept Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: isAcceptLoading ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(0, 48),
                    ),
                    child: isAcceptLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
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
      case 'electronics':
        return Icons.devices_outlined;
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
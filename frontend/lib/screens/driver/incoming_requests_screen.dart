import 'package:flutter/material.dart';

import '../../models/shipment_request.dart';
import '../../services/api_service.dart';
import '../../widgets/empty_state.dart';
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _apiService.getIncomingRequests(widget.tripId);
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = requests;
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
    Future<void> Function() request,
  ) async {
    setState(() {
      _loadingShipmentId = shipmentId;
      _loadingAction = action;
    });

    try {
      await request();
      if (!mounted) {
        return;
      }
      await _loadRequests();
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
          _loadingShipmentId = null;
          _loadingAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incoming Requests')),
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
                            OutlinedButton(
                              onPressed: _loadRequests,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadRequests,
                      child: _requests.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                EmptyState(
                                  message: 'No incoming requests',
                                  icon: Icons.inbox_outlined,
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
                                return _RequestCard(
                                  request: request,
                                  isAcceptLoading: _loadingShipmentId == request.id &&
                                      _loadingAction == 'accept',
                                  isRejectLoading: _loadingShipmentId == request.id &&
                                      _loadingAction == 'reject',
                                  onAccept: request.status == 'PENDING'
                                      ? () => _acceptRequest(request)
                                      : null,
                                  onReject: request.status == 'PENDING'
                                      ? () => _rejectRequest(request)
                                      : null,
                                );
                              },
                            ),
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
    final cargoMeta = _cargoMeta(request.cargoCategory);

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
                    '${request.pickupLocation} → ${request.dropoffLocation}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF173B2F),
                    ),
                  ),
                ),
                StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _InfoChip(label: 'Weight', value: '${request.weight.toStringAsFixed(1)} kg'),
                _InfoChip(label: 'Volume', value: '${request.volume.toStringAsFixed(1)} cu ft'),
                _CargoChip(icon: cargoMeta.icon, label: cargoMeta.label),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '₹${(request.price ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1D9E75),
              ),
            ),
            if (request.status == 'PENDING') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isRejectLoading ? null : onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isRejectLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                              ),
                            )
                          : const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isAcceptLoading ? null : onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D9E75),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
    );
  }
}

class _CargoChip extends StatelessWidget {
  const _CargoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: const Color(0xFF1D9E75)),
      label: Text(label),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
    );
  }
}

class _CargoMeta {
  const _CargoMeta(this.icon, this.label);

  final IconData icon;
  final String label;
}
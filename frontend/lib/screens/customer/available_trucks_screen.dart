import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/shipment_draft.dart';
import '../../models/trip.dart';
import '../../providers/shipment_provider.dart';
import '../../services/api_service.dart';
import 'booking_confirmation_screen.dart';

class AvailableTrucksScreen extends StatefulWidget {
  const AvailableTrucksScreen({super.key});

  @override
  State<AvailableTrucksScreen>
      createState() => _AvailableTrucksScreenState();
}

class _AvailableTrucksScreenState extends State<AvailableTrucksScreen> {
  List<Trip> _trips = const [];
  Trip? _selected;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final trips = await ApiService().getActiveTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _selected = trips.isNotEmpty ? trips.first : null;
        _isLoading = false;
      });
      if (_selected != null) {
        context.read<ShipmentProvider>().setSelectedTrip(_selected!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _selectTrip(Trip trip) {
    setState(() => _selected = trip);
    context.read<ShipmentProvider>().setSelectedTrip(trip);
  }

  void _book() {
    if (_selected == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookingConfirmationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ShipmentProvider>().draft;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Available Trips'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _ErrorView(
                  message: _errorMessage!,
                  onRetry: _loadTrips,
                )
              : _trips.isEmpty
                  ? const _EmptyView()
                  : Column(
                      children: [
                        _RouteSummaryStrip(draft: draft),
                        const Divider(height: 1, color: AppColors.border),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadTrips,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _trips.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => _TripCard(
                                trip: _trips[i],
                                draft: draft,
                                isSelected: _selected?.id == _trips[i].id,
                                onTap: () => _selectTrip(_trips[i]),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
      bottomNavigationBar: _selected == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Estimated Total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                '₹${draft.estimatedPrice.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Final price set by AI',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _book,
                      child: const Text('Book This Trip'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _RouteSummaryStrip extends StatelessWidget {
  const _RouteSummaryStrip({required this.draft});
  final ShipmentDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.pickup?.shortAddress ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${draft.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Text(
                        '  •  ',
                        style:
                            TextStyle(color: AppColors.textSecondary),
                      ),
                      Flexible(
                        child: Text(
                          draft.drop?.shortAddress ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.draft,
    required this.isSelected,
    required this.onTap,
  });

  final Trip trip;
  final ShipmentDraft draft;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estimatedPrice = draft.estimatedPrice;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.local_shipping_rounded,
                    size: 28,
                    color: isSelected
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trip.origin} → ${trip.destination}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${trip.remainingWeight.toStringAsFixed(0)} kg · '
                        '${trip.remainingVolume.toStringAsFixed(1)} m³ available',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${estimatedPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'estimate',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            Row(
              children: [
                _Tag(
                  icon: Icons.calendar_today_outlined,
                  label: _fmtDate(trip.date),
                  color: AppColors.orange,
                ),
                const SizedBox(width: 10),
                _Tag(
                  icon: Icons.scale_outlined,
                  label: 'Max ${trip.maxWeight.toStringAsFixed(0)} kg',
                  color: AppColors.primary,
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hr = (h % 12 == 0 ? 12 : h % 12).toString();
    return '${d.day} ${months[d.month - 1]}, $hr:$m $ampm';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      );
}

// ──────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.wifi_off_rounded,
              size: 64, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 72, color: Color(0xFFD1D5DB)),
            SizedBox(height: 16),
            Text(
              'No active trips found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'No drivers have active trips matching\nyour route right now.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

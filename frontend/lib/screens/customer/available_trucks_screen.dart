import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/truck_option.dart';
import '../../providers/shipment_provider.dart';
import '../../services/mock_data_service.dart';
import 'booking_confirmation_screen.dart';

class AvailableTrucksScreen extends StatefulWidget {
  const AvailableTrucksScreen({super.key});

  @override
  State<AvailableTrucksScreen> createState() =>
      _AvailableTrucksScreenState();
}

class _AvailableTrucksScreenState extends State<AvailableTrucksScreen> {
  TruckOption? _selected;

  @override
  void initState() {
    super.initState();
    _selected = MockDataService.trucks.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShipmentProvider>().selectTruck(_selected!);
    });
  }

  void _selectTruck(TruckOption truck) {
    setState(() => _selected = truck);
    context.read<ShipmentProvider>().selectTruck(truck);
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
    final distance = draft.distanceKm;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Available Trucks'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          // Route summary strip
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Row(
              children: [
                _RoutePin(color: AppColors.primary),
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
                              '${distance.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const Text(
                              '  •  ',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            Text(
                              draft.drop?.shortAddress ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                _RoutePin(color: AppColors.orange),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: MockDataService.trucks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final truck = MockDataService.trucks[i];
                final isSelected = _selected?.id == truck.id;
                final price = truck.estimatedTotal(distance);
                return _TruckCard(
                  truck: truck,
                  price: price,
                  isSelected: isSelected,
                  onTap: () => _selectTruck(truck),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Estimate',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '₹${_selected!.estimatedTotal(distance).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      _PriceBreakdown(truck: _selected!, distanceKm: distance),
                    ],
                  ),
                ),
              ElevatedButton(
                onPressed: _selected != null ? _book : null,
                child: const Text('Book Shipment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _RoutePin extends StatelessWidget {
  const _RoutePin({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _TruckCard extends StatelessWidget {
  const _TruckCard({
    required this.truck,
    required this.price,
    required this.isSelected,
    required this.onTap,
  });

  final TruckOption truck;
  final double price;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                // Truck icon container
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
                        truck.type,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        truck.capacityLabel,
                        style: const TextStyle(
                          fontSize: 13,
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
                      '₹${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '₹${truck.pricePerKm.toStringAsFixed(0)}/km',
                      style: const TextStyle(
                        fontSize: 11,
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
                  icon: Icons.access_time,
                  label: truck.pickupEta,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 10),
                _Tag(
                  icon: Icons.star_rounded,
                  label: '${truck.rating} (${truck.reviewCount})',
                  color: const Color(0xFFF59E0B),
                ),
                const Spacer(),
                if (isSelected)
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
            ),
            const SizedBox(height: 8),
            Text(
              truck.description,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
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

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown(
      {required this.truck, required this.distanceKm});
  final TruckOption truck;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBreakdown(context),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'View breakdown',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(Icons.info_outline,
              size: 14, color: AppColors.primary),
        ],
      ),
    );
  }

  void _showBreakdown(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Price Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _Row('Base price', '₹${truck.basePrice.toStringAsFixed(0)}'),
            _Row(
              'Distance charge',
              '${distanceKm.toStringAsFixed(1)} km × ₹${truck.pricePerKm.toStringAsFixed(0)}/km',
            ),
            _Row(
              '',
              '= ₹${(distanceKm * truck.pricePerKm).toStringAsFixed(0)}',
            ),
            const Divider(height: 24, color: AppColors.border),
            _Row(
              'Total',
              '₹${truck.estimatedTotal(distanceKm).toStringAsFixed(0)}',
              bold: true,
            ),
            const SizedBox(height: 8),
            const Text(
              '* Final price may vary based on actual weight, distance and tolls.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal,
                )),
            Text(value,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                )),
          ],
        ),
      );
}

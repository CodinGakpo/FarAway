import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/booking_provider.dart';
import '../../providers/shipment_provider.dart';
import 'tracking_screen.dart';

class BookingConfirmationScreen extends StatefulWidget {
  const BookingConfirmationScreen({super.key});

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState
    extends State<BookingConfirmationScreen> {
  bool _isConfirming = false;

  Future<void> _confirm() async {
    setState(() => _isConfirming = true);
    try {
      final draft = context.read<ShipmentProvider>().draft;
      await context.read<BookingProvider>().createBooking(draft);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const TrackingScreen()),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConfirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ShipmentProvider>().draft;
    final truck = draft.selectedTruck;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Confirm Booking'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Route card
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeader(
                    icon: Icons.route, label: 'Route Summary'),
                const SizedBox(height: 14),
                _RouteRow(
                  icon: Icons.radio_button_checked,
                  iconColor: AppColors.primary,
                  label: 'Pickup',
                  address: draft.pickup?.address ?? '—',
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 9),
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
                ),
                _RouteRow(
                  icon: Icons.location_on,
                  iconColor: AppColors.orange,
                  label: 'Drop',
                  address: draft.drop?.address ?? '—',
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatChip(
                      label: '${draft.distanceKm.toStringAsFixed(1)} km',
                      sublabel: 'Distance',
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      label: _fmtTime(draft.durationMin),
                      sublabel: 'Est. time',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Cargo card
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeader(
                    icon: Icons.inventory_2, label: 'Cargo Details'),
                const SizedBox(height: 14),
                _InfoRow('Cargo name', draft.cargoName),
                _InfoRow('Category', draft.cargoCategory),
                _InfoRow('Weight', '${draft.weightKg} kg'),
                if (draft.volumeCm3 > 0)
                  _InfoRow('Volume',
                      '${draft.volumeCm3.toStringAsFixed(0)} cm³'),
                if (draft.declaredValue > 0)
                  _InfoRow('Declared value',
                      '₹${draft.declaredValue.toStringAsFixed(0)}'),
                if (draft.specialInstructions.isNotEmpty)
                  _InfoRow('Instructions', draft.specialInstructions),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Truck card
          if (truck != null) ...[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(
                      icon: Icons.local_shipping, label: 'Assigned Truck'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.local_shipping_rounded,
                            size: 26, color: AppColors.primary),
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
                            Text(
                              truck.capacityLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow('Driver', truck.driverName),
                  _InfoRow('Truck No.', truck.truckNumber),
                  _InfoRow('Rating', '⭐ ${truck.rating} (${truck.reviewCount} reviews)'),
                  _InfoRow('Pickup ETA', truck.pickupEta),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Pricing card
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeader(
                    icon: Icons.receipt, label: 'Pricing'),
                const SizedBox(height: 14),
                if (truck != null) ...[
                  _PriceRow('Base price', '₹${truck.basePrice.toStringAsFixed(0)}'),
                  _PriceRow(
                    'Distance charge',
                    '₹${(draft.distanceKm * truck.pricePerKm).toStringAsFixed(0)}',
                  ),
                  const Divider(height: 20, color: AppColors.border),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '₹${draft.estimatedPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ElevatedButton(
            onPressed: _isConfirming ? null : _confirm,
            child: _isConfirming
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Confirm Booking'),
          ),
        ),
      ),
    );
  }

  String _fmtTime(double min) {
    if (min < 60) return '${min.toStringAsFixed(0)} min';
    final h = (min / 60).floor();
    final m = (min % 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.border),
          ),
        ),
        child: child,
      );
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
            Text(value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                )),
          ],
        ),
      );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.sublabel});
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

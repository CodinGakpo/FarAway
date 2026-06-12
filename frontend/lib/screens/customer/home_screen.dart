import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/location_point.dart';
import '../../providers/booking_provider.dart';
import '../../providers/shipment_provider.dart';

import 'location_picker_screen.dart';
import 'shipment_details_screen.dart';
import 'tracking_screen.dart';
import '../../widgets/fallback_map.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _recenter() {
    // No-op fallback
  }

  void _updateMapOverlays(
      LocationPoint? pickup, LocationPoint? drop) {
    // No-op fallback
  }



  Future<void> _selectPickup() async {
    final loc = await LocationPickerSheet.showPickup(context);
    if (loc == null || !mounted) return;
    context.read<ShipmentProvider>().setPickup(loc);
    final drop = context.read<ShipmentProvider>().draft.drop;
    _updateMapOverlays(loc, drop);
  }

  Future<void> _selectDrop() async {
    final loc = await LocationPickerSheet.showDrop(context);
    if (loc == null || !mounted) return;
    context.read<ShipmentProvider>().setDrop(loc);
    final pickup = context.read<ShipmentProvider>().draft.pickup;
    _updateMapOverlays(pickup, loc);
  }

  void _proceed() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ShipmentDetailsScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingProvider>().activeBooking;
    final hasActive = context.watch<BookingProvider>().hasActiveBooking;

    return Scaffold(
      body: Stack(
        children: [
          Consumer<ShipmentProvider>(
            builder: (context, shipmentProv, _) {
              final draft = shipmentProv.draft;
              return FallbackMap(
                pickupAddress: draft.pickup?.shortAddress,
                dropAddress: draft.drop?.shortAddress,
                showLogoPill: false,
              );
            },
          ),

          // Top overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 12,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_shipping,
                                size: 16, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'FarAway Cargo',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Active shipment banner
          if (hasActive && booking != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 68, 16, 0),
                  child: _ActiveBanner(
                    booking: booking,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TrackingScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Recenter button
          Positioned(
            right: 16,
            bottom: 240,
            child: _RecenterButton(onPressed: _recenter),
          ),

          // Bottom sheet
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.32,
            minChildSize: 0.14,
            maxChildSize: 0.72,
            snap: true,
            snapSizes: const [0.14, 0.32, 0.72],
            builder: (context, scrollController) =>
                _BottomSheet(
              scrollController: scrollController,
              onSelectPickup: _selectPickup,
              onSelectDrop: _selectDrop,
              onContinue: _proceed,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.booking, required this.onTap});
  final dynamic booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_shipping,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.status.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Tap to track your shipment',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: AppColors.shadow,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.my_location, size: 22, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({
    required this.scrollController,
    required this.onSelectPickup,
    required this.onSelectDrop,
    required this.onContinue,
  });

  final ScrollController scrollController;
  final VoidCallback onSelectPickup;
  final VoidCallback onSelectDrop;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ShipmentProvider>().draft;
    final hasRoute = draft.pickup != null && draft.drop != null;

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
              padding: const EdgeInsets.symmetric(vertical: 10),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Where to?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 14),

                // Pickup tile
                _LocationTile(
                  icon: Icons.radio_button_checked,
                  iconColor: AppColors.primary,
                  label: draft.pickup?.shortAddress ?? 'Select Pickup Location',
                  isSet: draft.pickup != null,
                  onTap: onSelectPickup,
                ),
                const SizedBox(height: 1),
                _DotConnector(),
                const SizedBox(height: 1),

                // Drop tile
                _LocationTile(
                  icon: Icons.location_on,
                  iconColor: AppColors.orange,
                  label: draft.drop?.shortAddress ?? 'Select Drop Location',
                  isSet: draft.drop != null,
                  onTap: onSelectDrop,
                ),

                if (hasRoute) ...[
                  const SizedBox(height: 16),
                  _RouteInfo(draft: draft),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onContinue,
                      child: const Text('Continue'),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isSet,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      isSet ? FontWeight.w600 : FontWeight.normal,
                  color: isSet
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSet)
              const Icon(Icons.check_circle,
                  size: 18, color: AppColors.primary)
            else
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DotConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
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
    );
  }
}

class _RouteInfo extends StatelessWidget {
  const _RouteInfo({required this.draft});
  final dynamic draft;

  String _fmt(double km) => km >= 10
      ? '${km.toStringAsFixed(0)} km'
      : '${km.toStringAsFixed(1)} km';

  String _fmtTime(double min) {
    if (min < 60) return '${min.toStringAsFixed(0)} min';
    final h = (min / 60).floor();
    final m = (min % 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _InfoChip(
            icon: Icons.straighten,
            label: _fmt(draft.distanceKm),
            sublabel: 'Distance',
          ),
          const _Divider(),
          _InfoChip(
            icon: Icons.access_time,
            label: _fmtTime(draft.durationMin),
            sublabel: 'Est. time',
          ),
          const _Divider(),
          _InfoChip(
            icon: Icons.currency_rupee,
            label: 'from ₹${(draft.distanceKm * 15 + 800).toStringAsFixed(0)}',
            sublabel: 'Est. price',
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(
      {required this.icon, required this.label, required this.sublabel});
  final IconData icon;
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              sublabel,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: AppColors.primary.withOpacity(0.2),
      );
}

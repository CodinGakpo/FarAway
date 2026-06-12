import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/location_point.dart';
import '../../services/mock_data_service.dart';

enum _PickerMode { pickup, drop }

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet._({required this.mode});

  final _PickerMode mode;

  static Future<LocationPoint?> showPickup(BuildContext context) =>
      showModalBottomSheet<LocationPoint>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            const LocationPickerSheet._(mode: _PickerMode.pickup),
      );

  static Future<LocationPoint?> showDrop(BuildContext context) =>
      showModalBottomSheet<LocationPoint>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            const LocationPickerSheet._(mode: _PickerMode.drop),
      );

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  String _query = '';

  List<LocationPoint> get _locations => widget.mode == _PickerMode.pickup
      ? MockDataService.pickupLocations
      : MockDataService.dropLocations;

  List<LocationPoint> get _filtered => _query.isEmpty
      ? _locations
      : _locations
          .where((l) =>
              l.address.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  @override
  Widget build(BuildContext context) {
    final isPickup = widget.mode == _PickerMode.pickup;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _Handle(),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPickup ? 'Select Pickup Location' : 'Select Drop Location',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search location...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setState(() => _query = ''),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: AppColors.border,
                  indent: 56,
                ),
                itemBuilder: (context, i) {
                  final loc = _filtered[i];
                  final isCurrent = i == 0 && _query.isEmpty;
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.primaryLight
                            : const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCurrent
                            ? Icons.my_location
                            : isPickup
                                ? Icons.radio_button_checked
                                : Icons.location_on,
                        size: 18,
                        color: isCurrent
                            ? AppColors.primary
                            : isPickup
                                ? AppColors.primary
                                : AppColors.orange,
                      ),
                    ),
                    title: Text(
                      loc.shortAddress,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      loc.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(loc),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
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
      );
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/location_point.dart';
import '../../services/location_service.dart';

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
        builder: (_) => const LocationPickerSheet._(mode: _PickerMode.drop),
      );

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  // Session token for this picker session — covers all autocomplete calls
  // plus the single Place Details call on selection (one billable session).
  final String _sessionToken = PlacesService.newSessionToken();

  List<PlacePrediction> _predictions = const [];
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _fetchingLocation = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _predictions = const [];
        _isLoading = false;
        _hasSearched = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _autocomplete(query),
    );
  }

  Future<void> _autocomplete(String query) async {
    final results =
        await PlacesService.autocomplete(query, _sessionToken);
    if (!mounted) return;
    setState(() {
      _predictions = results;
      _isLoading = false;
      _hasSearched = true;
    });
  }

  /// Fetch place details (coordinates) for the selected prediction.
  /// Passes the same session token — this finalises the billing session.
  Future<void> _onPredictionTap(PlacePrediction prediction) async {
    setState(() => _isLoading = true);
    final result = await PlacesService.placeDetails(
      prediction.placeId,
      _sessionToken,
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result.toLocationPoint());
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load location details.')),
      );
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    final result = await GpsService.currentLocation();
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result.toLocationPoint());
    } else {
      setState(() => _fetchingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission denied or unavailable. '
            'Enable Location in device Settings.',
          ),
        ),
      );
    }
  }

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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPickup
                        ? 'Select Pickup Location'
                        : 'Select Drop Location',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Search city or area...',
                      prefixIcon: _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : const Icon(Icons.search, size: 20),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            // Current location button — only shown for pickup
            if (isPickup)
              _CurrentLocationTile(
                isLoading: _fetchingLocation,
                onTap: _useCurrentLocation,
              ),
            if (isPickup)
              const Divider(height: 1, color: AppColors.border),

            Expanded(child: _buildBody(scrollController, isPickup)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController, bool isPickup) {
    if (!_hasSearched && !_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Start typing to search for a city or area.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasSearched && _predictions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined,
                  size: 48, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              Text(
                'No results for "${_controller.text}"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _predictions.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border, indent: 56),
      itemBuilder: (context, i) {
        final p = _predictions[i];
        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPickup ? Icons.radio_button_checked : Icons.location_on,
              size: 18,
              color: isPickup ? AppColors.primary : AppColors.orange,
            ),
          ),
          title: Text(
            p.text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          onTap: () => _onPredictionTap(p),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _CurrentLocationTile extends StatelessWidget {
  const _CurrentLocationTile({
    required this.isLoading,
    required this.onTap,
  });
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: isLoading ? null : onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : const Icon(Icons.my_location,
                  size: 18, color: AppColors.primary),
        ),
        title: const Text(
          'Use current location',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        subtitle: const Text(
          'Requires location permission',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      );
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
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
}

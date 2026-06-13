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

  // One session token per picker open. All autocomplete calls in this session
  // share the token. Place Details closes the session when the user selects.
  final String _sessionToken = PlacesService.newSessionToken();

  List<PlacePrediction> _predictions = const [];
  // FIX: Separate the "searching" indicator from the results list.
  // While searching, old results remain visible. Only the prefix icon spins.
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _fetchingLocation = false;
  bool _fetchingDetails = false;
  // FIX: Track API errors separately from empty results.
  String? _apiError;

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
        _isSearching = false;
        _hasSearched = false;
        _apiError = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300), // FIX: 300ms feels snappier than 400ms
      () {
        // FIX: Set searching state INSIDE the debounce callback — not on every
        // keystroke — so the spinner only shows when a request is actually fired.
        if (mounted) setState(() => _isSearching = true);
        _autocomplete(query);
      },
    );
  }

  Future<void> _autocomplete(String query) async {
    final (predictions, error) =
        await PlacesService.autocomplete(query, _sessionToken);
    if (!mounted) return;
    setState(() {
      _predictions = predictions;
      _isSearching = false;
      _hasSearched = true;
      _apiError = error; // null when successful, message string on failure
    });
  }

  Future<void> _onPredictionTap(PlacePrediction prediction) async {
    if (_fetchingDetails) return;
    setState(() {
      _fetchingDetails = true;
      _apiError = null;
    });
    final (result, error) =
        await PlacesService.placeDetails(prediction.placeId, _sessionToken);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result.toLocationPoint());
    } else {
      setState(() {
        _fetchingDetails = false;
        _apiError = error ?? 'Could not load location details.';
      });
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

  // True when any background work is happening (for prefix icon)
  bool get _isBusy => _isSearching || _fetchingDetails;

  @override
  Widget build(BuildContext context) {
    final isPickup = widget.mode == _PickerMode.pickup;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Material(
        // Material provides the ink-splash surface that ListTile requires.
        // Container + BoxDecoration does NOT provide this, causing the
        // "ink splashes may be invisible" warning.
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
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
                      hintText: 'Search city, area or landmark...',
                      // FIX: Spinner only shows when actively searching.
                      // Previous results remain visible beneath it.
                      prefixIcon: _isBusy
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
            if (isPickup)
              _CurrentLocationTile(
                isLoading: _fetchingLocation,
                onTap: _useCurrentLocation,
              ),
            if (isPickup) const Divider(height: 1, color: AppColors.border),

            // FIX: API error banner — distinguishes "no results" from "API broken"
            if (_apiError != null)
              _ErrorBanner(
                message: _apiError!,
                onRetry: _controller.text.trim().length >= 2
                    ? () {
                        setState(() => _apiError = null);
                        _autocomplete(_controller.text);
                      }
                    : null,
              ),

            Expanded(child: _buildBody(scrollController, isPickup)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController, bool isPickup) {
    // FIX: Never replace results with a full-screen spinner.
    // If no results yet and not searched, show the prompt.
    if (!_hasSearched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Search for a city, area, or landmark.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    // Show empty state only after a successful search with zero results.
    if (_hasSearched && _predictions.isEmpty && _apiError == null) {
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
              const SizedBox(height: 6),
              const Text(
                'Try a city name, area, or landmark.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // FIX: Show results even while a new search is in-flight.
    // The spinner in the prefix icon communicates that a refresh is coming.
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _predictions.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: AppColors.border,
        indent: 56,
      ),
      itemBuilder: (context, i) {
        final p = _predictions[i];
        final isTapping = _fetchingDetails;
        return ListTile(
          enabled: !isTapping,
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
          // FIX: Two-line display with mainText (bold) and secondaryText (gray)
          title: Text(
            p.mainText,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: p.secondaryText.isNotEmpty
              ? Text(
                  p.secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                )
              : null,
          onTap: isTapping ? null : () => _onPredictionTap(p),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

/// Shown when the Places API returns an error — clearly distinguishes API
/// failures from genuine "no results" responses.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error)),
              ),
          ],
        ),
      );
}

class _CurrentLocationTile extends StatelessWidget {
  const _CurrentLocationTile(
      {required this.isLoading, required this.onTap});
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

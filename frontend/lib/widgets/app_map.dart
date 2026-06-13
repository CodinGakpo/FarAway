import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/app_theme.dart';

/// Production Google Maps widget.
///
/// Replaces the former FallbackMap canvas widget.
///
/// ## Live tracking readiness (Phase 6)
/// Call [AppMapState.updateTruckPosition] via a GlobalKey to move the truck
/// marker without rebuilding the map widget tree — ready for real GPS streams.
///
///   final _mapKey = GlobalKey<AppMapState>();
///   _mapKey.currentState?.updateTruckPosition(newLatLng);
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    this.pickup,
    this.drop,
    this.pickupLabel,
    this.dropLabel,
    this.truckPosition,
    this.truckLabel,
    this.routePoints,
    this.height,
    this.onMapCreated,
  });

  /// Pickup coordinate — green marker.
  final LatLng? pickup;

  /// Drop coordinate — orange marker.
  final LatLng? drop;

  final String? pickupLabel;
  final String? dropLabel;

  /// Current truck position — blue marker. Updated efficiently via
  /// [AppMapState.updateTruckPosition] without a full widget rebuild.
  final LatLng? truckPosition;

  final String? truckLabel;

  /// Optional explicit route polyline. If null, a direct dashed line is drawn
  /// between pickup and drop when both are provided.
  final List<LatLng>? routePoints;

  /// Fixed height. Null = expand to fill available space.
  final double? height;

  final void Function(GoogleMapController)? onMapCreated;

  @override
  State<AppMap> createState() => AppMapState();
}

class AppMapState extends State<AppMap> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // India geographic center — default camera when no locations are set
  static const _indiaCenter = LatLng(20.5937, 78.9629);

  @override
  void initState() {
    super.initState();
    _rebuild(widget.truckPosition, widget.truckLabel);
  }

  @override
  void didUpdateWidget(AppMap old) {
    super.didUpdateWidget(old);
    // Efficiently update only the truck marker when its position changes
    if (widget.truckPosition != old.truckPosition) {
      _updateTruckMarker(widget.truckPosition, widget.truckLabel);
    }
    // Rebuild all markers and polylines when route inputs change
    if (widget.pickup != old.pickup || widget.drop != old.drop) {
      _rebuild(widget.truckPosition, widget.truckLabel);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fitCamera());
    }
  }

  // ── Public API for parent widgets ──────────────────────────────────────────

  /// Updates the truck marker position without rebuilding the map widget.
  /// Call this from a Timer callback or GPS stream for efficient live tracking.
  void updateTruckPosition(LatLng position, {String? label}) {
    _updateTruckMarker(position, label ?? widget.truckLabel);
  }

  /// Animates the camera to fit all current markers.
  void recenter() => _fitCamera();

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _rebuild(LatLng? truckPos, String? truckLabel) {
    final markers = <Marker>{};
    if (widget.pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickup!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
            title: widget.pickupLabel ?? 'Pickup',
            snippet: 'Pickup point'),
      ));
    }
    if (widget.drop != null) {
      markers.add(Marker(
        markerId: const MarkerId('drop'),
        position: widget.drop!,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
            title: widget.dropLabel ?? 'Drop',
            snippet: 'Drop-off point'),
      ));
    }
    if (truckPos != null) {
      markers.add(_makeTruckMarker(truckPos, truckLabel));
    }

    final polylines = <Polyline>{};
    final pts = widget.routePoints;
    if (pts != null && pts.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: pts,
        color: AppColors.primary,
        width: 4,
      ));
    } else if (widget.pickup != null && widget.drop != null) {
      // Direct dashed line — used when backend route is not yet available
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: [widget.pickup!, widget.drop!],
        color: AppColors.primary,
        width: 3,
        patterns: [PatternItem.dash(16), PatternItem.gap(8)],
      ));
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  void _updateTruckMarker(LatLng? pos, String? label) {
    if (!mounted) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'truck');
      if (pos != null) _markers.add(_makeTruckMarker(pos, label));
    });
  }

  Marker _makeTruckMarker(LatLng pos, String? label) => Marker(
        markerId: const MarkerId('truck'),
        position: pos,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: label ?? 'Driver'),
        zIndex: 2,
      );

  void _fitCamera() {
    if (_controller == null) return;
    final lngs = [
      if (widget.pickup != null) widget.pickup!,
      if (widget.drop != null) widget.drop!,
    ];
    if (lngs.isEmpty) return;
    if (lngs.length == 1) {
      _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: lngs.first, zoom: 13),
        ),
      );
      return;
    }
    final south = lngs.map((l) => l.latitude).reduce(math.min);
    final north = lngs.map((l) => l.latitude).reduce(math.max);
    final west = lngs.map((l) => l.longitude).reduce(math.min);
    final east = lngs.map((l) => l.longitude).reduce(math.max);
    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        72, // padding in logical pixels
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.pickup ?? _indiaCenter,
        zoom: widget.pickup != null ? 11.0 : 5.0,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        widget.onMapCreated?.call(controller);
        _rebuild(widget.truckPosition, widget.truckLabel);
        // Fit after first frame so the map has a measured size
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _fitCamera());
      },
      markers: Set.unmodifiable(_markers),
      polylines: Set.unmodifiable(_polylines),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      liteModeEnabled: false,
    );

    if (widget.height != null) {
      return SizedBox(width: double.infinity, height: widget.height, child: map);
    }
    return map;
  }
}

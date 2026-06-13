import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/app_theme.dart';

class LiveMapWidget extends StatefulWidget {
  const LiveMapWidget({
    super.key,
    this.pickupLocation,
    this.dropLocation,
    this.routePoints,
    this.truckPosition,
    this.truckLabel,
    this.truckSublabel,
    this.height,
    this.showLogoPill = true,
  });

  final LatLng? pickupLocation;
  final LatLng? dropLocation;
  final List<LatLng>? routePoints;
  final LatLng? truckPosition;
  final String? truckLabel;
  final String? truckSublabel;
  final double? height;
  final bool showLogoPill;

  @override
  State<LiveMapWidget> createState() => _LiveMapWidgetState();
}

class _LiveMapWidgetState extends State<LiveMapWidget> {
  GoogleMapController? _controller;
  
  static const LatLng _defaultCenter = LatLng(19.0760, 72.8777); // Mumbai

  @override
  void didUpdateWidget(LiveMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null) {
      _fitBounds();
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _controller!.setMapStyle(_mapStyle);
    _fitBounds();
  }

  void _fitBounds() {
    if (_controller == null) return;

    List<LatLng> points = [];
    if (widget.pickupLocation != null) points.add(widget.pickupLocation!);
    if (widget.dropLocation != null) points.add(widget.dropLocation!);
    if (widget.truckPosition != null) points.add(widget.truckPosition!);
    if (widget.routePoints != null) points.addAll(widget.routePoints!);

    if (points.isEmpty) return;

    if (points.length == 1) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60.0, // padding
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    if (widget.pickupLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      );
    }
    if (widget.dropLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('drop'),
          position: widget.dropLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'Dropoff'),
        ),
      );
    }
    if (widget.truckPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('truck'),
          position: widget.truckPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: widget.truckLabel ?? 'Truck',
            snippet: widget.truckSublabel,
          ),
        ),
      );
    }

    final polylines = <Polyline>{};
    if (widget.routePoints != null && widget.routePoints!.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: widget.routePoints!,
          color: AppColors.primary,
          width: 5,
        ),
      );
    }

    return SizedBox(
      height: widget.height ?? double.infinity,
      width: double.infinity,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultCenter,
              zoom: 11,
            ),
            onMapCreated: _onMapCreated,
            markers: markers,
            polylines: polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),
          
          if (widget.showLogoPill)
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                        child: const Icon(
                          Icons.local_shipping,
                          size: 16,
                          color: Colors.white,
                        ),
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
              ),
            ),
        ],
      ),
    );
  }

  // Simplified light map style
  final String _mapStyle = '''
  [
    {
      "featureType": "poi",
      "stylers": [
        { "visibility": "off" }
      ]
    },
    {
      "featureType": "transit",
      "stylers": [
        { "visibility": "off" }
      ]
    }
  ]
  ''';
}

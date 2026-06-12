import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class FallbackMap extends StatelessWidget {
  const FallbackMap({
    super.key,
    this.pickupAddress,
    this.dropAddress,
    this.truckProgress,
    this.truckLabel,
    this.truckSublabel,
    this.height,
    this.showLogoPill = true,
  });

  final String? pickupAddress;
  final String? dropAddress;
  final double? truckProgress;
  final String? truckLabel;
  final String? truckSublabel;
  final double? height;
  final bool showLogoPill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height ?? double.infinity,
      color: const Color(0xFFE8E0D5), // Grey-beige background
      child: Stack(
        children: [
          // Styled Map lines / grid background for premium look
          Positioned.fill(
            child: CustomPaint(
              painter: _MapGridPainter(
                pickupAddress: pickupAddress,
                dropAddress: dropAddress,
                truckProgress: truckProgress,
              ),
            ),
          ),

          // Pickup and Drop Address Labels on the map
          if (pickupAddress != null)
            Positioned(
              left: 20,
              top: (height ?? 300) * 0.6,
              child: _MapLabel(
                title: 'Pickup',
                address: pickupAddress!,
                color: AppColors.primary,
              ),
            ),

          if (dropAddress != null)
            Positioned(
              right: 20,
              top: (height ?? 300) * 0.35,
              child: _MapLabel(
                title: 'Dropoff',
                address: dropAddress!,
                color: AppColors.orange,
              ),
            ),

          // Truck Info Tooltip (if truck is present)
          if (truckProgress != null && truckLabel != null)
            _buildTruckTooltip(context),

          // Logo Pill overlay
          if (showLogoPill)
            Positioned(
              top: 16,
              left: 16,
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
        ],
      ),
    );
  }

  Widget _buildTruckTooltip(BuildContext context) {
    // Calculate approximate tooltip position based on progress
    // Bezier path: P0 (0.15, 0.65), P1 (0.5, 0.2), P2 (0.85, 0.4)
    final t = truckProgress ?? 0.0;

    // We can estimate the screen position of the truck to place the tooltip
    // We will place it relative to the alignment in screen width/height
    return Align(
      alignment: Alignment(
        -0.7 + (1.4 * t), // maps 0.0..1.0 to -0.7..0.7 horizontal alignment
        -0.2 - (0.3 * math.sin(t * math.pi)), // maps to curve height
      ),
      child: FractionallySizedBox(
        widthFactor: 0.5,
        child: Container(
          margin: const EdgeInsets.only(bottom: 50), // Offset above truck marker
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                truckLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (truckSublabel != null)
                Text(
                  truckSublabel!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({
    required this.title,
    required this.address,
    required this.color,
  });

  final String title;
  final String address;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      constraints: const BoxConstraints(maxWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            address,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  _MapGridPainter({
    this.pickupAddress,
    this.dropAddress,
    this.truckProgress,
  });

  final String? pickupAddress;
  final String? dropAddress;
  final double? truckProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.0;

    // Draw stylized map background roads
    final roadPaint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Simple grid lines
    const gridSpacing = 40.0;
    for (var x = 0.0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Stylized random "roads" in background
    canvas.drawLine(
      Offset(0, size.height * 0.3),
      Offset(size.width, size.height * 0.4),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.2, 0),
      Offset(size.width * 0.4, size.height),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.8, 0),
      Offset(size.width * 0.7, size.height),
      roadPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.7),
      Offset(size.width, size.height * 0.65),
      roadPaint,
    );

    // Render active route
    final hasRoute = pickupAddress != null && dropAddress != null;
    if (hasRoute) {
      final p0 = Offset(size.width * 0.2, size.height * 0.65);
      final p2 = Offset(size.width * 0.8, size.height * 0.4);
      // Curved control point
      final p1 = Offset(size.width * 0.5, size.height * 0.2);

      // 1. Draw Dotted Path
      final pathPaint = Paint()
        ..color = AppColors.primary.withOpacity(0.5)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy);

      _drawDashedPath(canvas, path, pathPaint, 6.0, 6.0);

      // 2. Draw Travelled solid path if truck progress exists
      if (truckProgress != null && truckProgress! > 0.0) {
        final t = truckProgress!.clamp(0.0, 1.0);
        final travelledPaint = Paint()
          ..color = AppColors.primary
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        final travelledPath = Path()..moveTo(p0.dx, p0.dy);
        // Draw path segments up to t
        const segments = 30;
        final endSeg = (segments * t).round();
        for (var i = 1; i <= endSeg; i++) {
          final currT = i / segments;
          final pos = _getBezierPoint(p0, p1, p2, currT);
          travelledPath.lineTo(pos.dx, pos.dy);
        }

        canvas.drawPath(travelledPath, travelledPaint);
      }

      // 3. Draw Pickup Marker (Green Dot)
      final greenPaint = Paint()..color = AppColors.primary;
      canvas.drawCircle(p0, 10, greenPaint);
      canvas.drawCircle(p0, 14, Paint()..color = AppColors.primary.withOpacity(0.25));

      // 4. Draw Dropoff Marker (Orange Dot)
      final orangePaint = Paint()..color = AppColors.orange;
      canvas.drawCircle(p2, 10, orangePaint);
      canvas.drawCircle(p2, 14, Paint()..color = AppColors.orange.withOpacity(0.25));

      // 5. Draw Truck Marker along the path
      if (truckProgress != null) {
        final truckPos = _getBezierPoint(p0, p1, p2, truckProgress!.clamp(0.0, 1.0));
        final truckPaint = Paint()..color = Colors.blue.shade600;
        canvas.drawCircle(truckPos, 11, truckPaint);
        canvas.drawCircle(
            truckPos, 15, Paint()..color = Colors.blue.shade600.withOpacity(0.25));
      }
    } else if (pickupAddress != null) {
      // Just pickup selected
      final p0 = Offset(size.width * 0.5, size.height * 0.5);
      final greenPaint = Paint()..color = AppColors.primary;
      canvas.drawCircle(p0, 10, greenPaint);
      canvas.drawCircle(p0, 14, Paint()..color = AppColors.primary.withOpacity(0.25));
    }
  }

  Offset _getBezierPoint(Offset p0, Offset p1, Offset p2, double t) {
    final x = (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
    final y = (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dashWidth,
    double dashSpace,
  ) {
    // Basic dash path rendering logic using metrics
    try {
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          final remaining = metric.length - distance;
          final width = remaining < dashWidth ? remaining : dashWidth;
          canvas.drawPath(
            metric.extractPath(distance, distance + width),
            paint,
          );
          distance += dashWidth + dashSpace;
        }
      }
    } catch (_) {
      // Fallback to standard path drawing if computeMetrics is unavailable
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

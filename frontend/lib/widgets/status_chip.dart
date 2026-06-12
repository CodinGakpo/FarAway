import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.toUpperCase();
    final color = _statusColor(normalizedStatus);

    return Chip(
      label: Text(
        normalizedStatus,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      backgroundColor: color,
      side: BorderSide.none,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.amber;
      case 'ACCEPTED':
      case 'ACTIVE':
      case 'COMPLETED':
      case 'DELIVERED':
        return const Color(0xFF1D9E75);
      case 'REJECTED':
        return Colors.red;
      case 'PICKED_UP':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }
}

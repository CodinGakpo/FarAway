class Trip {
  final String id;
  final String driverId;
  final String? driverName;
  final String origin;
  final String destination;
  final DateTime date;
  final double maxWeight;
  final double maxVolume;
  final double remainingWeight;
  final double remainingVolume;
  final String status;

  Trip({
    required this.id,
    required this.driverId,
    this.driverName,
    required this.origin,
    required this.destination,
    required this.date,
    required this.maxWeight,
    required this.maxVolume,
    required this.remainingWeight,
    required this.remainingVolume,
    required this.status,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'].toString(),
      driverId: json['driver_id'] as String? ?? json['driverId'] as String? ?? '',
      driverName: json['driverName'] as String?,
      origin: json['origin_name'] as String? ?? json['origin'] as String? ?? '',
      destination: json['destination_name'] as String? ?? json['destination'] as String? ?? '',
      date: DateTime.parse((json['departure_time'] ?? json['date']) as String),
      maxWeight: ((json['max_weight_capacity'] ?? json['maxWeight']) as num).toDouble(),
      maxVolume: ((json['max_volume_capacity'] ?? json['maxVolume']) as num).toDouble(),
      remainingWeight: ((json['remaining_weight_capacity'] ?? json['remainingWeight'] ?? json['max_weight_capacity'] ?? json['maxWeight']) as num).toDouble(),
      remainingVolume: ((json['remaining_volume_capacity'] ?? json['remainingVolume'] ?? json['max_volume_capacity'] ?? json['maxVolume']) as num).toDouble(),
      status: json['status'] as String? ?? 'ACTIVE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'driverName': driverName,
      'origin': origin,
      'destination': destination,
      'date': date.toIso8601String(),
      'maxWeight': maxWeight,
      'maxVolume': maxVolume,
      'remainingWeight': remainingWeight,
      'remainingVolume': remainingVolume,
      'status': status,
    };
  }
}

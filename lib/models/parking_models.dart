import 'package:google_maps_flutter/google_maps_flutter.dart';

enum ParkingStatus { available, occupied, reserved }

class ParkingLocation {
  final int? id;
  final String name;
  final String distance;
  final LatLng location;
  final int availableSpots;

  ParkingLocation({
    this.id,
    required this.name,
    required this.distance,
    required this.location,
    required this.availableSpots,
  });
}

class ParkingSpaceStatus {
  final String id;
  final LatLng location;
  final ParkingStatus status;
  final int parkingLocationId;
  final String parkingName;
  final String price;

  ParkingSpaceStatus({
    required this.id,
    required this.location,
    required this.status,
    required this.parkingLocationId,
    required this.parkingName,
    required this.price,
  });
}

class ValetBooking {
  final String id;
  final String userId;
  final LatLng pickupLocation;
  final LatLng parkingLocation;
  final DateTime bookingTime;
  final String valetName;
  final String valetPhone;
  final String vehicleNumber;

  ValetBooking({
    required this.id,
    required this.userId,
    required this.pickupLocation,
    required this.parkingLocation,
    required this.bookingTime,
    required this.valetName,
    required this.valetPhone,
    required this.vehicleNumber,
  });
}

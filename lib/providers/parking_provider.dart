import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

import '../models/parking_models.dart';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';

class ParkingProvider extends ChangeNotifier {
  List<ParkingLocation> _nearbyParkings = [];
  String fetchStatus = '';

  ParkingProvider() {
    fetchParkings();
  }

  List<ParkingLocation> get nearbyParkings => _nearbyParkings;

  void _initializeParkings() {
    // Deprecated static initialization. Use fetchParkings instead.
  }

  Future<void> fetchParkings([LatLng? userLocation]) async {
    final jwtToken = AuthTokenStore().token;
    final primaryUrl = Uri.parse('$apiBase/api/parking/locations');
    final fallbackUrl = Uri.parse('$apiEmulatorFallback/api/parking/locations');
    Uri url = primaryUrl;
    http.Response? response;
    try {
      response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      // Try fallback if primary didn't return 200
      if (response.statusCode != 200) {
        fetchStatus = 'primary failed ${response.statusCode}';
        debugPrint('fetchParkings: primary url failed with ${response.statusCode}');
        url = fallbackUrl;
        try {
          response = await http.get(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (jwtToken != null && jwtToken.isNotEmpty)
                'Authorization': 'Bearer $jwtToken',
            },
          );
          fetchStatus = 'fallback status ${response.statusCode}';
          debugPrint('fetchParkings: fallback url status ${response.statusCode}');
        } catch (e) {
          fetchStatus = 'fallback error $e';
          debugPrint('fetchParkings: fallback request error: $e');
        }
      } else {
        fetchStatus = 'primary status ${response.statusCode}';
      }

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final locations = (data['locations'] as List<dynamic>? ) ?? [];
        _nearbyParkings = locations.map((loc) {
          final lat = double.tryParse(loc['latitude'].toString()) ?? 0.0;
          final lng = double.tryParse(loc['longitude'].toString()) ?? 0.0;
          final locLatLng = LatLng(lat, lng);
          final distanceStr = _formatDistanceBetween(userLocation, locLatLng);
          return ParkingLocation(
            id: loc['id'] is int ? loc['id'] : int.tryParse(loc['id']?.toString() ?? ''),
            name: loc['name']?.toString() ?? 'Unknown',
            distance: distanceStr,
            location: locLatLng,
            availableSpots: _extractAvailableSpots(loc),
          );
        }).toList();
      } else {
        debugPrint('fetchParkings: no valid response, setting empty list');
        fetchStatus = 'no valid response';
        _nearbyParkings = [];
      }
    } catch (e) {
      debugPrint('fetchParkings exception: $e');
      fetchStatus = 'exception $e';
      _nearbyParkings = [];
    }
    notifyListeners();
  }

  int _extractAvailableSpots(Map<String, dynamic> loc) {
    final slots = loc['slots'];
    if (slots is List) {
      int count = 0;
      for (final slot in slots) {
        if (slot is Map && slot['status']?.toString() == 'available') {
          count += 1;
        }
      }
      if (slots.isNotEmpty) return count;
    }

    final direct = _toInt(loc['available_slots']);
    if (direct != null) return direct;

    final total = _toInt(loc['total_slots']);
    if (total != null) {
      final occupied = _toInt(loc['occupied_slots']) ?? 0;
      final booked = _toInt(loc['booked_slots']) ?? 0;
      final reserved = _toInt(loc['reserved_slots']) ?? 0;
      final computed = total - occupied - booked - reserved;
      return computed < 0 ? 0 : computed;
    }

    return 0;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  void updateDistances(LatLng? userLocation) {
    if (userLocation == null) return;
    _nearbyParkings = _nearbyParkings.map((p) {
      return ParkingLocation(
        id: p.id,
        name: p.name,
        distance: _formatDistanceBetween(userLocation, p.location),
        location: p.location,
        availableSpots: p.availableSpots,
      );
    }).toList();
    // Sort by numeric distance (meters)
    _nearbyParkings.sort((a, b) {
      final aMeters = _distanceMeters(userLocation, a.location);
      final bMeters = _distanceMeters(userLocation, b.location);
      return aMeters.compareTo(bMeters);
    });
    notifyListeners();
  }

  String _formatDistanceBetween(LatLng? from, LatLng to) {
    if (from == null) return '--';
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    if (meters < 1000) return '${meters.round()} m';
    final km = (meters / 1000);
    return '${km.toStringAsFixed(1)} km';
  }

  double _distanceMeters(LatLng? from, LatLng to) {
    if (from == null) return double.infinity;
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  void addParking(ParkingLocation parking, [LatLng? userLocation]) {
    final distanceStr = _formatDistanceBetween(userLocation, parking.location);
    final newParking = ParkingLocation(
      id: parking.id,
      name: parking.name,
      distance: distanceStr,
      location: parking.location,
      availableSpots: parking.availableSpots,
    );
    _nearbyParkings.add(newParking);
    // If user location available, keep list sorted by distance
    if (userLocation != null) {
      _nearbyParkings.sort((a, b) {
        final aMeters = _distanceMeters(userLocation, a.location);
        final bMeters = _distanceMeters(userLocation, b.location);
        return aMeters.compareTo(bMeters);
      });
    }
    notifyListeners();
  }

  void removeParkingAt(int index) {
    if (index >= 0 && index < _nearbyParkings.length) {
      _nearbyParkings.removeAt(index);
      notifyListeners();
    }
  }
}

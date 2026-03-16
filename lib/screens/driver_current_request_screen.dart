import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'driver_parking_selection_screen.dart';
import 'login_screen.dart';
import '../core/utils/auth_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverCurrentRequestScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onRequestCompleted;
  final bool showPickupAction;

  const DriverCurrentRequestScreen({
    Key? key,
    required this.request,
    required this.onRequestCompleted,
    this.showPickupAction = true,
  }) : super(key: key);

  @override
  State<DriverCurrentRequestScreen> createState() =>
      _DriverCurrentRequestScreenState();
}

class _DriverCurrentRequestScreenState
    extends State<DriverCurrentRequestScreen> {
  GoogleMapController? mapController;
  LatLng? _customerLocation;
  LatLng? _driverLocation;
  bool _isParkingDestination = false;
  late Set<Marker> _markers;
  late Set<Polyline> _polylines;
  StreamSubscription<Position>? _positionSub;

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initializeLocations();
    _refreshDriverLocation();
    _startLiveLocationUpdates();
  }

  void _initializeLocations() {
    final requestType =
        (widget.request['requestType'] ?? '').toString().toLowerCase();
    final hasAssignedSlot =
        (widget.request['slotNumber']?.toString().isNotEmpty ?? false);
    final parkingLat = _toDouble(widget.request['parkingLat']);
    final parkingLng = _toDouble(widget.request['parkingLng']);
    final useParkingDestination =
        requestType != 'return' &&
        hasAssignedSlot &&
        parkingLat != null &&
        parkingLng != null;

    final targetLat = requestType == 'return'
        ? (_toDouble(widget.request['returnLat']) ??
            _toDouble(widget.request['customerLat']) ??
            37.7749)
        : (useParkingDestination
            ? parkingLat!
            : (_toDouble(widget.request['customerLat']) ?? 37.7749));
    final targetLng = requestType == 'return'
        ? (_toDouble(widget.request['returnLng']) ??
            _toDouble(widget.request['customerLng']) ??
            -122.4194)
        : (useParkingDestination
            ? parkingLng!
            : (_toDouble(widget.request['customerLng']) ?? -122.4194));

    _isParkingDestination = useParkingDestination;

    // Customer location (red marker)
    _customerLocation = LatLng(targetLat, targetLng);
    // Driver location will be updated from live GPS.
    _driverLocation = LatLng(
      targetLat - 0.001,
      targetLng - 0.001,
    );

    _markers = {
      Marker(
        markerId: const MarkerId('driver'),
        position: _driverLocation!,
        infoWindow: const InfoWindow(title: 'Your Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId('customer'),
        position: _customerLocation!,
        infoWindow: InfoWindow(
          title: requestType == 'return'
              ? 'Return Destination'
              : (_isParkingDestination
                  ? 'Parking Location'
                  : 'Customer Location'),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    _polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_driverLocation!, _customerLocation!],
        color: Colors.blue.shade600,
        width: 5,
        geodesic: true,
      ),
    };
  }

  Future<void> _refreshDriverLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _driverLocation = LatLng(pos.latitude, pos.longitude);
        _markers = {
          Marker(
            markerId: const MarkerId('driver'),
            position: _driverLocation!,
            infoWindow: const InfoWindow(title: 'Your Location'),
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
          Marker(
            markerId: const MarkerId('customer'),
            position: _customerLocation!,
            infoWindow: InfoWindow(
              title: (widget.request['requestType'] ?? '')
                          .toString()
                          .toLowerCase() ==
                      'return'
                  ? 'Return Destination'
                  : (_isParkingDestination
                      ? 'Parking Location'
                      : 'Customer Location'),
            ),
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        };
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: [_driverLocation!, _customerLocation!],
            color: Colors.blue.shade600,
            width: 5,
            geodesic: true,
          ),
        };
      });
    } catch (_) {}
  }

  Future<void> _startLiveLocationUpdates() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((pos) {
        if (!mounted || _customerLocation == null) return;
        setState(() {
          _driverLocation = LatLng(pos.latitude, pos.longitude);
          _markers = {
            Marker(
              markerId: const MarkerId('driver'),
              position: _driverLocation!,
              infoWindow: const InfoWindow(title: 'Your Location'),
              icon:
                  BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            ),
            Marker(
              markerId: const MarkerId('customer'),
              position: _customerLocation!,
              infoWindow: InfoWindow(
                title: (widget.request['requestType'] ?? '')
                            .toString()
                            .toLowerCase() ==
                        'return'
                    ? 'Return Destination'
                    : (_isParkingDestination
                        ? 'Parking Location'
                        : 'Customer Location'),
              ),
              icon:
                  BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          };
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: [_driverLocation!, _customerLocation!],
              color: Colors.blue.shade600,
              width: 5,
              geodesic: true,
            ),
          };
        });
    });
  } catch (_) {}
  }

  void _onPickedUp() {
    if (widget.request['requestType'] == 'pickup') {
      // Go to parking selection
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DriverParkingSelectionScreen(
            request: widget.request,
            onCompleted: () {
              widget.onRequestCompleted();
              Navigator.pop(context);
            },
          ),
        ),
      );
    } else {
      // Retrieved - task complete
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle retrieved successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
      widget.onRequestCompleted();
      Navigator.pop(context);
    }
  }

  bool get _isReturnRequest =>
      (widget.request['requestType'] ?? '').toString().toLowerCase() ==
      'return';

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (shouldLogout != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('user_id');
    } catch (_) {}

    try {
      AuthTokenStore().token = null;
      AuthTokenStore().userId = null;
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (context) => const LoginScreen(fromLogout: true)),
      (route) => false,
    );
  }

  Future<void> _navigateToCustomer() async {
    if (_customerLocation == null) return;
    final lat = _customerLocation!.latitude;
    final lng = _customerLocation!.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open navigation app'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openInGoogleMaps() async {
    if (_customerLocation == null) return;
    final lat = _customerLocation!.latitude;
    final lng = _customerLocation!.longitude;
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Current Request Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Assigned Request',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Customer Name
                    Text(
                      _isReturnRequest
                          ? 'Return Request - ${widget.request['customerName']}'
                          : widget.request['customerName'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Vehicle Info
                    Text(
                      widget.request['vehicleModel'],
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Time and Location
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.request['time'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isReturnRequest
                              ? (widget.request['returnLocationText']
                                          ?.toString()
                                          .isNotEmpty ==
                                      true
                                  ? widget.request['returnLocationText']
                                  : 'Return destination')
                              : (_isParkingDestination
                                  ? (widget.request['parkingLocationName']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true
                                      ? widget.request['parkingLocationName']
                                      : 'Parking location')
                                  : widget.request['parkingLocation']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Route Section Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isReturnRequest
                      ? 'Return Route'
                      : (_isParkingDestination
                          ? 'Parking Route'
                          : 'Customer Route'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _navigateToCustomer,
                  icon: const Icon(Icons.navigation),
                  label: Text(_isReturnRequest
                      ? 'Navigate to Return Location'
                      : (_isParkingDestination
                          ? 'Navigate to Parking'
                          : 'Navigate to Customer')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openInGoogleMaps,
                  icon: const Icon(Icons.map),
                  label: const Text('Open Google Maps'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

            // Map
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target:
                            _driverLocation ?? const LatLng(37.7749, -122.4194),
                        zoom: 16,
                      ),
                      onMapCreated: (controller) {
                        mapController = controller;
                      },
                      markers: _markers,
                      polylines: _polylines,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                      zoomGesturesEnabled: true,
                      mapToolbarEnabled: false,
                    ),
                  ),
                ),
              ),
            ),

            if (widget.showPickupAction)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onPickedUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.request['requestType'] == 'pickup'
                          ? 'Pickup Vehicle'
                          : 'Retrieved',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    mapController?.dispose();
    super.dispose();
  }
}

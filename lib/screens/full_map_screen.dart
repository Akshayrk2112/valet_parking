import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/parking_models.dart';
import '../widgets/custom_drawer.dart';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';

class FullMapScreen extends StatefulWidget {
  final LatLng initialLocation;
  final List<ParkingLocation> nearbyParkings;

  const FullMapScreen({
    Key? key,
    required this.initialLocation,
    required this.nearbyParkings,
  }) : super(key: key);

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen>
    with TickerProviderStateMixin {
  GoogleMapController? mapController;
  LatLng? _currentLocation;
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _showRouteInfo = false;
  String _selectedMarkerTitle = '';
  double _selectedMarkerDistance = 0.0;
  int _selectedMarkerIndex = -1;

  // Parking space status
  late List<ParkingSpaceStatus> _parkingSpaces;
  late AnimationController _pulseController;
  bool _isMounted = true;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _generateParkingSpaces();
    _initializeMarkers();

    // Pulse animation for floating indicators
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  void _generateParkingSpaces() {
    _parkingSpaces = [];
    final random = Random();

    // Generate parking spaces for each parking location
    for (int i = 0; i < widget.nearbyParkings.length; i++) {
      final parking = widget.nearbyParkings[i];

      // Create 8-12 parking spaces per location
      final spacesCount = 8 + random.nextInt(5);

      for (int j = 0; j < spacesCount; j++) {
        // Random offset within the parking location (smaller radius for better clustering)
        final latOffset = (random.nextDouble() - 0.5) * 0.001;
        final lngOffset = (random.nextDouble() - 0.5) * 0.001;

        // Randomly assign status
        final statusRandom = random.nextInt(100);
        late ParkingStatus status;

        if (statusRandom < 50) {
          status = ParkingStatus.available; // 50% green
        } else if (statusRandom < 80) {
          status = ParkingStatus.occupied; // 30% red
        } else {
          status = ParkingStatus.reserved; // 20% yellow
        }

        _parkingSpaces.add(
          ParkingSpaceStatus(
            id: 'space_${i}_$j',
            location: LatLng(
              parking.location.latitude + latOffset,
              parking.location.longitude + lngOffset,
            ),
            status: status,
            parkingLocationId: i,
            parkingName: parking.name,
            price: '₹${15 + random.nextInt(20)}/hr',
          ),
        );
      }
    }
  }

  void _initializeMarkers() {
    Set<Marker> markers = {};

    // Add current location marker
    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Current Position',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          onTap: () {
            _onCurrentLocationTapped();
          },
        ),
      );
    }

    // Add parking location markers
    for (int i = 0; i < widget.nearbyParkings.length; i++) {
      final parking = widget.nearbyParkings[i];
      markers.add(
        Marker(
          markerId: MarkerId('parking_$i'),
          position: parking.location,
          infoWindow: InfoWindow(
            title: parking.name,
            snippet:
                '${parking.distance} away • ${parking.availableSpots} spots',
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          onTap: () {
            _onParkingMarkerTapped(parking, i);
          },
        ),
      );
    }

    if (_isMounted) {
      setState(() {
        _markers = markers;
      });
    }
  }

  void _onCurrentLocationTapped() {
    if (_isMounted) {
      setState(() {
        _showRouteInfo = false;
        _selectedLocation = null;
        _selectedMarkerIndex = -1;
        _polylines.clear();
      });
    }
  }

  void _onParkingMarkerTapped(ParkingLocation parking, int index) {
    if (!_isMounted || _currentLocation == null) return;

    final distance = _calculateDistance(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      parking.location.latitude,
      parking.location.longitude,
    );

    if (_isMounted) {
      setState(() {
        _selectedLocation = parking.location;
        _selectedMarkerTitle = parking.name;
        _selectedMarkerDistance = distance;
        _selectedMarkerIndex = index;
        _showRouteInfo = true;
      });
    }

    _drawRoute();
    _animateCameraToMarkers();
  }

  Future<void> _openNavigationToSelected() async {
    if (_selectedLocation == null) return;
    final destLat = _selectedLocation!.latitude;
    final destLng = _selectedLocation!.longitude;
    final origin = _currentLocation != null
        ? '&origin=${_currentLocation!.latitude},${_currentLocation!.longitude}'
        : '';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng$origin&travelmode=driving',
    );

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open navigation app'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open navigation app'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onParkingSpaceTapped(ParkingSpaceStatus space) {
    if (!_isMounted || _currentLocation == null) return;

    final distance = _calculateDistance(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      space.location.latitude,
      space.location.longitude,
    );

    if (_isMounted) {
      setState(() {
        _selectedLocation = space.location;
        _selectedMarkerTitle = '${space.parkingName} - Space ${space.id}';
        _selectedMarkerDistance = distance;
        _showRouteInfo = true;
      });
    }

    _drawRoute();
    _animateCameraToMarkers();

    // Show space details
    _showParkingSpaceDetails(space);
  }

  void _showParkingSpaceDetails(ParkingSpaceStatus space) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        space.parkingName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Space: ${space.id.replaceAll('space_', '')}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(space.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getStatusIcon(space.status),
                      color: _getStatusColor(space.status),
                      size: 24,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Status and Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(space.status),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getStatusText(space.status),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Distance',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _getDistanceString(_selectedMarkerDistance),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Price',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          space.price,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action buttons
              if (space.status == ParkingStatus.available)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Parking space ${space.id} reserved!'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Reserve Space',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Space Not Available',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _drawRoute() {
    if (_selectedLocation != null && _currentLocation != null && _isMounted) {
      setState(() {
        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: [_currentLocation!, _selectedLocation!],
            color: Colors.blue.shade600,
            width: 5,
            geodesic: true,
          ),
        );
      });
    }
  }

  void _animateCameraToMarkers() {
    if (mapController == null ||
        _selectedLocation == null ||
        _currentLocation == null) {
      return;
    }

    try {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          (_currentLocation!.latitude < _selectedLocation!.latitude)
              ? _currentLocation!.latitude
              : _selectedLocation!.latitude,
          (_currentLocation!.longitude < _selectedLocation!.longitude)
              ? _currentLocation!.longitude
              : _selectedLocation!.longitude,
        ),
        northeast: LatLng(
          (_currentLocation!.latitude > _selectedLocation!.latitude)
              ? _currentLocation!.latitude
              : _selectedLocation!.latitude,
          (_currentLocation!.longitude > _selectedLocation!.longitude)
              ? _currentLocation!.longitude
              : _selectedLocation!.longitude,
        ),
      );

      mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    } catch (e) {
      debugPrint('Error animating camera: $e');
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    final km = 12742 * asin(sqrt(a));
    return km * 1000; // Return in meters
  }

  String _getDistanceString(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  Color _getStatusColor(ParkingStatus status) {
    switch (status) {
      case ParkingStatus.available:
        return Colors.green.shade600;
      case ParkingStatus.occupied:
        return Colors.red.shade600;
      case ParkingStatus.reserved:
        return Colors.yellow.shade600;
    }
  }

  String _getStatusText(ParkingStatus status) {
    switch (status) {
      case ParkingStatus.available:
        return 'Available';
      case ParkingStatus.occupied:
        return 'Occupied';
      case ParkingStatus.reserved:
        return 'Reserved';
    }
  }

  IconData _getStatusIcon(ParkingStatus status) {
    switch (status) {
      case ParkingStatus.available:
        return Icons.check_circle;
      case ParkingStatus.occupied:
        return Icons.cancel;
      case ParkingStatus.reserved:
        return Icons.lock_clock;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_showRouteInfo) {
          setState(() {
            _showRouteInfo = false;
            _polylines.clear();
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Map View'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        drawer: const CustomDrawer(),
        body: Stack(
          children: [
            // Full-screen Google Map
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentLocation ?? const LatLng(37.7749, -122.4194),
                zoom: 15,
              ),
              onMapCreated: (controller) {
                mapController = controller;
                setState(() {}); // trigger rebuild for FloatingParkingSpace
              },
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              zoomGesturesEnabled: true,
              mapToolbarEnabled: false,
              onTap: (LatLng position) {
                if (_isMounted) {
                  setState(() {
                    _showRouteInfo = false;
                    _polylines.clear();
                  });
                }
              },
            ),

            // Floating Parking Space Indicators
            ..._parkingSpaces.map((space) {
              if (mapController == null) return const SizedBox.shrink();
              return FloatingParkingSpace(
                space: space,
                onTap: () => _onParkingSpaceTapped(space),
                mapController: mapController!, // safe to use !
                pulseController: _pulseController,
              );
            }).toList(),

            // Route Info Panel
            if (_showRouteInfo)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Route Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Route Details',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _showRouteInfo = false;
                                _polylines.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Location Details
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: Colors.blue.shade600,
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedMarkerTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Distance: ${_getDistanceString(_selectedMarkerDistance)}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _showRouteInfo = false;
                                  _polylines.clear();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showRouteInfo = false;
                                });
                                _openNavigationToSelected();
                              },
                              icon: const Icon(Icons.directions),
                              label: const Text('Navigate'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Legend overlay
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Parking Status:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildLegendItem(Colors.green.shade600, 'Available'),
                      const SizedBox(height: 6),
                      _buildLegendItem(Colors.red.shade600, 'Occupied'),
                      const SizedBox(height: 6),
                      _buildLegendItem(Colors.yellow.shade600, 'Reserved'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _isMounted = false;
    _pulseController.dispose();
    super.dispose();
  }
}

// Floating Parking Space Widget
class FloatingParkingSpace extends StatefulWidget {
  final ParkingSpaceStatus space;
  final VoidCallback onTap;
  final GoogleMapController mapController;
  final AnimationController pulseController;

  const FloatingParkingSpace({
    Key? key,
    required this.space,
    required this.onTap,
    required this.mapController,
    required this.pulseController,
  }) : super(key: key);

  @override
  State<FloatingParkingSpace> createState() => _FloatingParkingSpaceState();
}

class _FloatingParkingSpaceState extends State<FloatingParkingSpace> {
  Offset _screenPosition = Offset.zero;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _updatePosition();
  }

  void _updatePosition() async {
    try {
      final screenCoordinate = await widget.mapController.getScreenCoordinate(
        widget.space.location,
      );

      if (screenCoordinate != null && mounted) {
        setState(() {
          _screenPosition = Offset(
            screenCoordinate.x.toDouble(),
            screenCoordinate.y.toDouble(),
          );
          _isVisible = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    }
  }

  Color _getStatusColor() {
    switch (widget.space.status) {
      case ParkingStatus.available:
        return Colors.green.shade600;
      case ParkingStatus.occupied:
        return Colors.red.shade600;
      case ParkingStatus.reserved:
        return Colors.yellow.shade600;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.space.status) {
      case ParkingStatus.available:
        return Icons.directions_car;
      case ParkingStatus.occupied:
        return Icons.block;
      case ParkingStatus.reserved:
        return Icons.lock;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _screenPosition.dx - 25,
      top: _screenPosition.dy - 25,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(
                parent: widget.pulseController, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _getStatusColor(),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor().withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(25),
                child: Center(
                  child: Icon(
                    _getStatusIcon(),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

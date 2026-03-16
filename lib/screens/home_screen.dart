import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../providers/parking_provider.dart';
import '../models/parking_models.dart';
import '../widgets/custom_drawer.dart';
import 'book_valet_screen.dart';
import 'track_valet_screen.dart';
import 'full_map_screen.dart';
import 'park_yourself_screen.dart';
import 'parking_layout_screen.dart';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? mapController;
  LatLng? _currentLocation;
  bool _isLoadingLocation = true;
  bool _isLoadingNotifications = false;
  int _unreadNotificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  Timer? _notificationPollTimer;
  DateTime? _lastBackPressed;

  Future<bool> _handleExitWarning() async {
    final now = DateTime.now();
    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please logout to exit this dashboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadNotifications();
    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadNotifications(silent: true),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLoadingLocation = false);
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        // Fetch parkings with the user's location so provider computes distances and sorts
        final provider = Provider.of<ParkingProvider>(context, listen: false);
        provider.fetchParkings(_currentLocation);
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    if (!silent) {
      setState(() {
        _isLoadingNotifications = true;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/notifications/mine?limit=30'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (!mounted) return;
      if (response.statusCode != 200) {
        if (!silent) {
          setState(() {
            _isLoadingNotifications = false;
          });
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final unreadRaw = data['unread_count'];
      final unreadCount = unreadRaw is int
          ? unreadRaw
          : int.tryParse(unreadRaw?.toString() ?? '0') ?? 0;
      final list = (data['notifications'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _unreadNotificationCount = unreadCount;
        _notifications = list;
        _isLoadingNotifications = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  Future<void> _markAllNotificationsRead() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      await http.patch(
        Uri.parse('$apiBase/api/notifications/read-all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
    } catch (_) {}
  }

  String _formatNotificationTime(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year;
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$min';
  }

  Future<void> _openNotifications() async {
    await _loadNotifications();
    if (!mounted) return;

    final items = List<Map<String, dynamic>>.from(_notifications);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No notifications yet'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final message = (item['message'] ?? '').toString();
                          final createdAt =
                              (item['created_at'] ?? '').toString();
                          final isRead = item['is_read'] == true;

                          return ListTile(
                            leading: Icon(
                              isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: isRead
                                  ? Colors.grey.shade600
                                  : Colors.orange.shade600,
                            ),
                            title: Text(
                              message,
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(_formatNotificationTime(createdAt)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_unreadNotificationCount > 0) {
      await _markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        _unreadNotificationCount = 0;
        _notifications = _notifications.map((n) {
          final updated = Map<String, dynamic>.from(n);
          updated['is_read'] = true;
          return updated;
        }).toList();
      });
    }
  }

  void _openFullMap() {
    final provider = Provider.of<ParkingProvider>(context, listen: false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullMapScreen(
          initialLocation:
              _currentLocation ?? const LatLng(37.7749, -122.4194),
          nearbyParkings: provider.nearbyParkings,
        ),
      ),
    );
  }

  Future<void> _openNavigation(ParkingLocation parking) async {
    final lat = parking.location.latitude;
    final lng = parking.location.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint('Could not launch maps');
      }
    } catch (e) {
      debugPrint('Could not launch maps: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleExitWarning,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Valet Parking'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 2,
          actions: [
            Stack(
              children: [
                IconButton(
                  icon: _isLoadingNotifications
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        )
                      : const Icon(Icons.notifications),
                  onPressed: _openNotifications,
                ),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _unreadNotificationCount > 99
                            ? '99+'
                            : '$_unreadNotificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        drawer: const CustomDrawer(
          showHomeItem: false,
          showLoginItem: false,
          showCustomerHistory: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
            // Action Buttons - Book Valet & Track Valet
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const BookValetScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Book Valet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const TrackValetScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Track Valet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Expanded Map Preview
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _isLoadingLocation
                      ? Center(
                          child: CircularProgressIndicator(
                            color: Colors.blue.shade600,
                          ),
                        )
                      : Stack(
                          children: [
                            GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: _currentLocation ??
                                    const LatLng(37.7749, -122.4194),
                                zoom: 15,
                              ),
                              onMapCreated: (controller) {
                                setState(() {
                                  mapController = controller;
                                });
                              },
                              markers: _buildMarkers(
                                Provider.of<ParkingProvider>(context)
                                    .nearbyParkings,
                              ),
                              myLocationEnabled: true,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: true,
                              zoomGesturesEnabled: true,
                              mapToolbarEnabled: false,
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: _openFullMap,
                                  child: Ink(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade600,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.fullscreen,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Park Yourself Button - Full Width
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final provider = Provider.of<ParkingProvider>(
                      context,
                      listen: false,
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ParkYourselfScreen(
                          userLocation: _currentLocation,
                          nearbyParkings: provider.nearbyParkings,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Park Yourself',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Nearby Parking Cards - Bottom Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby Parking',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer<ParkingProvider>(
                    builder: (context, provider, _) {
                      return SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: provider.nearbyParkings.length,
                          itemBuilder: (context, index) {
                            final parking = provider.nearbyParkings[index];
                            return ParkingCard(
                              parking: parking,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ParkingLayoutScreen(parking: parking),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Set<Marker> _buildMarkers(List<ParkingLocation> parkings) {
    Set<Marker> markers = {};

    // Add current location marker
    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          infoWindow: const InfoWindow(title: 'You'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    // Add nearby parking markers
    for (int i = 0; i < parkings.length; i++) {
      final parking = parkings[i];
      markers.add(
        Marker(
          markerId: MarkerId('parking_$i'),
          position: parking.location,
          infoWindow: InfoWindow(
            title: parking.name,
            snippet:
                '${parking.availableSpots} slots available - ${parking.distance} away - tap for navigation',
            onTap: () {
              _openNavigation(parking);
            },
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    return markers;
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }
}

class ParkingCard extends StatelessWidget {
  final ParkingLocation parking;
  final VoidCallback onTap;

  const ParkingCard({
    Key? key,
    required this.parking,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              parking.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              parking.distance,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              '${parking.availableSpots} slots available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(
                Icons.arrow_forward,
                color: Colors.blue.shade600,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

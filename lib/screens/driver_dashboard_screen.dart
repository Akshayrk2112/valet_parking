import 'package:flutter/material.dart';
import 'dart:async';
import 'login_screen.dart';
import 'driver_current_request_screen.dart';
import 'driver_profile_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({Key? key}) : super(key: key);

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
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

  Map<String, dynamic>? _toRequestMap(Map<String, dynamic> booking) {
    final bookingIdRaw =
        booking['booking_token'] ?? booking['id'] ?? booking['booking_id'];
    if (bookingIdRaw == null) return null;

    final requestTypeRaw = (booking['request_type'] ??
            (booking['return_requested_at'] != null ? 'return' : 'pickup'))
        .toString()
        .toLowerCase();
    final requestType = requestTypeRaw == 'return' ? 'return' : 'pickup';

    return {
      'id': bookingIdRaw.toString(),
      'customerName': booking['customer_name']?.toString().isNotEmpty == true
          ? booking['customer_name'].toString()
          : 'Customer ${booking['user_id']}',
      'vehicleModel': booking['vehicle_type']?.toString() ?? '',
      'vehicleNumber': booking['vehicle_number']?.toString() ?? '',
      'time': booking['booking_time']?.toString() ?? '',
      'parkingLocation': booking['location_id']?.toString() ?? 'Not assigned',
      'parkingLocationName': booking['location_name']?.toString() ?? '',
      'slotNumber': booking['slot_number']?.toString() ?? '',
      'bookingStatus': booking['status']?.toString() ?? 'pending',
      'requestType': requestType,
      'customerLat': _toDouble(booking['customer_latitude']),
      'customerLng': _toDouble(booking['customer_longitude']),
      'parkingLat': _toDouble(booking['location_latitude']),
      'parkingLng': _toDouble(booking['location_longitude']),
      'returnLat': _toDouble(booking['desired_return_latitude']),
      'returnLng': _toDouble(booking['desired_return_longitude']),
      'returnLocationText':
          booking['desired_return_location']?.toString() ?? '',
      'returnStatus': booking['return_status']?.toString() ?? '',
      'returnDriverName': booking['return_driver_name']?.toString() ?? '',
    };
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> &&
          decoded['error'] is String &&
          (decoded['error'] as String).isNotEmpty) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  Future<bool> _acceptBooking(String bookingToken) async {
    final jwtToken = AuthTokenStore().token;
    final driverId =
        AuthTokenStore().userId ?? '1'; // Replace with actual driver id logic
    final url = Uri.parse('$apiBase/api/bookings/$bookingToken');
    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'status': 'accepted',
          'driver_id': driverId,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking accepted!')),
        );
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to accept booking'),
              backgroundColor: Colors.red),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Network error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<bool> _declineBooking(String bookingToken) async {
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/bookings/$bookingToken');
    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'status': 'declined',
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Booking declined. Other drivers can now accept it.')),
        );
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to decline booking'),
              backgroundColor: Colors.red),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Network error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<bool> _acceptReturnRequest(String bookingToken) async {
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/bookings/$bookingToken/accept-return');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return request accepted')),
        );
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractErrorMessage(response)),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Network error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<bool> _declineReturnRequest(String bookingToken) async {
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/bookings/$bookingToken/decline-return');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return request declined')),
        );
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractErrorMessage(response)),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Network error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  List<Map<String, dynamic>> _incomingRequests = [];
  Map<String, dynamic>? _myAcceptedRequest;
  int _parkedToday = 0;
  int _totalParked = 0;
  bool _isLoading = false;
  bool _isLoadingNotifications = false;
  bool _isUpdatingAvailability = false;
  String _driverAvailabilityStatus = 'available';
  int _unreadNotificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  String? _fetchError;
  Timer? _refreshTimer;
  Timer? _notificationPollTimer;

  @override
  void initState() {
    super.initState();
    _fetchPendingBookings();
    _loadDriverAvailability();
    _loadDriverStats();
    _loadNotifications();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _fetchPendingBookings(silent: true),
    );
    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadNotifications(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _notificationPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchPendingBookings({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final jwtToken = AuthTokenStore().token;

    try {
      final availableUrl = Uri.parse('$apiBase/api/bookings/available');
      final availableResponse = await http.get(
        availableUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      final returnAvailableUrl =
          Uri.parse('$apiBase/api/bookings/return/available');
      final returnAvailableResponse = await http.get(
        returnAvailableUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      List<dynamic> pickupBookings = [];
      List<dynamic> returnBookings = [];
      String? fetchError;

      if (availableResponse.statusCode == 200) {
        final data = jsonDecode(availableResponse.body);
        pickupBookings = (data['bookings'] as List<dynamic>? ?? []);
      } else {
        final allUrl = Uri.parse('$apiBase/api/bookings');
        final allResponse = await http.get(
          allUrl,
          headers: {
            'Content-Type': 'application/json',
            if (jwtToken != null && jwtToken.isNotEmpty)
              'Authorization': 'Bearer $jwtToken',
          },
        );

        if (allResponse.statusCode == 200) {
          final data = jsonDecode(allResponse.body);
          final allBookings = (data['bookings'] as List<dynamic>? ?? []);
          pickupBookings = allBookings
              .where((b) =>
                  (b['status'] == 'pending' || b['status'] == 'booked') &&
                  (b['driver_id'] == null) &&
                  (b['location_id'] == null) &&
                  (b['slot_number'] == null))
              .toList();
        } else {
          final availableErr = _extractErrorMessage(availableResponse);
          final allErr = _extractErrorMessage(allResponse);
          fetchError =
              'Could not load pickup requests: $availableErr | $allErr';
        }
      }

      if (returnAvailableResponse.statusCode == 200) {
        final data = jsonDecode(returnAvailableResponse.body);
        returnBookings = (data['bookings'] as List<dynamic>? ?? []);
      } else if (returnAvailableResponse.statusCode != 404) {
        final err = _extractErrorMessage(returnAvailableResponse);
        fetchError = fetchError == null
            ? 'Could not load return requests: $err'
            : '$fetchError | Return requests error: $err';
      }

      Map<String, dynamic>? acceptedRequest;
      final myCurrentUrl = Uri.parse('$apiBase/api/bookings/driver/current');
      final myCurrentResponse = await http.get(
        myCurrentUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (myCurrentResponse.statusCode == 200) {
        final myData = jsonDecode(myCurrentResponse.body);
        final myBooking = myData['booking'];
        if (myBooking is Map<String, dynamic>) {
          acceptedRequest = _toRequestMap(myBooking);
        }
      } else if (myCurrentResponse.statusCode != 404) {
        final err = _extractErrorMessage(myCurrentResponse);
        fetchError = fetchError == null
            ? 'Could not load accepted request: $err'
            : '$fetchError | Accepted request error: $err';
      }

      final mergedBookings = [...pickupBookings, ...returnBookings];
      mergedBookings.sort((a, b) {
        final idA = int.tryParse('${a['id'] ?? ''}') ??
            int.tryParse('${a['booking_id'] ?? ''}') ??
            0;
        final idB = int.tryParse('${b['id'] ?? ''}') ??
            int.tryParse('${b['booking_id'] ?? ''}') ??
            0;
        return idB.compareTo(idA);
      });

      if (acceptedRequest != null) {
        mergedBookings.removeWhere((b) =>
            (b['booking_token'] ?? b['id'] ?? '').toString() ==
            acceptedRequest!['id'].toString());
      }

      if (!mounted) return;
      setState(() {
        _incomingRequests = mergedBookings
            .map((b) => _toRequestMap(b as Map<String, dynamic>))
            .whereType<Map<String, dynamic>>()
            .toList();
        _myAcceptedRequest = acceptedRequest;
        _fetchError = fetchError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _incomingRequests = [];
        _myAcceptedRequest = null;
        _fetchError = 'Network error while loading requests';
      });
    } finally {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    final request = _incomingRequests.firstWhere(
      (r) => r['id'] == requestId,
    );

    final isReturnRequest =
        (request['requestType'] ?? '').toString().toLowerCase() == 'return';
    final accepted = isReturnRequest
        ? await _acceptReturnRequest(requestId)
        : await _acceptBooking(requestId);
    if (!accepted || !mounted) return;

    setState(() {
      _incomingRequests.removeWhere((r) => r['id'] == requestId);
      _myAcceptedRequest = request;
    });

    // Navigate to current request screen
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverCurrentRequestScreen(
          request: request,
          onRequestCompleted: _refreshDashboard,
          showPickupAction: !isReturnRequest,
        ),
      ),
    );
    _fetchPendingBookings(silent: true);
  }

  Future<void> _declineRequest(String requestId) async {
    final request = _incomingRequests.firstWhere(
      (r) => r['id'] == requestId,
    );
    final isReturnRequest =
        (request['requestType'] ?? '').toString().toLowerCase() == 'return';
    final declined = isReturnRequest
        ? await _declineReturnRequest(requestId)
        : await _declineBooking(requestId);
    if (!declined || !mounted) return;

    setState(() {
      _incomingRequests.removeWhere((r) => r['id'] == requestId);
    });
  }

  void _refreshDashboard() {
    _loadDriverStats(silent: true);
    _fetchPendingBookings(silent: true);
  }

  bool get _isDriverAvailable =>
      _driverAvailabilityStatus.toLowerCase() == 'available';

  Future<void> _loadDriverAvailability({bool silent = false}) async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    if (!silent && mounted) {
      setState(() {
        _isUpdatingAvailability = true;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/drivers/mine'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) {
        if (!silent && mounted) {
          setState(() {
            _isUpdatingAvailability = false;
          });
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final driver = data['driver'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _driverAvailabilityStatus =
            (driver?['status']?.toString() ?? 'available').toLowerCase();
        _isUpdatingAvailability = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() {
        _isUpdatingAvailability = false;
      });
    }
  }

  Future<void> _setDriverAvailability(bool available) async {
    if (_isUpdatingAvailability) return;

    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    setState(() {
      _isUpdatingAvailability = true;
    });

    try {
      final response = await http.patch(
        Uri.parse('$apiBase/api/drivers/mine/availability'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'available': available}),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _driverAvailabilityStatus = available ? 'available' : 'inactive';
          _isUpdatingAvailability = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              available
                  ? 'You are marked as Available'
                  : 'You are marked as Unavailable',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      setState(() {
        _isUpdatingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractErrorMessage(response)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdatingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _incomingReturnRequests => _incomingRequests
      .where(
        (r) => (r['requestType'] ?? '').toString().toLowerCase() == 'return',
      )
      .toList();

  List<Map<String, dynamic>> get _incomingPickupRequests => _incomingRequests
      .where(
        (r) => (r['requestType'] ?? '').toString().toLowerCase() != 'return',
      )
      .toList();

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

  Future<void> _loadDriverStats({bool silent = false}) async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/drivers/mine/stats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode != 200) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final stats = data['stats'] as Map<String, dynamic>? ?? {};
      final parkedTodayRaw = stats['parked_today'];
      final totalParkedRaw = stats['total_parked'];
      final parkedToday = parkedTodayRaw is int
          ? parkedTodayRaw
          : int.tryParse(parkedTodayRaw?.toString() ?? '') ?? 0;
      final totalParked = totalParkedRaw is int
          ? totalParkedRaw
          : int.tryParse(totalParkedRaw?.toString() ?? '') ?? 0;

      if (!mounted) return;
      setState(() {
        _parkedToday = parkedToday;
        _totalParked = totalParked;
      });
    } catch (_) {}
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

  String _acceptedStatusLabel(Map<String, dynamic> request) {
    final requestType = (request['requestType'] ?? '').toString().toLowerCase();
    if (requestType == 'return') {
      final returnStatus =
          (request['returnStatus'] ?? '').toString().toLowerCase();
      if (returnStatus == 'released') {
        return 'Security confirmed handover. Deliver to customer';
      }
      return 'Accepted return request';
    }
    final hasSlot = (request['slotNumber']?.toString().isNotEmpty ?? false);
    final status = (request['bookingStatus'] ?? '').toString().toLowerCase();
    if (!hasSlot) return 'Vehicle pickup pending';
    if (status == 'confirmed') return 'Parking confirmed by security';
    return 'Slot assigned. Waiting for security confirmation';
  }

  void _openAcceptedRequest(Map<String, dynamic> request) {
    final requestType = (request['requestType'] ?? '').toString().toLowerCase();
    final hasSlot = (request['slotNumber']?.toString().isNotEmpty ?? false);
    final showPickupAction = requestType == 'pickup' ? !hasSlot : false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverCurrentRequestScreen(
          request: request,
          onRequestCompleted: _refreshDashboard,
          showPickupAction: showPickupAction,
        ),
      ),
    );
  }

  void _viewRequestInMap(Map<String, dynamic> request) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverCurrentRequestScreen(
          request: request,
          onRequestCompleted: _refreshDashboard,
          showPickupAction: false,
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleExitWarning,
      child: Scaffold(
        appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.account_circle),
          tooltip: 'Profile',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DriverProfileScreen(),
              ),
            );
          },
        ),
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Requests',
            onPressed: _fetchPendingBookings,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAvailabilityCard(),
                      const SizedBox(height: 16),

                      if (_myAcceptedRequest != null) ...[
                        Text(
                          'My Accepted Request',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildAcceptedRequestCard(_myAcceptedRequest!),
                        const SizedBox(height: 24),
                      ],

                      // Return Requests Section
                      Text(
                        'Return Requests',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_fetchError != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _fetchError!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      if (_incomingReturnRequests.isEmpty)
                        _buildNoRequestsCard('No return requests at the moment')
                      else
                        Column(
                          children: _incomingReturnRequests
                              .map((request) => _buildRequestCard(request))
                              .toList(),
                        ),

                      const SizedBox(height: 20),

                      Text(
                        'Pickup Requests',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_incomingPickupRequests.isEmpty)
                        _buildNoRequestsCard('No pickup requests at the moment')
                      else
                        Column(
                          children: _incomingPickupRequests
                              .map((request) => _buildRequestCard(request))
                              .toList(),
                        ),

                      const SizedBox(height: 32),

                      // Your Stats Section
                      Text(
                        'Your Stats',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Stats Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Parked Today',
                              _parkedToday.toString(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              'Total Parked',
                              _totalParked.toString(),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDriverAvailable ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              _isDriverAvailable ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isDriverAvailable ? Icons.check_circle : Icons.pause_circle_filled,
            color: _isDriverAvailable
                ? Colors.green.shade700
                : Colors.red.shade700,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDriverAvailable
                      ? 'You are available for requests'
                      : 'You are unavailable for requests',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _isDriverAvailable
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Toggle to mark Available / Unavailable',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isDriverAvailable,
            onChanged: _isUpdatingAvailability
                ? null
                : (v) => _setDriverAvailability(v),
            activeColor: Colors.green.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildNoRequestsCard(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.green.shade600,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.green.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final isReturnRequest =
        (request['requestType'] ?? '').toString().toLowerCase() == 'return';
    final locationLabel = isReturnRequest ? 'Return To' : 'Pickup';
    final locationValue = isReturnRequest
        ? (request['returnLocationText']?.toString().isNotEmpty == true
            ? request['returnLocationText'].toString()
            : 'Customer location')
        : request['parkingLocation'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row - Name and Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['customerName'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request['vehicleModel'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        request['time'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isReturnRequest ? Icons.flag : Icons.location_on,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$locationLabel: $locationValue',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isDriverAvailable
                      ? () => _acceptRequest(request['id'])
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isReturnRequest ? 'Accept Return' : 'Accept',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _viewRequestInMap(request),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.blue.shade600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(
                    Icons.map_outlined,
                    size: 16,
                    color: Colors.blue.shade600,
                  ),
                  label: Text(
                    isReturnRequest ? 'Return Map' : 'View Map',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isDriverAvailable
                      ? () => _declineRequest(request['id'])
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.red.shade600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isReturnRequest ? 'Decline Return' : 'Decline',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedRequestCard(Map<String, dynamic> request) {
    final isReturnRequest =
        (request['requestType'] ?? '').toString().toLowerCase() == 'return';
    final slotText = (request['slotNumber']?.toString().isNotEmpty ?? false)
        ? request['slotNumber'].toString()
        : 'Not assigned';
    final locationText =
        request['parkingLocation']?.toString().isNotEmpty == true
            ? request['parkingLocation'].toString()
            : 'Not assigned';
    final returnLocationText =
        request['returnLocationText']?.toString().isNotEmpty == true
            ? request['returnLocationText'].toString()
            : 'Not specified';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_turned_in, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _acceptedStatusLabel(request),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request['customerName']?.toString() ?? 'Customer',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${request['vehicleModel'] ?? ''} (${request['vehicleNumber'] ?? ''})',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            isReturnRequest
                ? 'Return To: $returnLocationText'
                : 'Location: $locationText  |  Slot: $slotText',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openAcceptedRequest(request),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(isReturnRequest ? 'Open Return Map' : 'Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _viewRequestInMap(request),
                  icon: Icon(Icons.map_outlined, color: Colors.blue.shade700),
                  label: Text(
                    'View Map',
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.blue.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

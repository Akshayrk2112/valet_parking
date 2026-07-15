import 'dart:async';

import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'add_parking_location_screen.dart';
import 'register_drivers_screen.dart';
import 'register_security_screen.dart';
import 'admin_parking_locations_screen.dart';
import 'admin_drivers_screen.dart';
import 'admin_security_staff_screen.dart';
import 'admin_active_bookings_screen.dart';
import 'admin_booking_history_screen.dart';
import 'admin_payment_history_screen.dart';
import 'admin_declined_requests_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // Stats data - will be updated dynamically
  int _totalLocations = 0;
  int _totalDrivers = 0;
  int _activeBookings = 0;
  int _bookingHistoryCount = 0;
  int _securityStaff = 0;
  int _paymentHistoryCount = 0;
  int _declinedRequestsCount = 0;
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
    _updateStats();
    _loadNotifications();
    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadNotifications(silent: true),
    );
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateStats() async {
    await Future.wait([
      _fetchTotalLocationsCount(),
      _fetchTotalDriversCount(),
      _fetchSecurityStaffCount(),
      _fetchPaymentHistoryCount(),
      _fetchDeclinedRequestsCount(),
      _fetchActiveBookingsCount(),
      _fetchBookingHistoryCount(),
    ]);
  }

  Future<void> _fetchTotalLocationsCount() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/parking/locations'),
        headers: {
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final locations = (data['locations'] as List<dynamic>? ?? []);

      if (!mounted) return;
      setState(() {
        _totalLocations = locations.length;
      });
    } catch (_) {}
  }

  Future<void> _fetchTotalDriversCount() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/drivers/admin/count'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final countRaw = data['count'];
      final count = countRaw is int
          ? countRaw
          : int.tryParse(countRaw?.toString() ?? '0') ?? 0;

      if (!mounted) return;
      setState(() {
        _totalDrivers = count;
      });
    } catch (_) {}
  }

  Future<void> _fetchSecurityStaffCount() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/auth/security-staff'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final staff = (data['staff'] as List<dynamic>? ?? []);

      if (!mounted) return;
      setState(() {
        _securityStaff = staff.length;
      });
    } catch (_) {}
  }

  Future<void> _fetchPaymentHistoryCount() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List<dynamic>? ?? []);
      final count = bookings.where((entry) {
        final booking = Map<String, dynamic>.from(entry as Map);
        final paymentStatus =
            (booking['payment_status'] ?? '').toString().toLowerCase();
        return paymentStatus == 'paid' || paymentStatus == 'refunded';
      }).length;

      if (!mounted) return;
      setState(() {
        _paymentHistoryCount = count;
      });
    } catch (_) {}
  }

  Future<void> _fetchDeclinedRequestsCount() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List<dynamic>? ?? []);
      var count = 0;
      for (final entry in bookings) {
        final booking = Map<String, dynamic>.from(entry as Map);
        final declines = booking['declines'];
        if (declines is List) {
          count += declines.length;
        }
      }

      if (!mounted) return;
      setState(() {
        _declinedRequestsCount = count;
      });
    } catch (_) {}
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    if (!silent && mounted) {
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

  Future<void> _fetchActiveBookingsCount() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List<dynamic>? ?? []);

      final count = bookings.where((entry) {
        final booking = Map<String, dynamic>.from(entry as Map);
        final status =
            (booking['status'] ?? '').toString().toLowerCase().trim();
        if (status == 'cancelled') return false;
        final isValet = booking['driver_id'] != null;
        if (isValet) {
          final returnStatus =
              (booking['return_status'] ?? '').toString().toLowerCase().trim();
          return returnStatus != 'completed';
        }
        return status != 'completed';
      }).length;

      if (!mounted) return;
      setState(() {
        _activeBookings = count;
      });
    } catch (_) {}
  }

  Future<void> _fetchBookingHistoryCount() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List<dynamic>? ?? []);

      if (!mounted) return;
      setState(() {
        _bookingHistoryCount = bookings.length;
      });
    } catch (_) {}
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
    if (shouldLogout == true) {
      // Clear token from AuthTokenStore and SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('jwt_token');
      } catch (_) {}
      // Also clear from AuthTokenStore singleton if used
      try {
        AuthTokenStore().token = null;
      } catch (_) {}
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (context) => const LoginScreen(fromLogout: true)),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleExitWarning,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.9),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add Parking Location Button
                  _buildActionCard(
                    icon: Icons.location_on,
                    iconColor: Colors.blue.shade600,
                    title: 'Add Parking Location',
                    subtitle: 'Create new parking facility',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddParkingLocationScreen(
                            onParkingAdded: (_) {
                              _fetchTotalLocationsCount();
                            },
                          ),
                        ),
                      ).then((_) => _fetchTotalLocationsCount());
                    },
                  ),

                  const SizedBox(height: 12),

                  // Register Drivers Button
                  _buildActionCard(
                    icon: Icons.people,
                    iconColor: Colors.green.shade600,
                    title: 'Register Drivers',
                    subtitle: 'Add valet drivers',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RegisterDriversScreen(
                            onDriverAdded: () {
                              _fetchTotalDriversCount();
                            },
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // Register Security Button
                  _buildActionCard(
                    icon: Icons.security,
                    iconColor: Colors.orange.shade600,
                    title: 'Register Security',
                    subtitle: 'Add security staff',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RegisterSecurityScreen(
                            onSecurityAdded: () {
                              _fetchSecurityStaffCount();
                            },
                          ),
                        ),
                      ).then((_) => _fetchSecurityStaffCount());
                    },
                  ),

                  const SizedBox(height: 32),

                  // Quick Stats
                  Text(
                    'Quick Stats',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AdminParkingLocationsScreen(
                                  totalLocations: _totalLocations,
                                ),
                              ),
                            ).then((_) => _fetchTotalLocationsCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.location_on,
                            iconColor: Colors.blue.shade600,
                            label: 'Total Locations',
                            value: _totalLocations.toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminDriversScreen(
                                  totalDrivers: _totalDrivers,
                                ),
                              ),
                            ).then((_) => _fetchTotalDriversCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.directions_car,
                            iconColor: Colors.green.shade600,
                            label: 'Total Drivers',
                            value: _totalDrivers.toString(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AdminBookingHistoryScreen(),
                              ),
                            ).then((_) => _fetchBookingHistoryCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.history,
                            iconColor: Colors.indigo.shade600,
                            label: 'Booking History',
                            value: _bookingHistoryCount.toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminActiveBookingsScreen(
                                  activeBookings: _activeBookings,
                                ),
                              ),
                            ).then((_) => _fetchActiveBookingsCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.bookmark,
                            iconColor: Colors.purple.shade600,
                            label: 'Active Bookings',
                            value: _activeBookings.toString(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminSecurityStaffScreen(
                                  totalSecurityStaff: _securityStaff,
                                ),
                              ),
                            ).then((_) => _fetchSecurityStaffCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.security,
                            iconColor: Colors.orange.shade600,
                            label: 'Security Staff',
                            value: _securityStaff.toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AdminPaymentHistoryScreen(),
                              ),
                            ).then((_) => _fetchPaymentHistoryCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.receipt_long,
                            iconColor: Colors.teal.shade600,
                            label: 'Payment History',
                            value: _paymentHistoryCount.toString(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AdminDeclinedRequestsScreen(),
                              ),
                            ).then((_) => _fetchDeclinedRequestsCount());
                          },
                          child: _buildStatCard(
                            icon: Icons.report_problem,
                            iconColor: Colors.red.shade700,
                            label: 'Declined Requests',
                            value: _declinedRequestsCount.toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: SizedBox.shrink()),
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

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}

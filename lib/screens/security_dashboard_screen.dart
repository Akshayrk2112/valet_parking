import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'security_parking_layout_screen.dart';
import 'login_screen.dart';
import '../core/config.dart';
import '../core/utils/auth_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({Key? key}) : super(key: key);

  @override
  State<SecurityDashboardScreen> createState() =>
      _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  String _parkingName = 'Parking A';
  int? _parkingLocationId;
  bool _isLoadingAssignment = false;
  bool _isLoadingNotifications = false;
  int _unreadNotificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  Timer? _notificationPollTimer;
  int _availableSpaces = 0;
  int _pendingSpaces = 0;
  int _occupiedSpaces = 0;
  int _totalCapacity = 0;
  DateTime? _lastBackPressed;
  bool _isRefreshing = false;

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
    _loadSecurityAssignment();
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

  Future<void> _loadSecurityAssignment() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    setState(() {
      _isLoadingAssignment = true;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/auth/security-assignment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final assignedName =
            (data['parking_location_name'] ?? '').toString().trim();
        final assignedIdRaw = data['parking_location_id'];
        final assignedId = assignedIdRaw is int
            ? assignedIdRaw
            : int.tryParse(assignedIdRaw?.toString() ?? '');
        if (assignedName.isNotEmpty || assignedId != null) {
          setState(() {
            _parkingName = assignedName.isNotEmpty
                ? assignedName
                : (data['parking_location'] ?? '').toString();
            _parkingLocationId = assignedId;
          });
          await _loadSlotCounts();
        }
      }
    } catch (_) {
      // Keep fallback parking name if assignment fetch fails.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAssignment = false;
        });
      }
    }
  }

  Future<void> _refreshDashboard() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      await _loadSecurityAssignment();
      await _loadSlotCounts();
      await _loadNotifications();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadSlotCounts() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) return;

    try {
      final locationsResponse = await http.get(
        Uri.parse('$apiBase/api/parking/locations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (locationsResponse.statusCode != 200) return;

      final data = jsonDecode(locationsResponse.body) as Map<String, dynamic>;
      final locations = (data['locations'] as List<dynamic>? ?? []);

      final assignedName = _parkingName.trim().toLowerCase();
      final assignedId = _parkingLocationId;
      final matched = locations.cast<Map>().firstWhere(
            (loc) {
              final idMatch = assignedId != null &&
                  loc['id'].toString() == assignedId.toString();
              final nameMatch =
                  (loc['name'] ?? '').toString().trim().toLowerCase() ==
                      assignedName;
              return idMatch || nameMatch;
            },
            orElse: () => {},
          );

      if (matched.isEmpty) return;
      final locationId = matched['id'];
      if (locationId == null) return;

      final slotsResponse = await http.get(
        Uri.parse('$apiBase/api/parking/slots/$locationId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );
      if (slotsResponse.statusCode != 200) return;

      final slotsData = jsonDecode(slotsResponse.body) as Map<String, dynamic>;
      final slots = (slotsData['slots'] as List<dynamic>? ?? []);

      int available = 0;
      int pending = 0;
      int occupied = 0;

      for (final raw in slots) {
        final slot = Map<String, dynamic>.from(raw as Map);
        final status = (slot['status'] ?? '').toString().toLowerCase();
        final bookingStatus =
            (slot['booking_status'] ?? '').toString().toLowerCase();

        if (status == 'available') {
          available += 1;
          continue;
        }

        if (bookingStatus == 'pending' || status == 'reserved') {
          pending += 1;
          continue;
        }

        if (bookingStatus == 'confirmed' || status == 'occupied') {
          occupied += 1;
          continue;
        }
      }

      if (!mounted) return;
      setState(() {
        _availableSpaces = available;
        _pendingSpaces = pending;
        _occupiedSpaces = occupied;
        _totalCapacity = slots.length;
      });
    } catch (_) {}
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
                    ? const Center(
                        child: Text('No notifications yet'),
                      )
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleExitWarning,
      child: Scaffold(
        appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Security Dashboard'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isRefreshing
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
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshDashboard,
            tooltip: 'Refresh',
          ),
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
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Parking Name Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.orange.shade200,
                      width: 2,
                    ),
                  ),
                ),
                child: Center(
                  child: _isLoadingAssignment
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              Colors.orange.shade600,
                            ),
                          ),
                        )
                      : Text(
                          _parkingName,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade600,
                          ),
                        ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Slot Summary Section
                    Text(
                      'SLOT SUMMARY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Stats Cards Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.check_circle,
                            iconColor: Colors.green.shade600,
                            label: 'AVAILABLE',
                            value: _availableSpaces.toString(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.schedule,
                            iconColor: Colors.amber.shade600,
                            label: 'PENDING',
                            value: _pendingSpaces.toString(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.close,
                            iconColor: Colors.red.shade600,
                            label: 'OCCUPIED',
                            value: _occupiedSpaces.toString(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.layers,
                            iconColor: Colors.blue.shade600,
                            label: 'TOTAL',
                            value: _totalCapacity.toString(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Quick Actions Section
                    Text(
                      'QUICK ACTIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Parking Space Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SecurityParkingLayoutScreen(
                                parkingName: _parkingName,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.grid_3x3),
                        label: const Text('View Parking Layout'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}

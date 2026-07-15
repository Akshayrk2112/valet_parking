import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class AdminDriversScreen extends StatefulWidget {
  final int totalDrivers;

  const AdminDriversScreen({
    Key? key,
    required this.totalDrivers,
  }) : super(key: key);

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoading = false;
  int? _deletingDriverId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
        final error = decoded['error']?.toString();
        if (error != null && error.isNotEmpty) return error;
      }
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  Future<void> _loadDrivers() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() {
        _errorMessage = 'Missing login session token';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/drivers/admin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode != 200) {
        setState(() {
          _errorMessage = _extractErrorMessage(response);
          _drivers = [];
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['drivers'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _drivers = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
        _drivers = [];
        _isLoading = false;
      });
    }
  }

  String _safeInitial(String? name) {
    final value = (name ?? '').trim();
    if (value.isEmpty) return '?';
    return value[0].toUpperCase();
  }

  String _prettyStatus(String raw) {
    final value = raw.toLowerCase();
    if (value == 'available') return 'Available';
    if (value == 'busy') return 'Busy';
    return 'Unavailable';
  }

  Color _statusColor(String raw) {
    final value = raw.toLowerCase();
    if (value == 'available') return Colors.green.shade700;
    if (value == 'busy') return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Future<void> _confirmDeleteDriver(
    Map<String, dynamic> driver, {
    bool closeDetailsSheet = false,
  }) async {
    final driverId = int.tryParse(driver['user_id']?.toString() ?? '');
    if (driverId == null) return;

    final name = driver['name']?.toString() ?? 'this driver';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Driver'),
        content: Text(
          'Delete $name? This removes the driver login and driver profile. Drivers with active bookings cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;
    await _deleteDriver(driverId, name, closeDetailsSheet: closeDetailsSheet);
  }

  Future<void> _deleteDriver(
    int driverId,
    String name, {
    bool closeDetailsSheet = false,
  }) async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing login session token'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _deletingDriverId = driverId;
    });

    try {
      final response = await http.delete(
        Uri.parse('$apiBase/api/drivers/admin/$driverId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _drivers.removeWhere(
            (driver) => driver['user_id']?.toString() == driverId.toString(),
          );
          _deletingDriverId = null;
        });
        if (closeDetailsSheet && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name deleted')),
        );
        return;
      }

      setState(() {
        _deletingDriverId = null;
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
        _deletingDriverId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete driver: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDriverDetails(Map<String, dynamic> driver) {
    final status = (driver['status'] ?? 'inactive').toString();
    final driverId = int.tryParse(driver['user_id']?.toString() ?? '');
    final isDeleting = driverId != null && _deletingDriverId == driverId;

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Driver Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDetailRow('Name', driver['name']?.toString() ?? 'N/A'),
                _buildDetailRow('Driver ID', '${driver['user_id'] ?? 'N/A'}'),
                _buildDetailRow('Email', driver['email']?.toString() ?? 'N/A'),
                _buildDetailRow('Phone', driver['phone']?.toString() ?? 'N/A'),
                _buildDetailRow(
                  'License Number',
                  driver['license_number']?.toString() ?? 'N/A',
                ),
                _buildDetailRow('Availability', _prettyStatus(status)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _statusColor(status).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Current Status: ${_prettyStatus(status)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(status),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isDeleting
                        ? null
                        : () => _confirmDeleteDriver(
                              driver,
                              closeDetailsSheet: true,
                            ),
                    icon: isDeleting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.red.shade700,
                              ),
                            ),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(isDeleting ? 'Deleting...' : 'Delete Driver'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final name = driver['name']?.toString() ?? 'Unknown';
    final driverId = int.tryParse(driver['user_id']?.toString() ?? '');
    final isDeleting = driverId != null && _deletingDriverId == driverId;
    final status = (driver['status'] ?? 'inactive').toString();
    final statusLabel = _prettyStatus(status);
    final statusColor = _statusColor(status);

    return GestureDetector(
      onTap: () => _showDriverDetails(driver),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _safeInitial(name),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${driver['user_id']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    driver['license_number']?.toString() ?? 'No license number',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            isDeleting
                ? SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.red.shade700,
                          ),
                        ),
                      ),
                    ),
                  )
                : PopupMenuButton<String>(
                    tooltip: 'Driver actions',
                    onSelected: (value) {
                      if (value == 'delete') {
                        _confirmDeleteDriver(driver);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete driver',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drivers'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDrivers,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red.shade600,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Drivers: ${_drivers.length}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _drivers.isEmpty
                              ? Center(
                                  child: Text(
                                    'No registered drivers found',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _drivers.length,
                                  itemBuilder: (context, index) =>
                                      _buildDriverCard(_drivers[index]),
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

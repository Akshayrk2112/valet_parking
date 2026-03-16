import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class AdminSecurityStaffScreen extends StatefulWidget {
  final int totalSecurityStaff;

  const AdminSecurityStaffScreen({
    Key? key,
    required this.totalSecurityStaff,
  }) : super(key: key);

  @override
  State<AdminSecurityStaffScreen> createState() =>
      _AdminSecurityStaffScreenState();
}

class _AdminSecurityStaffScreenState extends State<AdminSecurityStaffScreen> {
  List<Map<String, dynamic>> _securityStaff = [];
  List<String> _parkingLocations = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _fetchSecurityStaff(),
        _fetchParkingLocations(),
      ]);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
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

  Future<void> _fetchSecurityStaff() async {
    final jwtToken = AuthTokenStore().token;
    final response = await http.get(
      Uri.parse('$apiBase/api/auth/security-staff'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode != 200) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load security staff: '
            '${_extractErrorMessage(response)}';
        _securityStaff = [];
      });
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final staff = (data['staff'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    if (!mounted) return;
    setState(() {
      _securityStaff = staff;
    });
  }

  Future<void> _fetchParkingLocations() async {
    final jwtToken = AuthTokenStore().token;
    final response = await http.get(
      Uri.parse('$apiBase/api/parking/locations'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode != 200) {
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final locations = (data['locations'] as List<dynamic>? ?? [])
        .map((item) => (item as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList();
    locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _parkingLocations = locations;
    });
  }

  Future<void> _updateAssignedParking(
    int userId,
    String? parkingLocation,
  ) async {
    final jwtToken = AuthTokenStore().token;
    final response = await http.patch(
      Uri.parse('$apiBase/api/auth/security-staff/$userId/assignment'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'parking_location': parkingLocation,
      }),
    );

    if (!mounted) return;
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractErrorMessage(response)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      final index =
          _securityStaff.indexWhere((staff) => staff['user_id'] == userId);
      if (index != -1) {
        _securityStaff[index]['parking_location'] = parkingLocation;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parkingLocation == null || parkingLocation.isEmpty
              ? 'Parking assignment cleared'
              : 'Assigned to $parkingLocation',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green.shade600,
      ),
    );
  }

  Future<void> _showEditAssignmentDialog(Map<String, dynamic> staff) async {
    final userId = staff['user_id'] as int?;
    if (userId == null) return;

    final options = ['Unassigned', ..._parkingLocations];
    String selected = (staff['parking_location'] ?? '').toString().trim();
    if (selected.isEmpty || !options.contains(selected)) {
      selected = 'Unassigned';
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Assigned Parking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                staff['name']?.toString() ?? 'Security Staff',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButton<String>(
                  value: selected,
                  isExpanded: true,
                  underline: const SizedBox(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  items: options
                      .map(
                        (location) => DropdownMenuItem(
                          value: location,
                          child: Text(location),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selected = value;
                    });
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateAssignedParking(
                  userId,
                  selected == 'Unassigned' ? null : selected,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  String _safeInitial(String? name) {
    final value = (name ?? '').trim();
    if (value.isEmpty) return '?';
    return value[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Staff'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Security Staff: ${_securityStaff.length}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _securityStaff.isEmpty
                              ? Center(
                                  child: Text(
                                    'No registered security staff found',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _securityStaff.length,
                                  itemBuilder: (context, index) {
                                    final staff = _securityStaff[index];
                                    final name =
                                        staff['name']?.toString() ?? 'Unknown';
                                    final email =
                                        staff['email']?.toString() ?? 'N/A';
                                    final phone =
                                        staff['phone']?.toString() ?? 'N/A';
                                    final location = (staff['parking_location']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true)
                                        ? staff['parking_location'].toString()
                                        : 'Unassigned';
                                    final status =
                                        staff['status']?.toString() ??
                                            'inactive';
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.05),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    _safeInitial(name),
                                                    style: TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors
                                                          .orange.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .grey.shade800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'ID: ${staff['user_id']}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      status.toLowerCase() ==
                                                              'active'
                                                          ? 'Status: Active'
                                                          : 'Status: Inactive',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            status.toLowerCase() ==
                                                                    'active'
                                                                ? Colors.green
                                                                    .shade700
                                                                : Colors.red
                                                                    .shade700,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Email: $email',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Phone: $phone',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on,
                                                  size: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    'Assigned Parking: $location',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade700,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () =>
                                                  _showEditAssignmentDialog(
                                                      staff),
                                              icon: const Icon(
                                                Icons.edit_location_alt,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                  'Change Assigned Parking'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.orange.shade600,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

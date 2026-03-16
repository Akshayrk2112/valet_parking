import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/custom_drawer.dart';
import '../core/utils/validators.dart';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import 'valet_booking_confirmed_screen.dart';

class BookValetScreen extends StatefulWidget {
  const BookValetScreen({Key? key}) : super(key: key);

  @override
  State<BookValetScreen> createState() => _BookValetScreenState();
}

class _BookValetScreenState extends State<BookValetScreen> {
  String? _jwtToken;
  final _formKey = GlobalKey<FormState>();
  final _vehicleNameController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _locationController = TextEditingController();

  late TimeOfDay _selectedTime;

  LatLng? _currentLocation;
  bool _locationShared = false;

  double _locationCharges = 50;
  double _totalCharges = 50;

  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);

    _getCurrentLocation();
    _addListenersToControllers();
    _calculateTotalCharges();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Retrieve token from AuthTokenStore singleton
    _jwtToken = AuthTokenStore().token;
  }

  void _addListenersToControllers() {
    _vehicleNameController.addListener(_validateForm);
    _vehicleNumberController.addListener(_validateForm);
    _locationController.addListener(_validateForm);
  }

  void _validateForm() {
    setState(() {
      bool vehicleFieldsValid = _vehicleNameController.text.isNotEmpty &&
          _vehicleNumberController.text.isNotEmpty;

      bool locationFieldValid = _locationShared;

      _isFormValid = vehicleFieldsValid && locationFieldValid;
    });
  }

  void _calculateTotalCharges() {
    _totalCharges = _locationCharges;
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {});
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _shareCurrentLocation() {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to fetch location. Please try again.'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _locationController.text =
          'Lat: ${_currentLocation!.latitude.toStringAsFixed(6)}, Lng: ${_currentLocation!.longitude.toStringAsFixed(6)}';
      _locationShared = true;
      _validateForm();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location shared successfully!'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _calculateTotalCharges();
      });
    }
  }

  void _confirmBooking() async {
    if (!_formKey.currentState!.validate() || !_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final bookingTime = DateTime.now().toIso8601String();
    final url = Uri.parse('$apiBase/api/bookings');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (_jwtToken != null && _jwtToken!.isNotEmpty)
          'Authorization': 'Bearer $_jwtToken',
      },
      body: jsonEncode({
        'vehicle_number': _vehicleNumberController.text,
        'vehicle_type': _vehicleNameController.text,
        'booking_time': bookingTime,
        'customer_latitude': _currentLocation?.latitude,
        'customer_longitude': _currentLocation?.longitude,
      }),
    );

    if (response.statusCode == 201) {
      Map<String, dynamic>? responseData;
      try {
        responseData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        responseData = null;
      }

      final booking =
          responseData != null && responseData['booking'] is Map<String, dynamic>
              ? responseData['booking'] as Map<String, dynamic>
              : null;

      final bookingId = (booking?['booking_token'] ??
              booking?['id'] ??
              booking?['booking_id'] ??
              'N/A')
          .toString();

      DateTime parsedBookingTime = DateTime.now();
      final bookingTimeValue = booking?['booking_time'];
      if (bookingTimeValue != null) {
        parsedBookingTime =
            DateTime.tryParse(bookingTimeValue.toString()) ?? parsedBookingTime;
      }

      final pickupTime =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ValetBookingConfirmedScreen(
            bookingId: bookingId,
            vehicleName: _vehicleNameController.text.trim(),
            vehicleNumber: _vehicleNumberController.text.trim(),
            pickupTime: pickupTime,
            bookingTime: parsedBookingTime,
            pickupLocation: _locationController.text.trim(),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed: ${response.body}'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPricingRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Driver'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: const Text(
                  'Book a Driver',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFormLabel('Vehicle Name'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _vehicleNameController,
                        validator: validateVehicleModel,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter vehicle name',
                          prefixIcon: Icons.directions_car,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFormLabel('Vehicle Number'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _vehicleNumberController,
                        validator: validateVehicleNumber,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter vehicle number',
                          prefixIcon: Icons.confirmation_number,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFormLabel('Pickup Time'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _selectTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.access_time,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFormLabel('Pickup Location'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.my_location,
                              color: Colors.blue.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Share Your Current Location',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Send your GPS location to nearby drivers',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _shareCurrentLocation,
                          icon: const Icon(Icons.location_on),
                          label: Text(_locationShared
                              ? 'Location Shared'
                              : 'Share Location'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (_locationShared) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.shade300,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Location Shared',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildLocationInfoRow(
                                  'Latitude',
                                  _currentLocation!.latitude
                                      .toStringAsFixed(6)),
                              const SizedBox(height: 8),
                              _buildLocationInfoRow(
                                  'Longitude',
                                  _currentLocation!.longitude
                                      .toStringAsFixed(6)),
                              const SizedBox(height: 8),
                              _buildLocationInfoRow(
                                'Status',
                                'Location shared to nearby drivers',
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Price Summary',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildPricingRow(
                              'Location',
                              'Rs${_locationCharges.toStringAsFixed(0)}',
                            ),
                            const SizedBox(height: 8),
                            Divider(color: Colors.blue.shade300),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade600,
                                  ),
                                ),
                                Text(
                                  'Rs${_totalCharges.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isFormValid ? _confirmBooking : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            disabledBackgroundColor: Colors.grey.shade400,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Confirm Booking',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blue.shade600,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(
        prefixIcon,
        color: Colors.grey.shade600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.blue.shade600,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.red.shade600,
          width: 2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.red.shade600,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
    );
  }

  @override
  void dispose() {
    _vehicleNameController.dispose();
    _vehicleNumberController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}



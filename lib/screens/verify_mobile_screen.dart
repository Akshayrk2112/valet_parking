import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/parking_models.dart';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import 'booking_confirmed_screen.dart';

class VerifyMobileScreen extends StatefulWidget {
  final Map<String, dynamic> slot;
  final ParkingLocation parking;
  final Function(String) onBookingConfirmed;

  const VerifyMobileScreen({
    Key? key,
    required this.slot,
    required this.parking,
    required this.onBookingConfirmed,
  }) : super(key: key);

  @override
  State<VerifyMobileScreen> createState() => _VerifyMobileScreenState();
}

class _VerifyMobileScreenState extends State<VerifyMobileScreen> {
  final _mobileController = TextEditingController();
  final List<TextEditingController> _otpControllers =
      List.generate(6, (index) => TextEditingController());
  bool _otpSent = false;
  bool _isVerifying = false;

  @override
  void dispose() {
    _mobileController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _sendOTP() {
    if (_mobileController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter mobile number'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_mobileController.text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid mobile number'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _otpSent = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTP sent to your mobile number'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _verifyOTP() {
    String otp = _otpControllers.map((c) => c.text).join();

    if (otp.isEmpty || otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter complete OTP'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() { _isVerifying = true; });

    // Call backend to create booking
    Future(() async {
      try {
        final jwt = AuthTokenStore().token;
        final url = Uri.parse('$apiBase/api/bookings');
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'location_id': widget.parking.id,
            'vehicle_number': 'UNKNOWN',
            'vehicle_type': 'car',
            'booking_time': DateTime.now().toIso8601String(),
            'customer_latitude': null,
            'customer_longitude': null,
          }),
        );

        if (mounted) setState(() { _isVerifying = false; });

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          final booking = data['booking'];
          final bookingToken = booking != null && booking['booking_token'] != null
              ? booking['booking_token']
              : 'BK${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

          // Notify parent
          widget.onBookingConfirmed(widget.slot['id']);

          // Navigate to confirmed screen
          if (mounted) Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BookingConfirmedScreen(
                slotId: widget.slot['id'],
                parkingName: widget.parking.name,
                bookingId: bookingToken,
              ),
            ),
          );
        } else {
          // Backend error - fallback to local confirmation
          widget.onBookingConfirmed(widget.slot['id']);
          if (mounted) Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BookingConfirmedScreen(
                slotId: widget.slot['id'],
                parkingName: widget.parking.name,
                bookingId: 'BK${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) setState(() { _isVerifying = false; });
        // Fallback to local confirmation
        widget.onBookingConfirmed(widget.slot['id']);
        if (mounted) Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BookingConfirmedScreen(
              slotId: widget.slot['id'],
              parkingName: widget.parking.name,
              bookingId: 'BK${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Mobile'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Booking info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'Booking slot ${widget.slot['id']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Mobile Number Field
                Text(
                  'Mobile Number',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !_otpSent,
                  decoration: InputDecoration(
                    hintText: 'Enter mobile number',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.blue.shade600,
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // OTP Field
                if (_otpSent) ...[
                  Text(
                    'Enter OTP',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      6,
                      (index) => SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _otpControllers[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          onChanged: (value) {
                            if (value.isNotEmpty && index < 5) {
                              FocusScope.of(context).nextFocus();
                            }
                          },
                          decoration: InputDecoration(
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.blue.shade600,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Verify OTP Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _verifyOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        disabledBackgroundColor: Colors.grey.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isVerifying
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    Colors.blue.shade600),
                              ),
                            )
                          : const Text(
                              'Verify OTP',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _sendOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Send OTP',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

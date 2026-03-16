import 'package:flutter/material.dart';
import '../core/utils/gmail_validator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/config.dart';

class RegisterSecurityScreen extends StatefulWidget {
  final VoidCallback onSecurityAdded;

  const RegisterSecurityScreen({
    Key? key,
    required this.onSecurityAdded,
  }) : super(key: key);

  @override
  State<RegisterSecurityScreen> createState() => _RegisterSecurityScreenState();
}

class _RegisterSecurityScreenState extends State<RegisterSecurityScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _parkingLocationController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _parkingLocationController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _registerSecurity() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final parkingLocation = _parkingLocationController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        parkingLocation.isEmpty ||
        password.isEmpty) {
      _showError('Please fill all fields');
      return;
    }
    if (phone.length < 10) {
      _showError('Phone number must be at least 10 digits');
      return;
    }
    final emailError = validateGmail(email);
    if (emailError != null) {
      _showError(emailError);
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse('$apiBase/api/auth/register');
    final Map<String, dynamic> data = {
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'location': parkingLocation,
      'role': 'security',
    };
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      setState(() {
        _isLoading = false;
      });
      if (response.statusCode == 201) {
        _showCredentialsDialog(
          staffName: name,
          email: email,
          phone: phone,
          parkingLocation: parkingLocation,
        );
      } else {
        final msg = json.decode(response.body)['message'] ?? 'Registration failed';
        _showError(msg);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Error: $e');
    }
  }

  void _showCredentialsDialog({
    required String staffName,
    required String email,
    required String phone,
    required String parkingLocation,
  }) {
    final enteredPassword = _passwordController.text;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Security Staff Registered Successfully'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Login Credentials:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            _buildCredentialRow('Name', staffName),
            const SizedBox(height: 12),
            _buildCredentialRow('Email', email),
            const SizedBox(height: 12),
            _buildCredentialRow('Phone', phone),
            const SizedBox(height: 12),
            _buildCredentialRow('Parking', parkingLocation),
            const SizedBox(height: 12),
            _buildCredentialRow('Password', enteredPassword),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'Please save these credentials securely. The security staff can use these to login.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSecurityAdded();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Security staff registered successfully!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  Widget _buildCredentialRow(String label, String value) {
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
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Security Staff'),
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
                // Name
                _buildFormLabel('Staff Name'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  decoration: _buildInputDecoration('Enter staff name'),
                  validator: (value) => value == null || value.isEmpty ? 'Enter staff name' : null,
                ),
                const SizedBox(height: 20),
                // Email
                _buildFormLabel('Email Address'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _buildInputDecoration('e.g., security@example.com'),
                  validator: validateGmail,
                ),
                const SizedBox(height: 20),
                // Mobile Number
                _buildFormLabel('Phone Number'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _buildInputDecoration('e.g., 9876543210'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter phone number'
                      : (value.length < 10
                          ? 'Phone number must be at least 10 digits'
                          : null),
                ),
                const SizedBox(height: 20),
                // Parking Location
                _buildFormLabel('Parking Location'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _parkingLocationController,
                  decoration: _buildInputDecoration('e.g., Parking A'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter parking location'
                      : null,
                ),
                const SizedBox(height: 20),
                // Password
                _buildFormLabel('Password'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _buildInputDecoration('Enter password'),
                  validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 40),
                // Register Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _registerSecurity,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.blue.shade600,
                              ),
                            ),
                          )
                        : const Text(
                            'Register Security Staff',
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
      ),
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

  InputDecoration _buildInputDecoration(String hint, {String? counterText}) {
    return InputDecoration(
      hintText: hint,
      counterText: counterText ?? '',
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
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/utils/gmail_validator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/config.dart';

class RegisterDriversScreen extends StatefulWidget {
  final VoidCallback onDriverAdded;

  const RegisterDriversScreen({
    Key? key,
    required this.onDriverAdded,
  }) : super(key: key);

  @override
  State<RegisterDriversScreen> createState() => _RegisterDriversScreenState();
}

class _RegisterDriversScreenState extends State<RegisterDriversScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _licenseController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _licenseController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _registerDriver() async {
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _licenseController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse('$apiBase/api/auth/register');
    final Map<String, dynamic> data = {
      'name': _nameController.text,
      'email': _emailController.text,
      'password': _passwordController.text,
      'phone': _phoneController.text,
      'role': 'driver',
      'license_number': _licenseController.text,
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
          driverName: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
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
    required String driverName,
    required String email,
    required String phone,
  }) {
    final enteredPassword = _passwordController.text;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Driver Registered Successfully'),
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
            _buildCredentialRow('Name', driverName),
            const SizedBox(height: 12),
            _buildCredentialRow('Email', email),
            const SizedBox(height: 12),
            _buildCredentialRow('Username', phone),
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
                'Please save these credentials securely. The driver can use these to login.',
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
              widget.onDriverAdded();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Driver registered successfully!'),
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
        title: const Text('Register Drivers'),
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
                _buildFormLabel('Driver Name'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  decoration: _buildInputDecoration('Enter driver name'),
                  validator: (value) => value == null || value.isEmpty ? 'Enter driver name' : null,
                ),
                const SizedBox(height: 20),
                // Email
                _buildFormLabel('Email Address'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _buildInputDecoration('e.g., driver@example.com'),
                  validator: validateGmail,
                ),
                const SizedBox(height: 20),
                // Mobile Number
                _buildFormLabel('Mobile Number'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _buildInputDecoration('e.g., 9876543210'),
                  validator: (value) => value == null || value.isEmpty 
                    ? 'Enter mobile number' 
                    : (value.length < 10 ? 'Mobile number must be at least 10 digits' : null),
                ),
                const SizedBox(height: 20),
                // License
                _buildFormLabel('License Number'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _licenseController,
                  decoration: _buildInputDecoration('e.g., DL001234567'),
                  validator: (value) => value == null || value.isEmpty ? 'Enter license number' : null,
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
                    onPressed: _isLoading ? null : _registerDriver,
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
                            'Register Driver',
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

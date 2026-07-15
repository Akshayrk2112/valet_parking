/// Email validation
String? validateEmail(String? value) {
  if (value == null || value.isEmpty) {
    return 'Email is required';
  }

  // Regular expression for validating email addresses
  final RegExp emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  if (!emailRegExp.hasMatch(value)) {
    return 'Please enter a valid email address';
  }

  return null;
}

/// Password validation
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }

  if (value.length < 8) {
    return 'Password must be at least 8 characters';
  }

  if (!value.contains(RegExp(r'[A-Z]'))) {
    return 'Password must contain at least one uppercase letter';
  }

  if (!value.contains(RegExp(r'[a-z]'))) {
    return 'Password must contain at least one lowercase letter';
  }

  if (!value.contains(RegExp(r'[0-9]'))) {
    return 'Password must contain at least one digit';
  }

  return null;
}

/// Name validation
String? validateName(String? value) {
  if (value == null || value.isEmpty) {
    return 'Name is required';
  }

  if (value.length < 2) {
    return 'Name must be at least 2 characters';
  }

  if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value)) {
    return 'Name can only contain letters and spaces';
  }

  return null;
}

/// Phone number validation (Indian phone numbers - 10 digits)
String? validatePhoneNumber(String? value) {
  if (value == null || value.isEmpty) {
    return 'Phone number is required';
  }

  // Remove any spaces or dashes
  final cleanPhone = value.replaceAll(RegExp(r'[^0-9]'), '');

  if (cleanPhone.length != 10) {
    return 'Phone number must be exactly 10 digits';
  }

  // Indian mobile numbers typically start with 6, 7, 8, or 9
  if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(cleanPhone)) {
    return 'Please enter a valid phone number (should start with 6-9)';
  }

  return null;
}

/// Vehicle number validation
String? validateVehicleNumber(String? value) {
  final cleanVehicleNumber = normalizeVehicleNumber(value);
  if (cleanVehicleNumber.isEmpty) {
    return 'Vehicle number is required';
  }

  // Indian vehicle number format, e.g. KL58AH9653.
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z]{1,3}[0-9]{4}$')
      .hasMatch(cleanVehicleNumber)) {
    return 'Enter a valid vehicle number, e.g. KL58AH9653';
  }

  return null;
}

String normalizeVehicleNumber(String? value) {
  return (value ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

/// License number validation
String? validateLicenseNumber(String? value) {
  if (value == null || value.isEmpty) {
    return 'License number is required';
  }

  if (value.length < 10) {
    return 'License number must be at least 10 characters';
  }

  return null;
}

/// Age validation
String? validateAge(String? value) {
  if (value == null || value.isEmpty) {
    return 'Age is required';
  }

  try {
    final age = int.parse(value);

    if (age < 18) {
      return 'Age must be at least 18 years';
    }

    if (age > 100) {
      return 'Please enter a valid age';
    }

    return null;
  } catch (e) {
    return 'Please enter a valid number';
  }
}

/// Generic field validation
String? validateRequiredField(String? value, String fieldName) {
  if (value == null || value.isEmpty) {
    return '$fieldName is required';
  }
  return null;
}

/// Vehicle model validation
String? validateVehicleModel(String? value) {
  if (value == null || value.isEmpty) {
    return 'Vehicle model is required';
  }

  if (value.length < 2) {
    return 'Vehicle model must be at least 2 characters';
  }

  return null;
}

/// Parking location validation
String? validateParkingLocation(String? value) {
  if (value == null || value.isEmpty) {
    return 'Parking location is required';
  }

  return null;
}

/// Badge number validation
String? validateBadgeNumber(String? value) {
  if (value == null || value.isEmpty) {
    return 'Badge number is required';
  }

  if (value.length < 3) {
    return 'Badge number must be at least 3 characters';
  }

  return null;
}

/// OTP validation
String? validateOTP(String? value) {
  if (value == null || value.isEmpty) {
    return 'OTP is required';
  }

  if (value.length != 6) {
    return 'OTP must be 6 digits';
  }

  if (!RegExp(r'^[0-9]{6}$').hasMatch(value)) {
    return 'OTP must contain only numbers';
  }

  return null;
}

/// Latitude validation
String? validateLatitude(String? value) {
  if (value == null || value.isEmpty) {
    return 'Latitude is required';
  }

  try {
    final lat = double.parse(value);
    if (lat < -90 || lat > 90) {
      return 'Latitude must be between -90 and 90';
    }
    return null;
  } catch (e) {
    return 'Please enter a valid latitude';
  }
}

/// Longitude validation
String? validateLongitude(String? value) {
  if (value == null || value.isEmpty) {
    return 'Longitude is required';
  }

  try {
    final lng = double.parse(value);
    if (lng < -180 || lng > 180) {
      return 'Longitude must be between -180 and 180';
    }
    return null;
  } catch (e) {
    return 'Please enter a valid longitude';
  }
}

/// Max capacity validation
String? validateMaxCapacity(String? value) {
  if (value == null || value.isEmpty) {
    return 'Max capacity is required';
  }

  try {
    final capacity = int.parse(value);
    if (capacity <= 0) {
      return 'Max capacity must be greater than 0';
    }
    if (capacity > 1000) {
      return 'Max capacity cannot exceed 1000';
    }
    return null;
  } catch (e) {
    return 'Please enter a valid number';
  }
}

-- Valet Parking App Database Schema


-- Unified users table for all user types
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('customer', 'driver', 'admin', 'security') NOT NULL,
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Driver-specific details
CREATE TABLE driver_details (
    user_id INT PRIMARY KEY,
    license_number VARCHAR(50) UNIQUE NOT NULL,
    status ENUM('available', 'busy', 'inactive') DEFAULT 'available',
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Security-specific details (add fields as needed)
CREATE TABLE security_details (
    user_id INT PRIMARY KEY,
    parking_location VARCHAR(255),
    status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    phone VARCHAR(20),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE parking_locations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address VARCHAR(255) NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    total_slots INT,
    available_slots INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE bookings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    booking_token VARCHAR(100) UNIQUE NOT NULL,
    user_id INT NOT NULL,
    driver_id INT,
    location_id INT ,
    slot_no VARCHAR(20),
    vehicle_number VARCHAR(20) NOT NULL,
    vehicle_type VARCHAR(50),
    booking_time DATETIME NOT NULL,
    status ENUM('pending', 'confirmed', 'completed', 'cancelled') DEFAULT 'pending',
    payment_status ENUM('unpaid', 'paid', 'refunded') DEFAULT 'unpaid',
    payment_method VARCHAR(50),
    payment_amount DECIMAL(10,2),
    payment_time DATETIME,
    parked_confirmed_at DATETIME,
    return_requested_at DATETIME,
    desired_return_location VARCHAR(255),
    desired_return_latitude DECIMAL(10,8),
    desired_return_longitude DECIMAL(11,8),
    return_status VARCHAR(20),
    return_driver_id INT,
    return_accepted_at DATETIME,
    return_completed_at DATETIME,
    cancelled_at DATETIME,
    completed_at DATETIME,
    customer_latitude DECIMAL(10,8),
    customer_longitude DECIMAL(11,8),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (driver_id) REFERENCES users(id),
    FOREIGN KEY (return_driver_id) REFERENCES users(id),
    FOREIGN KEY (location_id) REFERENCES parking_locations(id)
);

-- Parking slot management
CREATE TABLE parking_slots (
    id INT AUTO_INCREMENT PRIMARY KEY,
    location_id INT NOT NULL,
    slot_number VARCHAR(20) NOT NULL,
    status ENUM('available', 'reserved', 'occupied', 'maintenance') DEFAULT 'available',
    FOREIGN KEY (location_id) REFERENCES parking_locations(id)
);

CREATE TABLE slot_reservations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    slot_id INT NOT NULL,
    booking_id INT NOT NULL,
    reserved_from DATETIME NOT NULL,
    reserved_to DATETIME NOT NULL,
    FOREIGN KEY (slot_id) REFERENCES parking_slots(id),
    FOREIGN KEY (booking_id) REFERENCES bookings(id)
);

-- Notifications table
CREATE TABLE notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    message TEXT NOT NULL,
    type ENUM('in-app', 'sms', 'email') DEFAULT 'in-app',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

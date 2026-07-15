const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const Booking = sequelize.define('Booking', {
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  booking_token: { type: DataTypes.STRING, unique: true, allowNull: false },
  user_id: { type: DataTypes.INTEGER, allowNull: false },
  driver_id: { type: DataTypes.INTEGER },
  location_id: { type: DataTypes.INTEGER, allowNull: true },
  // Keep JS attribute as slot_number while mapping to legacy DB column slot_no.
  slot_number: { type: DataTypes.STRING, field: 'slot_no' },
  vehicle_number: { type: DataTypes.STRING, allowNull: false },
  vehicle_type: { type: DataTypes.STRING },
  booking_time: { type: DataTypes.DATE, allowNull: false },
  customer_latitude: { type: DataTypes.DECIMAL(10,8) },
  customer_longitude: { type: DataTypes.DECIMAL(11,8) },
  status: { type: DataTypes.ENUM('pending', 'confirmed', 'completed', 'cancelled'), defaultValue: 'pending' },
  payment_status: { type: DataTypes.ENUM('unpaid', 'paid', 'refunded'), defaultValue: 'unpaid' },
  payment_method: { type: DataTypes.STRING },
  payment_amount: { type: DataTypes.DECIMAL(10,2) },
  payment_time: { type: DataTypes.DATE },
  driver_accepted_at: { type: DataTypes.DATE },
  parked_confirmed_at: { type: DataTypes.DATE },
  return_requested_at: { type: DataTypes.DATE },
  desired_return_location: { type: DataTypes.STRING },
  desired_return_latitude: { type: DataTypes.DECIMAL(10,8) },
  desired_return_longitude: { type: DataTypes.DECIMAL(11,8) },
  return_status: { type: DataTypes.STRING },
  return_driver_id: { type: DataTypes.INTEGER },
  return_accepted_at: { type: DataTypes.DATE },
  return_completed_at: { type: DataTypes.DATE },
  cancelled_at: { type: DataTypes.DATE },
  completed_at: { type: DataTypes.DATE }
}, {
  tableName: 'bookings',
  timestamps: false
});

module.exports = Booking;

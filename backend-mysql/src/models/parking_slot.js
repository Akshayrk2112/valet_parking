const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const ParkingSlot = sequelize.define('ParkingSlot', {
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  location_id: { type: DataTypes.INTEGER, allowNull: false },
  slot_number: { type: DataTypes.STRING, allowNull: false },
  status: { type: DataTypes.ENUM('available', 'reserved', 'occupied', 'maintenance'), defaultValue: 'available' }
}, {
  tableName: 'parking_slots',
  timestamps: false
});

module.exports = ParkingSlot;
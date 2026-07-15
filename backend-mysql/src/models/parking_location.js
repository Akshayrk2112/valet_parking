const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const ParkingLocation = sequelize.define('ParkingLocation', {
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  name: { type: DataTypes.STRING, allowNull: false },
  address: { type: DataTypes.STRING, allowNull: false },
  latitude: { type: DataTypes.DECIMAL(10,8) },
  longitude: { type: DataTypes.DECIMAL(11,8) },
  total_slots: { type: DataTypes.INTEGER },
  available_slots: { type: DataTypes.INTEGER }
}, {
  tableName: 'parking_locations',
  timestamps: true,
  createdAt: 'created_at',
  updatedAt: false
});

module.exports = ParkingLocation;
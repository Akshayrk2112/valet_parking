const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const DriverDetails = sequelize.define('DriverDetails', {
  user_id: { type: DataTypes.INTEGER, primaryKey: true },
  license_number: { type: DataTypes.STRING, unique: true, allowNull: false },
  status: { type: DataTypes.ENUM('available', 'busy', 'inactive'), defaultValue: 'available' }
}, {
  tableName: 'driver_details',
  timestamps: false
});

module.exports = DriverDetails;
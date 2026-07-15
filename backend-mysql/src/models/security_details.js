const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const SecurityDetails = sequelize.define('SecurityDetails', {
  user_id: { type: DataTypes.INTEGER, primaryKey: true },
  parking_location_id: { type: DataTypes.INTEGER, allowNull: true },
  parking_location: { type: DataTypes.STRING, allowNull: true },
  status: {
    type: DataTypes.ENUM('active', 'inactive'),
    allowNull: false,
    defaultValue: 'active',
  },
  phone: { type: DataTypes.STRING, allowNull: true },
}, {
  tableName: 'security_details',
  timestamps: false,
});

module.exports = SecurityDetails;

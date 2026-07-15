const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const BookingDecline = sequelize.define('BookingDecline', {
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  booking_id: { type: DataTypes.INTEGER, allowNull: false },
  driver_id: { type: DataTypes.INTEGER, allowNull: false },
  request_type: {
    type: DataTypes.ENUM('pickup', 'return'),
    allowNull: false,
    defaultValue: 'pickup'
  },
  decline_reason: { type: DataTypes.STRING },
  decline_note: { type: DataTypes.TEXT },
  declined_at: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW }
}, {
  tableName: 'booking_declines',
  timestamps: false
});

module.exports = BookingDecline;

const { DataTypes } = require('sequelize');
const sequelize = require('../config');

const SlotReservation = sequelize.define('SlotReservation', {
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  slot_id: { type: DataTypes.INTEGER, allowNull: false },
  booking_id: { type: DataTypes.INTEGER, allowNull: false },
  reserved_from: { type: DataTypes.DATE, allowNull: false },
  reserved_to: { type: DataTypes.DATE, allowNull: false }
}, {
  tableName: 'slot_reservations',
  timestamps: false
});

module.exports = SlotReservation;
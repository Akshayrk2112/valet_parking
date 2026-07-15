const ParkingSlot = require('../models/parking_slot');
const ParkingLocation = require('../models/parking_location');
const Booking = require('../models/booking');
const SlotReservation = require('../models/slot_reservation');
const SecurityDetails = require('../models/security_details');
const Notification = require('../models/notification');
const { Op } = require('sequelize');

function normalizeText(value) {
  return (value || '').toString().trim().toLowerCase();
}

function toMaybeInt(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

// Get all parking slots for a location
exports.getSlotsByLocation = async (req, res) => {
  try {
    const { location_id } = req.params;
    let slots = await ParkingSlot.findAll({ where: { location_id } });

    // Auto-provision slots for locations that have total_slots configured
    // but no slot rows yet (common in fresh DB setups).
    if (!slots || slots.length == 0) {
      const location = await ParkingLocation.findOne({ where: { id: location_id } });
      if (location) {
        const totalSlots = Number(location.total_slots) || 0;
        if (totalSlots > 0) {
          const prefixRaw = (location.name || '').toString().toUpperCase().replace(/[^A-Z0-9]/g, '');
          const prefix = prefixRaw || `L${location_id}`;
          for (let i = 1; i <= totalSlots; i++) {
            await ParkingSlot.create({
              location_id,
              slot_number: `${prefix}${i}`,
              status: 'available'
            });
          }
          slots = await ParkingSlot.findAll({ where: { location_id } });
        }
      }
    }

    const activeBookings = await Booking.findAll({
      where: {
        location_id,
        slot_number: { [Op.not]: null },
        status: { [Op.in]: ['pending', 'confirmed'] },
      },
      attributes: [
        'slot_number',
        'vehicle_number',
        'vehicle_type',
        'status',
        'return_status',
      ],
    });

    const bookingBySlot = new Map();
    for (const booking of activeBookings) {
      const slotNumber = (booking.slot_number || '').toString();
      if (!slotNumber) continue;
      const returnStatus = (booking.return_status || '').toString().toLowerCase();
      if (returnStatus === 'completed' || returnStatus === 'released') {
        continue;
      }
      bookingBySlot.set(slotNumber, booking);
    }

    const enrichedSlots = slots.map((slot) => {
      const slotNumber = (slot.slot_number || '').toString();
      const booking = bookingBySlot.get(slotNumber);
      return {
        ...slot.toJSON(),
        booking_vehicle_number: booking ? booking.vehicle_number : null,
        booking_vehicle_type: booking ? booking.vehicle_type : null,
        booking_status: booking ? booking.status : null,
        booking_return_status: booking ? booking.return_status : null,
      };
    });

    res.json({ success: true, slots: enrichedSlots });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Create multiple parking slots for a location
exports.createSlots = async (req, res) => {
  try {
    const { location_id, total_slots } = req.body;

    // Verify location exists
    const location = await ParkingLocation.findOne({ where: { id: location_id } });
    if (!location) {
      return res.status(404).json({ success: false, error: 'Location not found' });
    }

    // Delete existing slots for this location (if any)
    await ParkingSlot.destroy({ where: { location_id } });

    // Create new slots
    const slots = [];
    for (let i = 1; i <= total_slots; i++) {
      const slot = await ParkingSlot.create({
        location_id,
        slot_number: `${location.name.replace(/[^A-Z0-9]/g, '')}${i}`,
        status: 'available'
      });
      slots.push(slot);
    }

    res.status(201).json({ success: true, slots });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Update parking slot status
exports.updateSlotStatus = async (req, res) => {
  try {
    const { slot_id } = req.params;
    const { status } = req.body;
    const role = req.user && req.user.role;

    if (!['admin', 'security', 'driver'].includes(role)) {
      return res.status(403).json({ success: false, error: 'Not authorized to update slot status' });
    }

    const allowedStatuses = ['available', 'reserved', 'occupied', 'maintenance'];
    if (!allowedStatuses.includes(status)) {
      return res.status(400).json({ success: false, error: 'Invalid slot status' });
    }

    if (role === 'driver' && status !== 'reserved') {
      return res.status(403).json({ success: false, error: 'Drivers can only reserve slots' });
    }

    if (role === 'security' && !['occupied', 'available'].includes(status)) {
      return res.status(403).json({ success: false, error: 'Security can only confirm parked/retrieved actions' });
    }

    const slot = await ParkingSlot.findOne({ where: { id: slot_id } });
    if (!slot) {
      return res.status(404).json({ success: false, error: 'Slot not found' });
    }

    if (role === 'security') {
      const security = await SecurityDetails.findOne({ where: { user_id: req.user.id } });
      if (!security || security.status !== 'active') {
        return res.status(403).json({ success: false, error: 'Active security assignment required' });
      }

      const location = await ParkingLocation.findOne({ where: { id: slot.location_id } });
      if (!location) {
        return res.status(404).json({ success: false, error: 'Parking location not found for this slot' });
      }

      const assigned = security.parking_location;
      const assignedLower = normalizeText(assigned);
      const assignedId = toMaybeInt(assigned);
      const matchesByName = assignedLower && assignedLower === normalizeText(location.name);
      const matchesById = assignedId !== null && assignedId === Number(location.id);
      if (!matchesByName && !matchesById) {
        return res.status(403).json({
          success: false,
          error: 'You can only manage slots in your assigned parking location'
        });
      }
    }

    // Keep Park Yourself booking lifecycle in sync with security actions.
    // reserved -> occupied  : security confirmed parked (booking => confirmed)
    // occupied -> available : vehicle retrieved (booking => completed)
    const latestReservation = await SlotReservation.findOne({
      where: { slot_id: slot.id },
      order: [['id', 'DESC']],
    });

    let relatedBooking = null;
    if (latestReservation) {
      relatedBooking = await Booking.findOne({
        where: { id: latestReservation.booking_id },
      });
    }

    // Valet flow may not have a slot_reservation row. Fall back to the latest
    // active booking bound to this exact location+slot.
    if (!relatedBooking) {
      relatedBooking = await Booking.findOne({
        where: {
          location_id: slot.location_id,
          slot_number: slot.slot_number,
          status: { [Op.in]: ['pending', 'confirmed'] },
        },
        order: [['id', 'DESC']],
      });
    }

    if (
      role === 'security' &&
      status === 'available' &&
      relatedBooking &&
      relatedBooking.status === 'confirmed' &&
      !relatedBooking.return_requested_at
    ) {
      return res.status(400).json({
        success: false,
        error: 'Customer return request is required before confirming return'
      });
    }

    if (
      role === 'security' &&
      status === 'available' &&
      relatedBooking &&
      relatedBooking.status === 'confirmed' &&
      relatedBooking.return_requested_at &&
      relatedBooking.driver_id &&
      (relatedBooking.return_status || '').toString().toLowerCase() !== 'accepted'
    ) {
      return res.status(400).json({
        success: false,
        error: 'A driver must accept the return request before confirming return',
      });
    }

    await ParkingSlot.update({ status }, { where: { id: slot_id } });
    const updated = await ParkingSlot.findOne({ where: { id: slot_id } });

    if (status === 'occupied' && relatedBooking) {
      if (relatedBooking.status === 'pending') {
        relatedBooking.status = 'confirmed';
        relatedBooking.parked_confirmed_at = new Date();
        relatedBooking.return_requested_at = null;
        relatedBooking.return_status = null;
        relatedBooking.return_driver_id = null;
        relatedBooking.return_accepted_at = null;
        relatedBooking.return_completed_at = null;
        await relatedBooking.save();
      } else if (
        relatedBooking.status === 'confirmed' &&
        !relatedBooking.parked_confirmed_at
      ) {
        relatedBooking.parked_confirmed_at = new Date();
        await relatedBooking.save();
      }
    }

    if (status === 'available' && relatedBooking) {
      const returnStatus = (relatedBooking.return_status || '')
        .toString()
        .toLowerCase();
      const isValetReturnFlow =
        Number(relatedBooking.driver_id || 0) > 0 &&
        Number(relatedBooking.return_driver_id || 0) > 0 &&
        returnStatus === 'accepted';

      if (isValetReturnFlow) {
        // Security has released the vehicle to the accepted driver.
        // Keep booking active until customer confirms final handover.
        relatedBooking.return_status = 'released';
        relatedBooking.return_completed_at = null;
        await relatedBooking.save();
      } else if (
        relatedBooking.status !== 'completed' &&
        relatedBooking.status !== 'cancelled'
      ) {
        relatedBooking.status = 'completed';
        relatedBooking.return_requested_at = null;
        relatedBooking.return_status = 'completed';
        relatedBooking.return_completed_at = new Date();
        relatedBooking.completed_at = new Date();
        await relatedBooking.save();
      }

      if (latestReservation) {
        await SlotReservation.destroy({ where: { id: latestReservation.id } });
      }

      const location = await ParkingLocation.findOne({ where: { id: slot.location_id } });
      if (location) {
        const currentAvailable = Number(location.available_slots) || 0;
        const maxSlots = Number(location.total_slots) || currentAvailable;
        const nextAvailable = Math.min(maxSlots, currentAvailable + 1);
        await ParkingLocation.update(
          { available_slots: nextAvailable },
          { where: { id: location.id } }
        );
      }

      try {
        if (isValetReturnFlow) {
          await Notification.create({
            user_id: relatedBooking.user_id,
            message:
              `Security confirmed return handover. Driver is bringing your car to ${relatedBooking.desired_return_location || 'your requested location'}. ` +
              'Please confirm return completed after receiving it.',
            type: 'in-app',
            is_read: false,
            created_at: new Date(),
          });

          await Notification.create({
            user_id: relatedBooking.return_driver_id,
            message:
              `Security confirmed release for vehicle ${relatedBooking.vehicle_number || 'N/A'}. ` +
              `Deliver to ${relatedBooking.desired_return_location || 'customer requested location'}.`,
            type: 'in-app',
            is_read: false,
            created_at: new Date(),
          });
        } else {
          await Notification.create({
            user_id: relatedBooking.user_id,
            message:
              `Security confirmed your return. Your car has been returned to ${relatedBooking.desired_return_location || 'your requested location'}.`,
            type: 'in-app',
            is_read: false,
            created_at: new Date(),
          });
        }
      } catch (notifyError) {
        console.error(
          'Failed to notify about return status update:',
          notifyError.message || notifyError
        );
      }
    }

    res.json({ success: true, slot: updated, booking: relatedBooking });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get all slots
exports.getAllSlots = async (req, res) => {
  try {
    const slots = await ParkingSlot.findAll();
    res.json({ success: true, slots });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

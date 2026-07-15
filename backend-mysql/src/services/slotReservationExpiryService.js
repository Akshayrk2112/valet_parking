const { Op } = require('sequelize');
const sequelize = require('../config');
const SlotReservation = require('../models/slot_reservation');
const Booking = require('../models/booking');
const ParkingSlot = require('../models/parking_slot');
const ParkingLocation = require('../models/parking_location');

let isSweepInProgress = false;

async function releaseExpiredReservations() {
  if (isSweepInProgress) {
    return { released: 0, skipped: true };
  }

  isSweepInProgress = true;
  try {
    const now = new Date();
    const expiredReservations = await SlotReservation.findAll({
      where: { reserved_to: { [Op.lte]: now } },
      attributes: ['id']
    });

    let released = 0;
    for (const reservationMeta of expiredReservations) {
      const didRelease = await sequelize.transaction(async (transaction) => {
        const reservation = await SlotReservation.findOne({
          where: { id: reservationMeta.id },
          transaction,
          lock: transaction.LOCK.UPDATE
        });
        if (!reservation) {
          return false;
        }

        if (new Date(reservation.reserved_to).getTime() > Date.now()) {
          return false;
        }

        const booking = await Booking.findOne({
          where: { id: reservation.booking_id },
          transaction,
          lock: transaction.LOCK.UPDATE
        });
        if (booking && booking.status === 'confirmed') {
          // Security already confirmed parking, so this reservation should not auto-expire.
          return false;
        }

        if (booking && booking.status === 'pending') {
          booking.status = 'cancelled';
          booking.return_requested_at = null;
          booking.return_status = null;
          booking.return_driver_id = null;
          booking.return_accepted_at = null;
          booking.return_completed_at = null;
          booking.cancelled_at = new Date();
          await booking.save({ transaction });
        }

        const slot = await ParkingSlot.findOne({
          where: { id: reservation.slot_id },
          transaction,
          lock: transaction.LOCK.UPDATE
        });

        if (slot && (slot.status === 'reserved' || slot.status === 'occupied')) {
          await ParkingSlot.update(
            { status: 'available' },
            { where: { id: slot.id }, transaction }
          );

          const location = await ParkingLocation.findOne({
            where: { id: slot.location_id },
            transaction,
            lock: transaction.LOCK.UPDATE
          });
          if (location && typeof location.available_slots === 'number') {
            const currentAvailable = Number(location.available_slots) || 0;
            const maxSlots = Number(location.total_slots) || currentAvailable;
            const nextAvailable = Math.min(maxSlots, currentAvailable + 1);
            await ParkingLocation.update(
              { available_slots: nextAvailable },
              { where: { id: location.id }, transaction }
            );
          }
        }

        await SlotReservation.destroy({
          where: { id: reservation.id },
          transaction
        });

        return true;
      });

      if (didRelease) {
        released += 1;
      }
    }

    return { released, skipped: false };
  } finally {
    isSweepInProgress = false;
  }
}

function startReservationExpiryJob() {
  const parsed = Number(process.env.SLOT_RESERVATION_SWEEP_MS);
  const intervalMs = Number.isFinite(parsed) && parsed > 0 ? parsed : 60 * 1000;

  const runSweep = async () => {
    try {
      const result = await releaseExpiredReservations();
      if (result.released > 0) {
        console.log(`Released ${result.released} expired slot reservation(s)`);
      }
    } catch (error) {
      console.error('Failed to release expired slot reservations:', error.message || error);
    }
  };

  runSweep();
  const timer = setInterval(runSweep, intervalMs);
  if (typeof timer.unref === 'function') {
    timer.unref();
  }
}

module.exports = {
  releaseExpiredReservations,
  startReservationExpiryJob
};

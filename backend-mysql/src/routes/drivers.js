const express = require('express');
const router = express.Router();
const { Op, fn, col, where } = require('sequelize');
const sequelize = require('../config');
const auth = require('../middleware/auth');
const User = require('../models/user');
const DriverDetails = require('../models/driver_details');
const Booking = require('../models/booking');
const BookingDecline = require('../models/bookingDecline');
const ParkingLocation = require('../models/parking_location');

// Example: GET /api/drivers/test
router.get('/test', (req, res) => {
  res.json({ message: 'Drivers route working' });
});

// GET /api/drivers/mine
// Driver/Admin: fetch current driver's profile + availability status.
router.get('/mine', auth, async (req, res, next) => {
  try {
    const role = req.user?.role;
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({ message: 'Only drivers can access this endpoint' });
    }

    const userId = Number(req.user.id);
    const user = await User.findOne({
      where: { id: userId, role: 'driver' },
      attributes: ['id', 'name', 'email', 'phone', 'created_at'],
    });
    if (!user) {
      return res.status(404).json({ message: 'Driver user not found' });
    }

    const details = await DriverDetails.findOne({
      where: { user_id: userId },
      attributes: ['user_id', 'license_number', 'status'],
    });
    if (!details) {
      return res.status(404).json({ message: 'Driver details not found' });
    }

    return res.json({
      success: true,
      driver: {
        user_id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        license_number: details.license_number,
        status: details.status,
        is_available: details.status === 'available',
        created_at: user.created_at,
      },
    });
  } catch (err) {
    return next(err);
  }
});

// PATCH /api/drivers/mine/availability
// Driver/Admin: mark self as available/unavailable.
router.patch('/mine/availability', auth, async (req, res, next) => {
  try {
    const role = req.user?.role;
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({ message: 'Only drivers can access this endpoint' });
    }

    const userId = Number(req.user.id);
    const available = req.body?.available;
    if (typeof available !== 'boolean') {
      return res.status(400).json({ message: 'available must be true or false' });
    }

    const nextStatus = available ? 'available' : 'inactive';
    const [affected] = await DriverDetails.update(
      { status: nextStatus },
      { where: { user_id: userId } }
    );

    if (!affected) {
      return res.status(404).json({ message: 'Driver details not found' });
    }

    const updated = await DriverDetails.findOne({
      where: { user_id: userId },
      attributes: ['user_id', 'license_number', 'status'],
    });

    return res.json({
      success: true,
      driver: {
        user_id: updated.user_id,
        license_number: updated.license_number,
        status: updated.status,
        is_available: updated.status === 'available',
      },
    });
  } catch (err) {
    return next(err);
  }
});

// GET /api/drivers/mine/stats
// Driver/Admin: fetch parked-today and total parked counts.
router.get('/mine/stats', auth, async (req, res, next) => {
  try {
    const role = req.user?.role;
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({ message: 'Only drivers can access this endpoint' });
    }

    const userId = Number(req.user.id);
    if (!Number.isFinite(userId)) {
      return res.status(400).json({ message: 'Invalid driver id' });
    }

    const baseWhere = {
      driver_id: userId,
      parked_confirmed_at: { [Op.ne]: null },
    };

    const [totalParked, parkedToday] = await Promise.all([
      Booking.count({ where: baseWhere }),
      Booking.count({
        where: {
          ...baseWhere,
          [Op.and]: where(fn('DATE', col('parked_confirmed_at')), fn('CURDATE')),
        },
      }),
    ]);

    return res.json({
      success: true,
      stats: {
        parked_today: parkedToday,
        total_parked: totalParked,
      },
    });
  } catch (err) {
    return next(err);
  }
});

// GET /api/drivers/mine/accepted-requests/today
// Driver/Admin: list today's accepted pickup and return requests for the current driver.
router.get('/mine/accepted-requests/today', auth, async (req, res, next) => {
  try {
    const role = req.user?.role;
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({ message: 'Only drivers can access this endpoint' });
    }

    const userId = Number(req.user.id);
    if (!Number.isFinite(userId)) {
      return res.status(400).json({ message: 'Invalid driver id' });
    }

    const pickupBookings = await Booking.findAll({
      where: {
        driver_id: userId,
        [Op.or]: [
          where(fn('DATE', col('driver_accepted_at')), fn('CURDATE')),
          {
            [Op.and]: [
              { driver_accepted_at: null },
              where(fn('DATE', col('booking_time')), fn('CURDATE')),
            ],
          },
        ],
      },
      order: [['driver_accepted_at', 'DESC'], ['id', 'DESC']],
    });

    const returnBookings = await Booking.findAll({
      where: {
        return_driver_id: userId,
        return_accepted_at: { [Op.ne]: null },
        [Op.and]: where(fn('DATE', col('return_accepted_at')), fn('CURDATE')),
      },
      order: [['return_accepted_at', 'DESC'], ['id', 'DESC']],
    });

    const userIds = new Set();
    const locationIds = new Set();
    for (const booking of [...pickupBookings, ...returnBookings]) {
      const raw = booking.toJSON();
      if (raw.user_id != null) userIds.add(Number(raw.user_id));
      if (raw.location_id != null) locationIds.add(Number(raw.location_id));
    }

    const [users, locations] = await Promise.all([
      userIds.size
        ? User.findAll({
            where: { id: { [Op.in]: [...userIds] } },
            attributes: ['id', 'name', 'phone'],
          })
        : [],
      locationIds.size
        ? ParkingLocation.findAll({
            where: { id: { [Op.in]: [...locationIds] } },
            attributes: ['id', 'name', 'address', 'latitude', 'longitude'],
          })
        : [],
    ]);

    const userById = new Map(users.map((user) => [Number(user.id), user]));
    const locationById = new Map(
      locations.map((location) => [Number(location.id), location])
    );

    const toAcceptedRequest = (booking, requestType) => {
      const raw = booking.toJSON();
      const customer = userById.get(Number(raw.user_id));
      const location = locationById.get(Number(raw.location_id));
      const acceptedAt =
        requestType === 'return'
          ? raw.return_accepted_at
          : (raw.driver_accepted_at || raw.booking_time);

      return {
        ...raw,
        request_type: requestType,
        accepted_at: acceptedAt,
        customer_name: customer ? customer.name : null,
        customer_phone: customer ? customer.phone : null,
        location_name: location ? location.name : null,
        location_address: location ? location.address : null,
        location_latitude: location ? location.latitude : null,
        location_longitude: location ? location.longitude : null,
      };
    };

    const requests = [
      ...pickupBookings.map((booking) => toAcceptedRequest(booking, 'pickup')),
      ...returnBookings.map((booking) => toAcceptedRequest(booking, 'return')),
    ].sort((a, b) => {
      const aTime = new Date(a.accepted_at || a.booking_time || 0).getTime();
      const bTime = new Date(b.accepted_at || b.booking_time || 0).getTime();
      return bTime - aTime;
    });

    return res.json({
      success: true,
      date: new Date().toISOString().slice(0, 10),
      count: requests.length,
      requests,
    });
  } catch (err) {
    return next(err);
  }
});

// GET /api/drivers/admin
// Admin only: list all registered drivers and availability.
router.get('/admin', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ message: 'Only admin can access this endpoint' });
    }

    const users = await User.findAll({
      where: { role: 'driver' },
      attributes: ['id', 'name', 'email', 'phone', 'created_at'],
      order: [['id', 'DESC']],
    });

    const userIds = users.map((u) => Number(u.id)).filter((id) => Number.isFinite(id));
    const details = userIds.length
      ? await DriverDetails.findAll({
          where: { user_id: { [Op.in]: userIds } },
          attributes: ['user_id', 'license_number', 'status'],
        })
      : [];
    const detailsById = new Map(details.map((d) => [Number(d.user_id), d]));

    const drivers = users.map((user) => {
      const detail = detailsById.get(Number(user.id));
      const status = detail ? detail.status : 'inactive';
      return {
        user_id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        license_number: detail ? detail.license_number : null,
        status,
        is_available: status === 'available',
        created_at: user.created_at,
      };
    });

    return res.json({
      success: true,
      count: drivers.length,
      drivers,
    });
  } catch (err) {
    return next(err);
  }
});

// DELETE /api/drivers/admin/:userId
// Admin only: remove a driver account when the driver has no active assignment.
router.delete('/admin/:userId', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ message: 'Only admin can access this endpoint' });
    }

    const userId = Number(req.params.userId);
    if (!Number.isFinite(userId) || userId <= 0) {
      return res.status(400).json({ message: 'Invalid driver id' });
    }

    const driver = await User.findOne({
      where: { id: userId, role: 'driver' },
      attributes: ['id', 'name'],
    });
    if (!driver) {
      return res.status(404).json({ message: 'Driver user not found' });
    }

    const activeAssignments = await Booking.count({
      where: {
        [Op.or]: [
          {
            driver_id: userId,
            status: { [Op.in]: ['pending', 'confirmed'] },
          },
          {
            return_driver_id: userId,
            return_status: { [Op.in]: ['accepted', 'released', 'handover_confirmed'] },
            return_completed_at: null,
          },
        ],
      },
    });

    if (activeAssignments > 0) {
      return res.status(409).json({
        message: 'Cannot delete this driver while they have active bookings or return requests',
      });
    }

    await sequelize.transaction(async (transaction) => {
      await Booking.update(
        {
          driver_id: null,
          driver_accepted_at: null,
        },
        {
          where: { driver_id: userId },
          transaction,
        }
      );
      await Booking.update(
        {
          return_driver_id: null,
          return_accepted_at: null,
        },
        {
          where: { return_driver_id: userId },
          transaction,
        }
      );
      await BookingDecline.destroy({
        where: { driver_id: userId },
        transaction,
      });
      await DriverDetails.destroy({
        where: { user_id: userId },
        transaction,
      });
      await User.destroy({
        where: { id: userId, role: 'driver' },
        transaction,
      });
    });

    return res.json({
      success: true,
      message: 'Driver deleted',
      deleted_driver_id: userId,
    });
  } catch (err) {
    return next(err);
  }
});

// GET /api/drivers/admin/count
// Admin only: total registered drivers.
router.get('/admin/count', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ message: 'Only admin can access this endpoint' });
    }

    const total = await User.count({ where: { role: 'driver' } });
    return res.json({ success: true, count: total });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;

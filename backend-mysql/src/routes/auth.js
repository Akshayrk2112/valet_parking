const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/user');
const DriverDetails = require('../models/driver_details');
const SecurityDetails = require('../models/security_details');
const ParkingLocation = require('../models/parking_location');
const { Op } = require('sequelize');
const auth = require('../middleware/auth');
const router = express.Router();
const crypto = require('crypto');
const otpStore = new Map(); // In-memory OTP store (for demo)

async function resolveParkingLocation(input) {
  if (input === undefined || input === null) return null;
  const raw = input.toString().trim();
  if (!raw) return null;

  const maybeId = Number(raw);
  if (Number.isFinite(maybeId) && maybeId > 0) {
    return await ParkingLocation.findOne({
      where: { id: maybeId },
      attributes: ['id', 'name'],
    });
  }

  return await ParkingLocation.findOne({
    where: { name: raw },
    attributes: ['id', 'name'],
  });
}

async function resolveParkingLocationByName(input) {
  if (input === undefined || input === null) return null;
  const raw = input.toString().trim();
  if (!raw) return null;
  return await ParkingLocation.findOne({
    where: { name: raw },
    attributes: ['id', 'name'],
  });
}

// POST /api/auth/register
router.post('/register', async (req, res, next) => {
  try {
    const {
      name,
      email,
      password,
      phone,
      role,
      license_number,
      location,
      parking_location,
      status,
    } = req.body;
    if (!name || !email || !password || !role) {
      return res.status(400).json({ message: 'Name, email, password, and role are required' });
    }
    if (role === 'driver' && (!license_number || license_number.trim() === '')) {
      return res.status(400).json({ message: 'License number is required for drivers' });
    }
    if (role === 'security' && (!phone || phone.trim() === '')) {
      return res.status(400).json({ message: 'Phone number is required for security staff' });
    }
    // Check if user already exists
    const existing = await User.findOne({ where: { email } });
    if (existing) {
      return res.status(409).json({ message: 'User already exists' });
    }
    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);
    // Create user
    const user = await User.create({
      name,
      email,
      password: hashedPassword,
      phone,
      role
    });
    // If driver, create driver_details
    if (role === 'driver') {
      await DriverDetails.create({
        user_id: user.id,
        license_number,
        status: 'available'
      });
    }
    // If security, create security_details
    if (role === 'security') {
      const resolvedLocation = await resolveParkingLocation(
        parking_location || location || null
      );
      if (!resolvedLocation) {
        return res.status(400).json({
          message: 'Valid parking location is required for security staff',
        });
      }
      await SecurityDetails.create({
        user_id: user.id,
        parking_location_id: resolvedLocation.id,
        parking_location: resolvedLocation.name,
        status: (status || 'active'),
        phone: phone || null,
      });
    }
    res.status(201).json({ message: 'User registered successfully', user: { id: user.id, name: user.name, email: user.email, role: user.role, phone: user.phone } });
  } catch (err) {
    next(err);
  }
});
// POST /api/auth/send-otp
router.post('/send-otp', async (req, res, next) => {
  try {
    const { phone } = req.body;
    if (!phone) return res.status(400).json({ message: 'Phone number required' });
    // Check if user exists
    const user = await User.findOne({ where: { phone, role: 'customer' } });
    if (!user) return res.status(404).json({ message: 'User not found' });
    // Generate 6-digit OTP
    const otp = ('' + Math.floor(100000 + Math.random() * 900000));
    otpStore.set(phone, { otp, expires: Date.now() + 5 * 60 * 1000 });
    // TODO: Integrate SMS gateway here. For now, return OTP in response (for demo)
    res.json({ message: 'OTP sent', otp });
  } catch (err) {
    next(err);
  }
});

// POST /api/auth/verify-otp
router.post('/verify-otp', async (req, res, next) => {
  try {
    const { phone, otp } = req.body;
    if (!phone || !otp) return res.status(400).json({ message: 'Phone and OTP required' });
    const record = otpStore.get(phone);
    if (!record || record.otp !== otp || Date.now() > record.expires) {
      return res.status(401).json({ message: 'Invalid or expired OTP' });
    }
    otpStore.delete(phone);
    const user = await User.findOne({ where: { phone, role: 'customer' } });
    if (!user) return res.status(404).json({ message: 'User not found' });
    const token = jwt.sign(
      { id: user.id, phone: user.phone, role: user.role },
      process.env.JWT_SECRET || 'secretkey',
      { expiresIn: '1d' }
    );
    res.json({ token, user: { id: user.id, name: user.name, phone: user.phone, role: user.role } });
  } catch (err) {
    next(err);
  }
});
// ...existing code...

// Example: GET /api/auth/test
router.get('/test', (req, res) => {
  res.json({ message: 'Auth route working' });
});

// POST /api/auth/login
router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ message: 'Email and password are required' });
    }
    const user = await User.findOne({ where: { email } });
    if (!user) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }
    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET || 'secretkey',
      { expiresIn: '1d' }
    );
    res.json({ token, user: { id: user.id, name: user.name, email: user.email, role: user.role } });
  } catch (err) {
    next(err);
  }
});

// GET /api/auth/security-assignment
router.get('/security-assignment', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'security') {
      return res.status(403).json({ message: 'Only security users can access this endpoint' });
    }

    const details = await SecurityDetails.findOne({
      where: { user_id: req.user.id },
    });

    if (!details) {
      return res.status(404).json({ message: 'Security details not found for this user' });
    }

    let location = null;
    if (details.parking_location_id != null) {
      location = await resolveParkingLocation(details.parking_location_id);
    }
    if (!location && details.parking_location) {
      location = await resolveParkingLocationByName(details.parking_location);
    }

    res.json({
      user_id: req.user.id,
      parking_location: details.parking_location,
      parking_location_id: details.parking_location_id ?? location?.id ?? null,
      parking_location_name: location ? location.name : details.parking_location,
      phone: details.phone,
      status: details.status,
    });
  } catch (err) {
    next(err);
  }
});

// GET /api/auth/security-staff
// Admin only: list registered security staff with assignment details.
router.get('/security-staff', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ message: 'Only admin can access this endpoint' });
    }

    const users = await User.findAll({
      where: { role: 'security' },
      attributes: ['id', 'name', 'email', 'phone', 'created_at'],
      order: [['id', 'DESC']],
    });

    const userIds = users.map((u) => u.id);
    const details = userIds.length
      ? await SecurityDetails.findAll({
          where: { user_id: { [Op.in]: userIds } },
        })
      : [];

    const detailsByUserId = new Map(details.map((d) => [Number(d.user_id), d]));
    const locationIds = details
      .map((d) => Number(d.parking_location_id))
      .filter((id) => Number.isFinite(id) && id > 0);
    const locations = locationIds.length
      ? await ParkingLocation.findAll({
          where: { id: { [Op.in]: locationIds } },
          attributes: ['id', 'name'],
        })
      : [];
    const locationById = new Map(locations.map((l) => [Number(l.id), l.name]));

    const staff = users.map((user) => {
      const detail = detailsByUserId.get(Number(user.id));
      const locationId = detail ? Number(detail.parking_location_id) : null;
      const locationName =
        locationId && locationById.has(locationId)
          ? locationById.get(locationId)
          : (detail?.parking_location || null);
      return {
        user_id: user.id,
        name: user.name,
        email: user.email,
        phone: (detail && detail.phone) || user.phone || null,
        parking_location: detail ? detail.parking_location : null,
        parking_location_id: locationId || null,
        parking_location_name: locationName,
        status: detail ? detail.status : 'inactive',
        created_at: user.created_at,
      };
    });

    return res.json({ success: true, staff });
  } catch (err) {
    return next(err);
  }
});

// PATCH /api/auth/security-staff/:userId/assignment
// Admin only: update assigned parking location for a security staff.
router.patch('/security-staff/:userId/assignment', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ message: 'Only admin can access this endpoint' });
    }

    const userId = Number(req.params.userId);
    if (!Number.isFinite(userId) || userId <= 0) {
      return res.status(400).json({ message: 'Invalid user id' });
    }

    const user = await User.findOne({
      where: { id: userId, role: 'security' },
      attributes: ['id'],
    });
    if (!user) {
      return res.status(404).json({ message: 'Security user not found' });
    }

    const inputLocation = (req.body.parking_location || '').toString().trim();
    let normalizedLocation = null;
    let normalizedLocationId = null;
    if (inputLocation !== '' && inputLocation.toLowerCase() !== 'unassigned') {
      const resolvedLocation = await resolveParkingLocation(inputLocation);
      if (!resolvedLocation) {
        return res.status(400).json({ message: 'Selected parking location does not exist' });
      }
      normalizedLocationId = resolvedLocation.id;
      normalizedLocation = resolvedLocation.name;
    }

    const [affected] = await SecurityDetails.update(
      {
        parking_location: normalizedLocation,
        parking_location_id: normalizedLocationId,
      },
      { where: { user_id: userId } }
    );
    if (!affected) {
      return res.status(404).json({ message: 'Security details not found for this user' });
    }

    const updated = await SecurityDetails.findOne({
      where: { user_id: userId },
      attributes: [
        'user_id',
        'parking_location',
        'parking_location_id',
        'status',
        'phone',
      ],
    });

    let locationName = null;
    if (updated && updated.parking_location_id != null) {
      const resolvedLocation = await resolveParkingLocation(updated.parking_location_id);
      locationName = resolvedLocation ? resolvedLocation.name : null;
    } else if (updated && updated.parking_location) {
      const resolvedLocation = await resolveParkingLocationByName(updated.parking_location);
      locationName = resolvedLocation ? resolvedLocation.name : updated.parking_location;
    }

    return res.json({
      success: true,
      assignment: updated,
      parking_location_name: locationName,
    });
  } catch (err) {
    return next(err);
  }
});

// DELETE /api/auth/security-staff/:userId
// Admin only: remove a security staff account.
router.delete('/security-staff/:userId', auth, async (req, res, next) => {
  try {
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ message: 'Only admin can access this endpoint' });
    }

    const userId = Number(req.params.userId);
    if (!Number.isFinite(userId) || userId <= 0) {
      return res.status(400).json({ message: 'Invalid user id' });
    }

    const user = await User.findOne({
      where: { id: userId, role: 'security' },
      attributes: ['id'],
    });
    if (!user) {
      return res.status(404).json({ message: 'Security user not found' });
    }

    await User.destroy({ where: { id: userId } });
    return res.json({ success: true, message: 'Security staff deleted' });
  } catch (err) {
    return next(err);
  }
});


module.exports = router;

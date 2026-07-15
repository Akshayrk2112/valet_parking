const Booking = require('../models/booking');
const ParkingLocation = require('../models/parking_location');
const ParkingSlot = require('../models/parking_slot');
const SlotReservation = require('../models/slot_reservation');
const DriverDetails = require('../models/driver_details');
const SecurityDetails = require('../models/security_details');
const User = require('../models/user');
const BookingDecline = require('../models/bookingDecline');
const Notification = require('../models/notification');
const { Op } = require('sequelize');
const sequelize = require('../config');

const SELF_PARK_RESERVATION_WINDOW_MS = 30 * 60 * 1000;
const SELF_PARK_FEE_RS = 50;
const SELF_PARK_PAYMENT_METHODS = new Set(['debitcard', 'credit card', 'gpay']);
const SELF_PARK_BASE_MINUTES = 30;
const SELF_PARK_EXTRA_BLOCK_MINUTES = 60;
const SELF_PARK_EXTRA_BLOCK_FEE_RS = 10;
const RETURN_BASE_FEE_RS = 50;
const RETURN_BASE_MINUTES = 30;
const RETURN_EXTRA_BLOCK_MINUTES = 60;
const RETURN_EXTRA_BLOCK_FEE_RS = 15;

function normalizeText(value) {
  return (value || '').toString().trim().toLowerCase();
}

function normalizeVehicleNumber(value) {
  return (value || '').toString().toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function isValidVehicleNumber(value) {
  return /^[A-Z]{2}[0-9]{2}[A-Z]{1,3}[0-9]{4}$/.test(value);
}

function toMaybeInt(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeDeclineReason(value) {
  const text = (value || '').toString().trim();
  return text.length > 100 ? text.substring(0, 100) : text;
}

function normalizeDeclineNote(value) {
  const text = (value || '').toString().trim();
  return text.length > 1000 ? text.substring(0, 1000) : text;
}

function getReturnChargeEstimate(parkedConfirmedAt, now = new Date()) {
  const parkedAt = parkedConfirmedAt ? new Date(parkedConfirmedAt) : null;
  const validParkedAt = parkedAt && !Number.isNaN(parkedAt.getTime()) ? parkedAt : now;
  const elapsedMs = Math.max(0, now.getTime() - validParkedAt.getTime());
  const parkedMinutes = Math.ceil(elapsedMs / (60 * 1000));

  if (parkedMinutes <= RETURN_BASE_MINUTES) {
    return {
      parked_minutes: parkedMinutes,
      amount_rs: RETURN_BASE_FEE_RS,
      extra_blocks: 0,
    };
  }

  const remaining = parkedMinutes - RETURN_BASE_MINUTES;
  const extraBlocks = Math.ceil(remaining / RETURN_EXTRA_BLOCK_MINUTES);
  return {
    parked_minutes: parkedMinutes,
    amount_rs: RETURN_BASE_FEE_RS + extraBlocks * RETURN_EXTRA_BLOCK_FEE_RS,
    extra_blocks: extraBlocks,
  };
}

function getSelfParkAdditionalCharge(parkedConfirmedAt, now = new Date()) {
  const parkedAt = parkedConfirmedAt ? new Date(parkedConfirmedAt) : null;
  const validParkedAt = parkedAt && !Number.isNaN(parkedAt.getTime()) ? parkedAt : now;
  const elapsedMs = Math.max(0, now.getTime() - validParkedAt.getTime());
  const parkedMinutes = Math.ceil(elapsedMs / (60 * 1000));

  if (parkedMinutes <= SELF_PARK_BASE_MINUTES) {
    return {
      parked_minutes: parkedMinutes,
      amount_rs: 0,
      extra_blocks: 0,
      total_paid_rs: SELF_PARK_FEE_RS,
    };
  }

  const remaining = parkedMinutes - SELF_PARK_BASE_MINUTES;
  const extraBlocks = Math.ceil(remaining / SELF_PARK_EXTRA_BLOCK_MINUTES);
  const extraAmount = extraBlocks * SELF_PARK_EXTRA_BLOCK_FEE_RS;
  return {
    parked_minutes: parkedMinutes,
    amount_rs: extraAmount,
    extra_blocks: extraBlocks,
    total_paid_rs: SELF_PARK_FEE_RS + extraAmount,
  };
}

async function notifySecurityForReturnRequest(booking) {
  if (!booking || !booking.location_id) {
    return { count: 0, recipients: [], location: null };
  }

  const location = await ParkingLocation.findOne({
    where: { id: booking.location_id }
  });
  if (!location) {
    return { count: 0, recipients: [], location: null };
  }

  const activeSecurity = await SecurityDetails.findAll({
    where: { status: 'active' }
  });
  if (!activeSecurity || activeSecurity.length === 0) {
    return { count: 0, recipients: [], location };
  }

  const locationNameLower = normalizeText(location.name);
  const locationId = Number(location.id);
  const recipientUserIds = [];
  for (const security of activeSecurity) {
    const assigned = security.parking_location;
    const assignedByName = normalizeText(assigned);
    const assignedById = toMaybeInt(assigned);
    const matchesByName = assignedByName && assignedByName === locationNameLower;
    const matchesById = assignedById !== null && assignedById === locationId;
    if (matchesByName || matchesById) {
      recipientUserIds.push(security.user_id);
    }
  }

  if (recipientUserIds.length === 0) {
    return { count: 0, recipients: [], location: null };
  }

  const message = `Return request: slot ${booking.slot_number || 'N/A'}, vehicle ${booking.vehicle_number || 'N/A'}, location ${location.name}.`;
  const now = new Date();
  await Notification.bulkCreate(
    recipientUserIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: now
    }))
  );

  return { count: recipientUserIds.length, recipients: recipientUserIds, location };
}

async function notifySecurityForSelfParkBooking(booking) {
  if (!booking || !booking.location_id) {
    return { count: 0, recipients: [], location: null };
  }

  const location = await ParkingLocation.findOne({
    where: { id: booking.location_id }
  });
  if (!location) {
    return { count: 0, recipients: [], location: null };
  }

  const activeSecurity = await SecurityDetails.findAll({
    where: { status: 'active' }
  });
  if (!activeSecurity || activeSecurity.length === 0) {
    return { count: 0, recipients: [], location };
  }

  const locationNameLower = normalizeText(location.name);
  const locationId = Number(location.id);
  const recipientUserIds = [];
  for (const security of activeSecurity) {
    const assigned = security.parking_location;
    const assignedByName = normalizeText(assigned);
    const assignedById = toMaybeInt(assigned);
    const matchesByName = assignedByName && assignedByName === locationNameLower;
    const matchesById = assignedById !== null && assignedById === locationId;
    if (matchesByName || matchesById) {
      recipientUserIds.push(security.user_id);
    }
  }

  if (recipientUserIds.length === 0) {
    return { count: 0, recipients: [], location: null };
  }

  const message =
    `New self-parking booking: slot ${booking.slot_number || 'N/A'}, ` +
    `vehicle ${booking.vehicle_number || 'N/A'}, location ${location.name}.`;
  const now = new Date();
  await Notification.bulkCreate(
    recipientUserIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: now
    }))
  );

  return { count: recipientUserIds.length, recipients: recipientUserIds, location };
}

async function notifySecurityForValetAssignment(booking) {
  if (!booking || !booking.location_id) {
    return { count: 0, recipients: [], location: null };
  }

  const location = await ParkingLocation.findOne({
    where: { id: booking.location_id }
  });
  if (!location) {
    return { count: 0, recipients: [], location: null };
  }

  const activeSecurity = await SecurityDetails.findAll({
    where: { status: 'active' }
  });
  if (!activeSecurity || activeSecurity.length === 0) {
    return { count: 0, recipients: [], location };
  }

  const locationNameLower = normalizeText(location.name);
  const locationId = Number(location.id);
  const recipientUserIds = [];
  for (const security of activeSecurity) {
    const assigned = security.parking_location;
    const assignedByName = normalizeText(assigned);
    const assignedById = toMaybeInt(assigned);
    const matchesByName = assignedByName && assignedByName === locationNameLower;
    const matchesById = assignedById !== null && assignedById === locationId;
    if (matchesByName || matchesById) {
      recipientUserIds.push(security.user_id);
    }
  }

  if (recipientUserIds.length === 0) {
    return { count: 0, recipients: [], location: null };
  }

  let driverLabel = '';
  if (booking.driver_id != null) {
    try {
      const driver = await User.findOne({
        where: { id: booking.driver_id },
        attributes: ['id', 'name'],
      });
      if (driver) {
        driverLabel = driver.name
          ? `${driver.name} (ID ${driver.id})`
          : `Driver ID ${driver.id}`;
      }
    } catch (_) {}
  }

  const message =
    `Valet incoming: slot ${booking.slot_number || 'N/A'}, ` +
    `vehicle ${booking.vehicle_number || 'N/A'}, location ${location.name}` +
    (driverLabel ? `, driver ${driverLabel}.` : '.');
  const now = new Date();
  await Notification.bulkCreate(
    recipientUserIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: now
    }))
  );

  return { count: recipientUserIds.length, recipients: recipientUserIds, location };
}

async function notifyDriversForReturnRequest(booking, locationName) {
  const activeDrivers = await DriverDetails.findAll({
    where: { status: { [Op.in]: ['available', 'busy'] } }
  });

  const driverUserIds = new Set(
    (activeDrivers || [])
      .map((driver) => Number(driver.user_id))
      .filter((id) => Number.isFinite(id) && id > 0)
  );

  // Fallback: include all driver-role users so notifications still work
  // even when driver_details status rows are missing or stale.
  const driverUsers = await User.findAll({
    where: { role: 'driver' },
    attributes: ['id']
  });
  for (const driverUser of driverUsers) {
    const id = Number(driverUser.id);
    if (Number.isFinite(id) && id > 0) {
      driverUserIds.add(id);
    }
  }

  if (driverUserIds.size === 0) {
    return 0;
  }

  const message = `Return request available: slot ${booking.slot_number || 'N/A'}, vehicle ${booking.vehicle_number || 'N/A'}, location ${locationName || 'N/A'}.`;
  const now = new Date();
  const recipientIds = [...driverUserIds];
  await Notification.bulkCreate(
    recipientIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: now
    }))
  );

  return recipientIds.length;
}

async function notifyDriversForValetRequest(booking) {
  const activeDrivers = await DriverDetails.findAll({
    where: { status: { [Op.in]: ['available', 'busy'] } }
  });

  const driverUserIds = new Set(
    (activeDrivers || [])
      .map((driver) => Number(driver.user_id))
      .filter((id) => Number.isFinite(id) && id > 0)
  );

  // Fallback: include all driver-role users if driver_details rows are missing.
  const driverUsers = await User.findAll({
    where: { role: 'driver' },
    attributes: ['id']
  });
  for (const driverUser of driverUsers) {
    const id = Number(driverUser.id);
    if (Number.isFinite(id) && id > 0) {
      driverUserIds.add(id);
    }
  }

  if (driverUserIds.size === 0) return 0;

  const lat = booking.customer_latitude != null
    ? Number(booking.customer_latitude).toFixed(6)
    : 'N/A';
  const lng = booking.customer_longitude != null
    ? Number(booking.customer_longitude).toFixed(6)
    : 'N/A';

  const message =
    `New valet booking request: vehicle ${booking.vehicle_number || 'N/A'} ` +
    `(${booking.vehicle_type || 'N/A'}), pickup at ${lat}, ${lng}.`;

  const recipientIds = [...driverUserIds];
  const now = new Date();
  await Notification.bulkCreate(
    recipientIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: now
    }))
  );

  return recipientIds.length;
}

async function notifyCustomer(userId, message) {
  if (!userId) return;
  await Notification.create({
    user_id: userId,
    message,
    type: 'in-app',
    is_read: false,
    created_at: new Date()
  });
}

function getTodayRange() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(start.getDate() + 1);
  return { start, end };
}

async function getActiveDriverIds(options = {}) {
  const { transaction } = options;
  const driverDetails = await DriverDetails.findAll({
    attributes: ['user_id', 'status'],
    transaction,
  });

  const inactiveDriverIds = new Set();
  const activeDriverIds = new Set();
  for (const driver of driverDetails || []) {
    const userId = Number(driver.user_id);
    if (!Number.isFinite(userId) || userId <= 0) continue;
    const status = normalizeText(driver.status);
    if (status === 'inactive') {
      inactiveDriverIds.add(userId);
    } else if (status === 'available' || status === 'busy' || !status) {
      activeDriverIds.add(userId);
    }
  }

  const driverUsers = await User.findAll({
    where: { role: 'driver' },
    attributes: ['id'],
    transaction,
  });
  for (const driverUser of driverUsers || []) {
    const id = Number(driverUser.id);
    if (Number.isFinite(id) && id > 0 && !inactiveDriverIds.has(id)) {
      activeDriverIds.add(id);
    }
  }

  return [...activeDriverIds].sort((a, b) => a - b);
}

async function getDeclinedDriverIds(bookingId, requestType, options = {}) {
  const { transaction } = options;
  const declines = await BookingDecline.findAll({
    where: {
      booking_id: bookingId,
      request_type: requestType,
    },
    attributes: ['driver_id'],
    transaction,
  });

  return new Set(
    (declines || [])
      .map((decline) => Number(decline.driver_id))
      .filter((id) => Number.isFinite(id) && id > 0)
  );
}

async function hasDriverDeclinedRequest(
  bookingId,
  requestType,
  driverId,
  options = {},
) {
  if (!driverId) return false;
  const { transaction } = options;
  const decline = await BookingDecline.findOne({
    where: {
      booking_id: bookingId,
      driver_id: driverId,
      request_type: requestType,
    },
    attributes: ['id'],
    transaction,
  });

  return Boolean(decline);
}

async function recordBookingDecline(bookingId, driverId, requestType, options = {}) {
  const { transaction, declineReason, declineNote } = options;
  const reason = normalizeDeclineReason(declineReason);
  const note = normalizeDeclineNote(declineNote);
  const existing = await BookingDecline.findOne({
    where: {
      booking_id: bookingId,
      driver_id: driverId,
      request_type: requestType,
    },
    transaction,
  });
  if (existing) {
    existing.decline_reason = reason || existing.decline_reason;
    existing.decline_note = note || existing.decline_note;
    existing.declined_at = new Date();
    await existing.save({ transaction });
    return existing;
  }

  return BookingDecline.create({
    booking_id: bookingId,
    driver_id: driverId,
    request_type: requestType,
    decline_reason: reason || null,
    decline_note: note || null,
  }, { transaction });
}

async function notifyAdminsForBookingDecline(
  booking,
  driverId,
  requestType,
  declineReason,
  declineNote,
) {
  if (!booking) return 0;

  const admins = await User.findAll({
    where: { role: 'admin' },
    attributes: ['id'],
  });
  if (!admins || admins.length === 0) return 0;

  let driverLabel = `Driver ${driverId}`;
  try {
    const driver = await User.findOne({
      where: { id: driverId },
      attributes: ['id', 'name'],
    });
    if (driver) {
      driverLabel = driver.name
        ? `${driver.name} (ID ${driver.id})`
        : `Driver ${driver.id}`;
    }
  } catch (_) {}

  const typeLabel = requestType === 'return' ? 'return' : 'pickup';
  const reason = normalizeDeclineReason(declineReason) || 'No reason provided';
  const note = normalizeDeclineNote(declineNote);
  const token = booking.booking_token || booking.id || 'N/A';
  const message =
    `${driverLabel} declined a valet ${typeLabel} request. ` +
    `Booking ${token}, vehicle ${booking.vehicle_number || 'N/A'}. ` +
    `Reason: ${reason}${note ? `. Note: ${note}` : ''}`;

  const now = new Date();
  await Notification.bulkCreate(
    admins.map((admin) => ({
      user_id: admin.id,
      message,
      type: 'in-app',
      is_read: false,
      created_at: now,
    }))
  );

  return admins.length;
}

async function getDriverAcceptedCountsToday(driverIds, options = {}) {
  const { transaction } = options;
  const countMap = new Map(driverIds.map((id) => [Number(id), 0]));
  if (!driverIds.length) return countMap;

  const { start, end } = getTodayRange();

  const pickupCounts = await Booking.findAll({
    attributes: ['driver_id', [sequelize.fn('COUNT', sequelize.col('id')), 'count']],
    where: {
      driver_id: { [Op.in]: driverIds },
      status: { [Op.ne]: 'cancelled' },
      [Op.or]: [
        { driver_accepted_at: { [Op.gte]: start, [Op.lt]: end } },
        {
          driver_accepted_at: null,
          booking_time: { [Op.gte]: start, [Op.lt]: end },
        },
      ],
    },
    group: ['driver_id'],
    transaction,
  });
  for (const row of pickupCounts || []) {
    const id = Number(row.driver_id);
    countMap.set(id, (countMap.get(id) || 0) + Number(row.get('count') || 0));
  }

  const returnCounts = await Booking.findAll({
    attributes: ['return_driver_id', [sequelize.fn('COUNT', sequelize.col('id')), 'count']],
    where: {
      return_driver_id: { [Op.in]: driverIds },
      return_accepted_at: { [Op.gte]: start, [Op.lt]: end },
    },
    group: ['return_driver_id'],
    transaction,
  });
  for (const row of returnCounts || []) {
    const id = Number(row.return_driver_id);
    countMap.set(id, (countMap.get(id) || 0) + Number(row.get('count') || 0));
  }

  return countMap;
}

async function getPriorityQueueForRequest(bookingId, requestType, options = {}) {
  const { transaction } = options;
  const activeDriverIds = await getActiveDriverIds({ transaction });
  const declinedDriverIds = await getDeclinedDriverIds(
    bookingId,
    requestType,
    { transaction },
  );
  const eligibleDriverIds = activeDriverIds.filter(
    (id) => !declinedDriverIds.has(Number(id)),
  );
  const countMap = await getDriverAcceptedCountsToday(
    eligibleDriverIds,
    { transaction },
  );

  return eligibleDriverIds
    .map((driverId) => ({
      driverId,
      acceptedCountToday: countMap.get(Number(driverId)) || 0,
    }))
    .sort((a, b) => {
      if (a.acceptedCountToday !== b.acceptedCountToday) {
        return a.acceptedCountToday - b.acceptedCountToday;
      }
      return a.driverId - b.driverId;
    });
}

async function getPriorityContextForDriver(bookingId, requestType, driverId, options = {}) {
  const queue = await getPriorityQueueForRequest(bookingId, requestType, options);
  const index = queue.findIndex((entry) => Number(entry.driverId) === Number(driverId));
  const current = index >= 0 ? queue[index] : null;

  return {
    eligible_to_accept: index === 0,
    priority_position: index >= 0 ? index + 1 : null,
    accepted_requests_today: current ? current.acceptedCountToday : null,
    current_priority_driver_id: queue.length ? queue[0].driverId : null,
  };
}

async function notifySecurityReturnAccepted(booking, locationName, driverLabel) {
  if (!booking || !booking.location_id) return 0;
  const activeSecurity = await SecurityDetails.findAll({
    where: { status: 'active' }
  });
  if (!activeSecurity || activeSecurity.length === 0) {
    return 0;
  }

  const locationNameLower = normalizeText(locationName);
  const locationId = Number(booking.location_id);
  const recipientUserIds = [];
  for (const security of activeSecurity) {
    const assigned = security.parking_location;
    const assignedByName = normalizeText(assigned);
    const assignedById = toMaybeInt(assigned);
    const matchesByName =
      assignedByName && locationNameLower && assignedByName === locationNameLower;
    const matchesById = assignedById !== null && assignedById === locationId;
    if (matchesByName || matchesById) {
      recipientUserIds.push(security.user_id);
    }
  }
  if (recipientUserIds.length === 0) return 0;

  const message =
    `Return accepted by ${driverLabel}. Vehicle ${booking.vehicle_number || 'N/A'}, ` +
    `slot ${booking.slot_number || 'N/A'}, destination ${booking.desired_return_location || 'requested location'}.`;
  await Notification.bulkCreate(
    recipientUserIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: new Date()
    }))
  );
  return recipientUserIds.length;
}

async function notifySecurityReturnCompleted(booking, customerLabel) {
  if (!booking || !booking.location_id) return 0;

  const location = await ParkingLocation.findOne({
    where: { id: booking.location_id }
  });
  if (!location) return 0;

  const activeSecurity = await SecurityDetails.findAll({
    where: { status: 'active' }
  });
  if (!activeSecurity || activeSecurity.length === 0) return 0;

  const locationNameLower = normalizeText(location.name);
  const locationId = Number(location.id);
  const recipientUserIds = [];
  for (const security of activeSecurity) {
    const assigned = security.parking_location;
    const assignedByName = normalizeText(assigned);
    const assignedById = toMaybeInt(assigned);
    const matchesByName = assignedByName && assignedByName === locationNameLower;
    const matchesById = assignedById !== null && assignedById === locationId;
    if (matchesByName || matchesById) {
      recipientUserIds.push(security.user_id);
    }
  }
  if (recipientUserIds.length === 0) return 0;

  const message =
    `${customerLabel} confirmed return completed. Vehicle ${booking.vehicle_number || 'N/A'} ` +
    `from slot ${booking.slot_number || 'N/A'} is closed.`;
  await Notification.bulkCreate(
    recipientUserIds.map((userId) => ({
      user_id: userId,
      message,
      type: 'in-app',
      is_read: false,
      created_at: new Date()
    }))
  );
  return recipientUserIds.length;
}

// Create a new booking
exports.createBooking = async (req, res) => {
  try {

    console.log('createBooking payload:', req.body);
    const {
      location_id,
      vehicle_number,
      vehicle_type,
      customer_latitude,
      customer_longitude,
      location_name,
      location_address,
      latitude,
      longitude,
      total_slots,
      available_slots
    } = req.body;

    // Use user_id from JWT
    const user_id = req.user && req.user.id;

    // Generate a booking token (simple example)
    const booking_token = 'VAL' + Date.now();

    let locId = location_id;
    // For Book Valet, do not require location_id or location_name. Allow location_id to be null.
    // Only create parking location if location_name is provided (for Park Yourself flow).
    if (location_name) {
      const newLocation = await ParkingLocation.create({
        name: location_name,
        address: location_address || '',
        latitude,
        longitude,
        total_slots,
        available_slots
      });
      locId = newLocation.id;
    }

    const slotId = req.body.slot_id;
    const slotNumber = req.body.slot_number;
    const hasSelectedSlot = Boolean(slotId || (slotNumber && locId));
    const now = new Date();
    const paymentMethod = (req.body.payment_method || '').toString().trim().toLowerCase();
    const paymentAmount = Number(req.body.payment_amount);
    const normalizedVehicleNumber = normalizeVehicleNumber(vehicle_number);

    if (!isValidVehicleNumber(normalizedVehicleNumber)) {
      return res.status(400).json({
        success: false,
        error: 'Vehicle number must be in a valid format such as KL58AH9653'
      });
    }

    if (hasSelectedSlot) {
      if (!paymentMethod) {
        return res.status(400).json({
          success: false,
          error: 'Payment method is required for self parking'
        });
      }

      if (!SELF_PARK_PAYMENT_METHODS.has(paymentMethod)) {
        return res.status(400).json({
          success: false,
          error: 'Payment method must be one of: debitcard, credit card, gpay'
        });
      }

      if (!Number.isFinite(paymentAmount) || paymentAmount !== SELF_PARK_FEE_RS) {
        return res.status(400).json({
          success: false,
          error: `Self parking fee must be Rs ${SELF_PARK_FEE_RS}`
        });
      }
    }

    const bookingPayload = {
      booking_token,
      user_id,
      location_id: locId,
      slot_number: slotNumber,
      vehicle_number: normalizedVehicleNumber,
      vehicle_type: (vehicle_type || '').toString().trim(),
      booking_time: now,
      customer_latitude,
      customer_longitude,
      status: 'pending',
      payment_status: hasSelectedSlot ? 'paid' : 'unpaid',
      payment_method: hasSelectedSlot ? paymentMethod : null,
      payment_amount: hasSelectedSlot ? SELF_PARK_FEE_RS : null,
      payment_time: hasSelectedSlot ? now : null
    };

    let booking = null;
    let notifiedDriverCount = 0;
    let notifiedSecurityCount = 0;
    if (!hasSelectedSlot) {
      booking = await Booking.create(bookingPayload);
      try {
        notifiedDriverCount = await notifyDriversForValetRequest(booking);
      } catch (notifyError) {
        console.error(
          'Failed to notify drivers for valet booking:',
          notifyError.message || notifyError
        );
      }
    } else {
      booking = await sequelize.transaction(async (transaction) => {
        let slotRecord = null;
        if (slotId) {
          slotRecord = await ParkingSlot.findOne({
            where: { id: slotId },
            transaction,
            lock: transaction.LOCK.UPDATE
          });
        } else {
          slotRecord = await ParkingSlot.findOne({
            where: { slot_number: slotNumber, location_id: locId },
            transaction,
            lock: transaction.LOCK.UPDATE
          });
        }

        if (!slotRecord) {
          const err = new Error('Selected slot not found');
          err.statusCode = 404;
          throw err;
        }

        if (locId && Number(slotRecord.location_id) !== Number(locId)) {
          const err = new Error('Selected slot does not belong to this location');
          err.statusCode = 400;
          throw err;
        }

        const effectiveLocationId = locId || slotRecord.location_id;
        if (!bookingPayload.location_id && effectiveLocationId) {
          bookingPayload.location_id = effectiveLocationId;
        }

        if (slotRecord.status !== 'available') {
          const err = new Error('Selected slot is not available');
          err.statusCode = 409;
          throw err;
        }

        const createdBooking = await Booking.create(bookingPayload, { transaction });

        // Self-park booking blocks the slot immediately.
        await ParkingSlot.update(
          { status: 'occupied' },
          { where: { id: slotRecord.id }, transaction }
        );

        const reservedFrom = new Date();
        const reservedTo = new Date(reservedFrom.getTime() + SELF_PARK_RESERVATION_WINDOW_MS);
        await SlotReservation.create({
          slot_id: slotRecord.id,
          booking_id: createdBooking.id,
          reserved_from: reservedFrom,
          reserved_to: reservedTo
        }, { transaction });

        if (effectiveLocationId) {
          const loc = await ParkingLocation.findOne({
            where: { id: effectiveLocationId },
            transaction,
            lock: transaction.LOCK.UPDATE
          });
          if (loc && typeof loc.available_slots === 'number') {
            const currentAvailable = Number(loc.available_slots) || 0;
            const nextAvailable = Math.max(0, currentAvailable - 1);
            await ParkingLocation.update(
              { available_slots: nextAvailable },
              { where: { id: effectiveLocationId }, transaction }
            );
          }
        }

        return createdBooking;
      });
      try {
        const securityNotifyResult = await notifySecurityForSelfParkBooking(booking);
        notifiedSecurityCount = securityNotifyResult.count;
      } catch (notifyError) {
        console.error(
          'Failed to notify security for self parking booking:',
          notifyError.message || notifyError
        );
      }
    }

    res.status(201).json({
      success: true,
      booking,
      notified_driver_count: notifiedDriverCount,
      notified_security_count: notifiedSecurityCount,
    });
  } catch (error) {
    const statusCode = error.statusCode || 500;
    res.status(statusCode).json({ success: false, error: error.message });
  }
};

// Get user's current booking
exports.getUserCurrentBooking = async (req, res) => {
  try {
    const user_id = req.user && req.user.id;
    if (!user_id) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    // Get the most recent pending or confirmed booking for this user
    const booking = await Booking.findOne({
      where: {
        user_id,
        status: { [Op.in]: ['pending', 'confirmed'] }
      },
      order: [['id', 'DESC']]
    });

    if (!booking) {
      return res.status(404).json({ success: false, message: 'No active booking found' });
    }

    const raw = booking.toJSON();
    const userIds = [];
    if (raw.driver_id != null) userIds.push(Number(raw.driver_id));
    if (raw.return_driver_id != null) userIds.push(Number(raw.return_driver_id));

    const location =
      raw.location_id != null
        ? await ParkingLocation.findOne({
            where: { id: raw.location_id },
            attributes: ['id', 'name', 'address'],
          })
        : null;

    let securityUserId = null;
    let matchedSecurity = [];
    if (location) {
      const activeSecurity = await SecurityDetails.findAll({
        where: { status: 'active' },
      });
      if (activeSecurity && activeSecurity.length > 0) {
        const locationNameLower = normalizeText(location.name);
        const locationId = Number(location.id);
        matchedSecurity = activeSecurity.filter((security) => {
          const assigned = security.parking_location;
          const assignedByName = normalizeText(assigned);
          const assignedById = toMaybeInt(assigned);
          const matchesByName =
            assignedByName && assignedByName === locationNameLower;
          const matchesById = assignedById !== null && assignedById === locationId;
          return matchesByName || matchesById;
        });
        if (matchedSecurity.length > 0) {
          const securityIds = matchedSecurity
            .map((security) => Number(security.user_id))
            .filter((id) => Number.isFinite(id));
          if (securityIds.length > 0) {
            securityUserId = securityIds[0];
            userIds.push(...securityIds);
          }
        }
      }
    }

    const usersWithSecurity = userIds.length
      ? await User.findAll({
          where: { id: { [Op.in]: userIds } },
          attributes: ['id', 'name', 'phone'],
        })
      : [];
    const userById = new Map(usersWithSecurity.map((u) => [Number(u.id), u]));

    const securityStaff = matchedSecurity
      .map((security) => {
        const id = Number(security.user_id);
        const user = userById.get(id);
        return {
          user_id: Number.isFinite(id) ? id : null,
          name: user?.name || null,
          phone: user?.phone || null,
        };
      })
      .filter((entry) => entry.user_id != null);

    const enrichedBooking = {
      ...raw,
      driver_name:
        raw.driver_id != null
          ? userById.get(Number(raw.driver_id))?.name || null
          : null,
      driver_phone:
        raw.driver_id != null
          ? userById.get(Number(raw.driver_id))?.phone || null
          : null,
      return_driver_name:
        raw.return_driver_id != null
          ? userById.get(Number(raw.return_driver_id))?.name || null
          : null,
      return_driver_phone:
        raw.return_driver_id != null
          ? userById.get(Number(raw.return_driver_id))?.phone || null
          : null,
      security_name:
        securityUserId != null
          ? userById.get(Number(securityUserId))?.name || null
          : null,
      security_phone:
        securityUserId != null
          ? userById.get(Number(securityUserId))?.phone || null
          : null,
      security_staff: securityStaff,
      location_name: location ? location.name : null,
      location_address: location ? location.address : null,
    };

    res.json({ success: true, booking: enrichedBooking });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get available bookings for drivers (valet only), with eligibility status for each driver.
exports.getAvailableBookings = async (req, res) => {
  try {
    const userId = req.user && req.user.id;
    const bookings = await Booking.findAll({
      where: {
        status: 'pending',
        driver_id: null,
        slot_number: null,
        location_id: null
      }
    });

    // Extra safety: exclude any booking that still has a reservation record.
    const availableForDriver = [];
    for (const booking of bookings) {
      const reservation = await SlotReservation.findOne({
        where: { booking_id: booking.id }
      });
      if (!reservation) {
        availableForDriver.push(booking);
      }
    }

    const results = [];
    for (const booking of availableForDriver) {
      if (userId) {
        const alreadyDeclined = await hasDriverDeclinedRequest(
          booking.id,
          'pickup',
          userId,
        );
        if (alreadyDeclined) continue;
      }

      const priority = userId
        ? await getPriorityContextForDriver(booking.id, 'pickup', userId)
        : {
            eligible_to_accept: false,
            priority_position: null,
            accepted_requests_today: null,
            current_priority_driver_id: null,
          };
      results.push({
        ...booking.toJSON(),
        request_type: 'pickup',
        ...priority,
      });
    }

    res.json({
      success: true,
      bookings: results,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get all bookings
exports.getAllBookings = async (req, res) => {
  try {
    const bookings = await Booking.findAll();
    const userIds = new Set();
    const bookingIds = [];
    for (const booking of bookings) {
      bookingIds.push(Number(booking.id));
      if (booking.user_id != null) userIds.add(Number(booking.user_id));
      if (booking.driver_id != null) userIds.add(Number(booking.driver_id));
      if (booking.return_driver_id != null) {
        userIds.add(Number(booking.return_driver_id));
      }
    }

    const declines = bookingIds.length
      ? await BookingDecline.findAll({
          where: { booking_id: { [Op.in]: bookingIds } },
          order: [['declined_at', 'DESC']],
        })
      : [];

    for (const decline of declines) {
      if (decline.driver_id != null) userIds.add(Number(decline.driver_id));
    }

    const users = userIds.size
      ? await User.findAll({
          where: { id: { [Op.in]: [...userIds] } },
          attributes: ['id', 'name']
        })
      : [];

    const userNameById = new Map(users.map((u) => [Number(u.id), u.name]));
    const declinesByBookingId = new Map();
    for (const decline of declines) {
      const rawDecline = decline.toJSON();
      const bookingId = Number(rawDecline.booking_id);
      if (!declinesByBookingId.has(bookingId)) {
        declinesByBookingId.set(bookingId, []);
      }
      declinesByBookingId.get(bookingId).push({
        ...rawDecline,
        driver_name: userNameById.get(Number(rawDecline.driver_id)) || null,
      });
    }

    const enriched = bookings.map((booking) => {
      const raw = booking.toJSON();
      return {
        ...raw,
        customer_name: userNameById.get(Number(raw.user_id)) || null,
        driver_name: raw.driver_id != null
          ? userNameById.get(Number(raw.driver_id)) || null
          : null,
        return_driver_name: raw.return_driver_id != null
          ? userNameById.get(Number(raw.return_driver_id)) || null
          : null,
        declines: declinesByBookingId.get(Number(raw.id)) || [],
      };
    });
    res.json({ success: true, bookings: enriched });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get return requests available for any driver.
exports.getAvailableReturnRequests = async (req, res) => {
  try {
    const userId = req.user && req.user.id;
    const bookings = await Booking.findAll({
      where: {
        status: 'confirmed',
        driver_id: { [Op.not]: null },
        return_requested_at: { [Op.not]: null },
        return_driver_id: null,
        [Op.or]: [
          { return_status: null },
          { return_status: 'requested' },
        ],
      },
      order: [['id', 'DESC']],
    });

    const results = [];
    for (const booking of bookings) {
      if (userId) {
        const alreadyDeclined = await hasDriverDeclinedRequest(
          booking.id,
          'return',
          userId,
        );
        if (alreadyDeclined) continue;
      }

      const priority = userId
        ? await getPriorityContextForDriver(booking.id, 'return', userId)
        : {
            eligible_to_accept: false,
            priority_position: null,
            accepted_requests_today: null,
            current_priority_driver_id: null,
          };

      const raw = booking.toJSON();
      const location =
        raw.location_id != null
          ? await ParkingLocation.findOne({
              where: { id: raw.location_id },
              attributes: ['id', 'name', 'latitude', 'longitude'],
            })
          : null;

      results.push({
        ...raw,
        request_type: 'return',
        location_name: location ? location.name : null,
        location_latitude: location ? location.latitude : null,
        location_longitude: location ? location.longitude : null,
        ...priority,
      });
    }

    return res.json({
      success: true,
      bookings: results,
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Get booking by token
exports.getBookingByToken = async (req, res) => {
  try {
    const { token } = req.params;
    const booking = await Booking.findOne({ where: { booking_token: token } });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }
    res.json({ success: true, booking });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get driver's current accepted/active valet booking.
exports.getDriverCurrentBooking = async (req, res) => {
  try {
    const userId = req.user && req.user.id;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    // Priority 1: active accepted return request assigned to this driver.
    const returnBooking = await Booking.findOne({
      where: {
        return_driver_id: userId,
        return_status: { [Op.in]: ['accepted', 'released'] },
        status: 'confirmed',
        return_completed_at: null,
      },
      order: [['id', 'DESC']],
    });
    if (returnBooking) {
      const raw = returnBooking.toJSON();
      const location =
        raw.location_id != null
          ? await ParkingLocation.findOne({
              where: { id: raw.location_id },
              attributes: ['id', 'name', 'latitude', 'longitude'],
            })
          : null;
      return res.json({
        success: true,
        booking: {
          ...raw,
          request_type: 'return',
          location_name: location ? location.name : null,
          location_latitude: location ? location.latitude : null,
          location_longitude: location ? location.longitude : null,
        },
      });
    }

    const booking = await Booking.findOne({
      where: {
        driver_id: userId,
        // Pickup request should remain visible only until security confirms parking.
        status: 'pending',
      },
      order: [['id', 'DESC']],
    });

    if (!booking) {
      return res
        .status(404)
        .json({ success: false, message: 'No active driver booking found' });
    }

    const raw = booking.toJSON();
    const location =
      raw.location_id != null
        ? await ParkingLocation.findOne({
            where: { id: raw.location_id },
            attributes: ['id', 'name', 'latitude', 'longitude'],
          })
        : null;
    return res.json({
      success: true,
      booking: {
        ...raw,
        request_type: 'pickup',
        location_name: location ? location.name : null,
        location_latitude: location ? location.latitude : null,
        location_longitude: location ? location.longitude : null,
      },
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Get return payment estimate for a confirmed booking.
exports.getReturnPaymentEstimate = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const booking = await Booking.findOne({ where: { booking_token: token } });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }

    const isOwner = Number(booking.user_id) === Number(userId);
    if (!isOwner && role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Not allowed' });
    }

    if (!booking.slot_number || booking.status !== 'confirmed') {
      return res.status(400).json({
        success: false,
        message: 'Return estimate is available only after parking is confirmed',
      });
    }

    const isSelfParking =
      Number(booking.driver_id || 0) === 0 &&
      booking.location_id != null &&
      booking.slot_number != null;

    const estimate = isSelfParking
      ? getSelfParkAdditionalCharge(
          booking.parked_confirmed_at || booking.booking_time,
          new Date(),
        )
      : getReturnChargeEstimate(
          booking.parked_confirmed_at || booking.booking_time,
          new Date(),
        );

    return res.json({
      success: true,
      estimate: {
        ...estimate,
        base_fee_rs: isSelfParking ? SELF_PARK_FEE_RS : RETURN_BASE_FEE_RS,
        base_minutes: isSelfParking ? SELF_PARK_BASE_MINUTES : RETURN_BASE_MINUTES,
        extra_fee_per_10_min_rs: null,
        extra_fee_per_hour_rs: isSelfParking
          ? SELF_PARK_EXTRA_BLOCK_FEE_RS
          : RETURN_EXTRA_BLOCK_FEE_RS,
        extra_hours: estimate.extra_blocks,
        additional_due_rs: isSelfParking ? estimate.amount_rs : null,
        total_paid_rs: isSelfParking ? estimate.total_paid_rs : null,
      },
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Customer requests vehicle return with desired location and payment.
exports.requestVehicleReturn = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const booking = await Booking.findOne({ where: { booking_token: token } });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }

    const isOwner = Number(booking.user_id) === Number(userId);
    if (!isOwner && role !== 'admin') {
      return res.status(403).json({ success: false, message: 'You can request return only for your own booking' });
    }

    if (!booking.slot_number) {
      return res.status(400).json({ success: false, message: 'No slot assigned for this booking' });
    }

    if (booking.status !== 'confirmed') {
      return res.status(400).json({
        success: false,
        message: 'Return can be requested only after security confirms parking'
      });
    }

    if (booking.return_requested_at) {
      return res.json({
        success: true,
        booking,
        message: 'Return request already submitted',
        notified_security_count: 0,
        notified_driver_count: 0,
      });
    }

    const desiredReturnLocationInput = (req.body.desired_return_location || '')
      .toString()
      .trim();
    const requiresDesiredLocation = Number(booking.driver_id || 0) > 0;
    if (requiresDesiredLocation && !desiredReturnLocationInput) {
      return res.status(400).json({
        success: false,
        message: 'Desired return location is required',
      });
    }
    const desiredReturnLocation =
      desiredReturnLocationInput || 'Parking gate pickup';

    const desiredReturnLatitude = req.body.desired_return_latitude;
    const desiredReturnLongitude = req.body.desired_return_longitude;

    const isSelfParking =
      Number(booking.driver_id || 0) === 0 &&
      booking.location_id != null &&
      booking.slot_number != null;

    const estimate = isSelfParking
      ? getSelfParkAdditionalCharge(
          booking.parked_confirmed_at || booking.booking_time,
          new Date(),
        )
      : getReturnChargeEstimate(
          booking.parked_confirmed_at || booking.booking_time,
          new Date(),
        );

    if (isSelfParking) {
      // Self-park: charge only additional amount beyond the base 30 minutes.
      const additionalDue = Number(estimate.amount_rs) || 0;
      const basePaidRaw = Number(booking.payment_amount);
      const basePaid =
        Number.isFinite(basePaidRaw) && basePaidRaw > 0
          ? basePaidRaw
          : SELF_PARK_FEE_RS;
      if (additionalDue > 0) {
        const paymentMethod = (req.body.payment_method || '')
          .toString()
          .trim()
          .toLowerCase();
        const paymentAmount = Number(req.body.payment_amount);
        if (!paymentMethod) {
          return res.status(400).json({
            success: false,
            message: 'Payment method is required for additional self parking time',
          });
        }
        if (!SELF_PARK_PAYMENT_METHODS.has(paymentMethod)) {
          return res.status(400).json({
            success: false,
            message: 'Payment method must be one of: debitcard, credit card, gpay',
          });
        }
        if (!Number.isFinite(paymentAmount) || paymentAmount !== additionalDue) {
          return res.status(400).json({
            success: false,
            message: `Additional parking fee must be Rs ${additionalDue}`,
          });
        }

        booking.payment_status = 'paid';
        booking.payment_method = paymentMethod;
        booking.payment_amount = basePaid + additionalDue;
        booking.payment_time = new Date();
      } else if (!Number.isFinite(basePaidRaw) || basePaidRaw <= 0) {
        // Safety: ensure base payment is persisted for older rows.
        booking.payment_amount = basePaid;
        if ((booking.payment_status || '').toString().toLowerCase() !== 'paid') {
          booking.payment_status = 'paid';
        }
      }
    } else if ((booking.payment_status || '').toString().toLowerCase() !== 'paid') {
      // Valet return flow: collect payment at return request time.
      const paymentMethod = (req.body.payment_method || '')
        .toString()
        .trim()
        .toLowerCase();
      const paymentAmount = Number(req.body.payment_amount);
      if (!paymentMethod) {
        return res.status(400).json({
          success: false,
          message: 'Payment method is required',
        });
      }
      if (!SELF_PARK_PAYMENT_METHODS.has(paymentMethod)) {
        return res.status(400).json({
          success: false,
          message: 'Payment method must be one of: debitcard, credit card, gpay',
        });
      }
      if (!Number.isFinite(paymentAmount) || paymentAmount !== estimate.amount_rs) {
        return res.status(400).json({
          success: false,
          message: `Return fee must be Rs ${estimate.amount_rs}`,
        });
      }

      booking.payment_status = 'paid';
      booking.payment_method = paymentMethod;
      booking.payment_amount = estimate.amount_rs;
      booking.payment_time = new Date();
    }

    booking.return_requested_at = new Date();
    booking.desired_return_location = desiredReturnLocation;
    booking.desired_return_latitude =
      desiredReturnLatitude != null ? Number(desiredReturnLatitude) : null;
    booking.desired_return_longitude =
      desiredReturnLongitude != null ? Number(desiredReturnLongitude) : null;
    if (booking.driver_id) {
      booking.return_status = 'requested';
      booking.return_driver_id = null;
      booking.return_accepted_at = null;
    } else {
      booking.return_status = null;
      booking.return_driver_id = null;
      booking.return_accepted_at = null;
    }
    await booking.save();

    let notifiedSecurityCount = 0;
    let notifiedDriverCount = 0;
    try {
      const securityNotifyResult = await notifySecurityForReturnRequest(booking);
      notifiedSecurityCount = securityNotifyResult.count;
      const locationName =
        securityNotifyResult.location && securityNotifyResult.location.name
          ? securityNotifyResult.location.name
          : '';
      if (booking.driver_id) {
        notifiedDriverCount = await notifyDriversForReturnRequest(
          booking,
          locationName,
        );
      }
    } catch (notifyError) {
      console.error('Failed to notify security for return request:', notifyError.message || notifyError);
    }

    return res.json({
      success: true,
      booking,
      return_charge_rs: estimate.amount_rs,
      parked_minutes: estimate.parked_minutes,
      notified_security_count: notifiedSecurityCount,
      notified_driver_count: notifiedDriverCount,
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Driver accepts a customer return request.
exports.acceptReturnRequest = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Only drivers can accept return requests' });
    }

    const booking = await sequelize.transaction(async (transaction) => {
      const lockedBooking = await Booking.findOne({
        where: { booking_token: token },
        transaction,
        lock: transaction.LOCK.UPDATE,
      });
      if (!lockedBooking) {
        const err = new Error('Booking not found');
        err.statusCode = 404;
        throw err;
      }

      if (lockedBooking.status !== 'confirmed' || !lockedBooking.return_requested_at) {
        const err = new Error('Return request is not active for this booking');
        err.statusCode = 400;
        throw err;
      }

      if (
        lockedBooking.return_driver_id &&
        Number(lockedBooking.return_driver_id) !== Number(userId)
      ) {
        const err = new Error('Return request already accepted by another driver');
        err.statusCode = 409;
        throw err;
      }

      if (role !== 'admin' && !lockedBooking.return_driver_id) {
        const priority = await getPriorityContextForDriver(
          lockedBooking.id,
          'return',
          userId,
          { transaction },
        );
        if (!priority.eligible_to_accept) {
          const err = new Error('Please wait for your priority turn to accept this return request');
          err.statusCode = 403;
          throw err;
        }
      }

      lockedBooking.return_driver_id = userId;
      lockedBooking.return_status = 'accepted';
      lockedBooking.return_accepted_at = new Date();
      await lockedBooking.save({ transaction });
      return lockedBooking;
    });

    const acceptedDriver = await User.findOne({
      where: { id: userId },
      attributes: ['id', 'name'],
    });
    const driverLabel = acceptedDriver
      ? `${acceptedDriver.name} (ID ${acceptedDriver.id})`
      : `Driver ${userId}`;

    const location = booking.location_id
      ? await ParkingLocation.findOne({ where: { id: booking.location_id } })
      : null;
    const locationName = location ? location.name : '';

    try {
      await notifySecurityReturnAccepted(booking, locationName, driverLabel);
      await notifyCustomer(
        booking.user_id,
        `Driver accepted your return request. Driver: ${driverLabel}.`,
      );
    } catch (notifyError) {
      console.error('Failed to notify return acceptance:', notifyError.message || notifyError);
    }

    return res.json({ success: true, booking, accepted_driver: acceptedDriver });
  } catch (error) {
    return res.status(error.statusCode || 500).json({ success: false, error: error.message });
  }
};

// Driver declines return request. If current assigned driver declines, it becomes available again.
exports.declineReturnRequest = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    const declineReason = req.body && req.body.decline_reason;
    const declineNote = req.body && req.body.decline_note;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Only drivers can decline return requests' });
    }

    const booking = await sequelize.transaction(async (transaction) => {
      const lockedBooking = await Booking.findOne({
        where: { booking_token: token },
        transaction,
        lock: transaction.LOCK.UPDATE,
      });
      if (!lockedBooking) {
        const err = new Error('Booking not found');
        err.statusCode = 404;
        throw err;
      }

      if (!lockedBooking.return_requested_at || lockedBooking.status !== 'confirmed') {
        const err = new Error('Return request is not active');
        err.statusCode = 400;
        throw err;
      }

      if (
        lockedBooking.return_driver_id &&
        Number(lockedBooking.return_driver_id) !== Number(userId) &&
        role !== 'admin'
      ) {
        const err = new Error('Only the assigned return driver can decline this request');
        err.statusCode = 403;
        throw err;
      }

      if (!lockedBooking.return_driver_id && role !== 'admin') {
        const priority = await getPriorityContextForDriver(
          lockedBooking.id,
          'return',
          userId,
          { transaction },
        );
        if (!priority.eligible_to_accept) {
          const err = new Error('Please wait for your priority turn to decline this return request');
          err.statusCode = 403;
          throw err;
        }
      }

      await recordBookingDecline(lockedBooking.id, userId, 'return', {
        transaction,
        declineReason,
        declineNote,
      });
      lockedBooking.return_driver_id = null;
      lockedBooking.return_status = 'requested';
      lockedBooking.return_accepted_at = null;
      await lockedBooking.save({ transaction });
      return lockedBooking;
    });

    try {
      await notifyAdminsForBookingDecline(
        booking,
        userId,
        'return',
        declineReason,
        declineNote,
      );
    } catch (notifyError) {
      console.error(
        'Failed to notify admins for return decline:',
        notifyError.message || notifyError
      );
    }

    return res.json({
      success: true,
      booking,
      message: 'Return request is now available for other drivers',
    });
  } catch (error) {
    return res.status(error.statusCode || 500).json({ success: false, error: error.message });
  }
};

// Customer confirms the vehicle was returned successfully.
exports.confirmDriverReturnHandover = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    const providedToken = (req.body.booking_token || '').toString().trim();

    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }
    if (role !== 'driver' && role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only the assigned driver can confirm handover',
      });
    }
    if (!providedToken) {
      return res.status(400).json({
        success: false,
        message: 'Booking token is required',
      });
    }

    const booking = await Booking.findOne({ where: { booking_token: token } });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }

    if (providedToken.toLowerCase() !== booking.booking_token.toLowerCase()) {
      return res.status(400).json({
        success: false,
        message: 'Booking token does not match',
      });
    }

    if (Number(booking.return_driver_id) !== Number(userId) && role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only the assigned return driver can confirm this handover',
      });
    }

    const returnStatus = (booking.return_status || '').toString().toLowerCase();
    if (returnStatus === 'completed' || booking.status === 'completed') {
      return res.json({
        success: true,
        booking,
        message: 'Return already completed',
      });
    }

    if (returnStatus !== 'released' && returnStatus !== 'handover_confirmed') {
      return res.status(400).json({
        success: false,
        message: 'Security must release the vehicle before driver handover',
      });
    }

    booking.return_status = 'handover_confirmed';
    await booking.save();

    try {
      await notifyCustomer(
        booking.user_id,
        `Driver confirmed vehicle handover for booking ${booking.booking_token}. Please confirm after receiving your vehicle.`,
      );
    } catch (notifyError) {
      console.error('Failed to notify customer about driver handover:', notifyError.message || notifyError);
    }

    return res.json({
      success: true,
      booking,
      message: 'Driver handover confirmed. Customer can now confirm receipt.',
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Customer confirms the vehicle was returned successfully.
exports.confirmReturnCompleted = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const booking = await Booking.findOne({ where: { booking_token: token } });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }

    const isOwner = Number(booking.user_id) === Number(userId);
    if (!isOwner && role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only the booking customer can confirm return completion'
      });
    }

    const returnStatus = (booking.return_status || '').toString().toLowerCase();
    if (returnStatus === 'completed' || booking.status === 'completed') {
      return res.json({
        success: true,
        booking,
        message: 'Return already marked as completed'
      });
    }

    if (returnStatus !== 'handover_confirmed') {
      return res.status(400).json({
        success: false,
        message: 'Driver must confirm handover before customer completion'
      });
    }

    booking.return_status = 'completed';
    booking.return_completed_at = new Date();
    booking.return_requested_at = null;
    booking.status = 'completed';
    booking.completed_at = new Date();
    await booking.save();

    let customerLabel = `Customer ${booking.user_id}`;
    try {
      const customer = await User.findOne({
        where: { id: booking.user_id },
        attributes: ['name']
      });
      if (customer && customer.name) {
        customerLabel = customer.name;
      }
    } catch (_) {}

    try {
      await notifySecurityReturnCompleted(booking, customerLabel);
    } catch (notifyError) {
      console.error(
        'Failed to notify security about return completion:',
        notifyError.message || notifyError
      );
    }

    return res.json({ success: true, booking });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Customer cancels a pending self-parking booking.
exports.cancelSelfParkingBooking = async (req, res) => {
  try {
    const { token } = req.params;
    const userId = req.user && req.user.id;
    const role = req.user && req.user.role;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const booking = await Booking.findOne({ where: { booking_token: token } });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }

    const isOwner = Number(booking.user_id) === Number(userId);
    if (!isOwner && role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'You can cancel only your own booking',
      });
    }

    const isSelfParking =
      Number(booking.driver_id || 0) === 0 &&
      booking.location_id != null &&
      booking.slot_number != null;
    if (!isSelfParking) {
      return res.status(400).json({
        success: false,
        message: 'This cancellation option is only for self parking bookings',
      });
    }

    if (booking.status === 'cancelled') {
      return res.json({
        success: true,
        message: 'Booking already cancelled',
        booking,
      });
    }

    if (booking.status === 'completed') {
      return res.status(400).json({
        success: false,
        message: 'Completed booking cannot be cancelled',
      });
    }

    if (booking.status !== 'pending') {
      return res.status(400).json({
        success: false,
        message: 'Only pending self parking bookings can be cancelled',
      });
    }

    const wasPaid =
      (booking.payment_status || '').toString().toLowerCase() === 'paid';
    const refundAmount = wasPaid
      ? Number(booking.payment_amount || 0)
      : 0;

    await sequelize.transaction(async (transaction) => {
      booking.status = 'cancelled';
      booking.cancelled_at = new Date();
      if (wasPaid) {
        booking.payment_status = 'refunded';
      }
      booking.return_requested_at = null;
      booking.return_status = null;
      booking.return_driver_id = null;
      booking.return_accepted_at = null;
      booking.return_completed_at = null;
      await booking.save({ transaction });

      const slot = await ParkingSlot.findOne({
        where: {
          location_id: booking.location_id,
          slot_number: booking.slot_number,
        },
        transaction,
        lock: transaction.LOCK.UPDATE,
      });

      let releasedSlot = false;
      if (slot && (slot.status === 'occupied' || slot.status === 'reserved')) {
        await ParkingSlot.update(
          { status: 'available' },
          { where: { id: slot.id }, transaction }
        );
        releasedSlot = true;
      }

      await SlotReservation.destroy({
        where: { booking_id: booking.id },
        transaction,
      });

      if (releasedSlot && booking.location_id != null) {
        const location = await ParkingLocation.findOne({
          where: { id: booking.location_id },
          transaction,
          lock: transaction.LOCK.UPDATE,
        });
        if (location) {
          const currentAvailable = Number(location.available_slots) || 0;
          const maxSlots = Number(location.total_slots) || currentAvailable;
          const nextAvailable = Math.min(maxSlots, currentAvailable + 1);
          await ParkingLocation.update(
            { available_slots: nextAvailable },
            { where: { id: location.id }, transaction }
          );
        }
      }
    });

    return res.json({
      success: true,
      message: wasPaid
        ? `Self parking booking cancelled. Refund of Rs ${refundAmount.toStringAsFixed(0)} completed.`
        : 'Self parking booking cancelled. Slot is now available.',
      refund_processed: wasPaid,
      refund_amount: wasPaid ? refundAmount : 0,
      booking,
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

// Update booking status and assignment.
// Driver accept should not mark parking as confirmed.
exports.updateBookingStatus = async (req, res) => {
    try {
      const { token } = req.params;
      const {
        status,
        driver_id,
        location_id,
        slot_number,
        decline_reason,
        decline_note,
      } = req.body;
      const userId = req.user && req.user.id;
      const role = req.user && req.user.role;
      if (!userId) {
        return res.status(401).json({ success: false, message: 'Unauthorized' });
      }

      const booking = await Booking.findOne({ where: { booking_token: token } });
      if (!booking) {
        return res.status(404).json({ success: false, message: 'Booking not found' });
      }

      let updated = false;
      const prevLocationId = booking.location_id;
      const prevSlotNumber = booking.slot_number;
      let declineNotification = null;

      if (booking.status === 'completed' || booking.status === 'cancelled') {
        return res.status(400).json({
          success: false,
          message: 'Cannot modify a completed or cancelled booking',
        });
      }

      if (status != null) {
        // Treat `accepted` as driver assignment for valet flow.
        // Keep status as `pending` until security confirms parked (slot -> occupied).
        if (status === 'accepted' || status === 'confirmed') {
          if (role !== 'driver' && role !== 'admin') {
            return res.status(403).json({
              success: false,
              message: 'Only drivers can accept a valet request',
            });
          }

          const acceptingDriverId =
            role === 'admin' ? (driver_id || userId) : userId;
          if (!acceptingDriverId) {
            return res.status(400).json({
              success: false,
              message: 'driver_id is required when accepting a booking',
            });
          }

          if (
            booking.driver_id &&
            Number(booking.driver_id) !== Number(acceptingDriverId)
          ) {
            return res.status(409).json({
              success: false,
              message: 'Booking already accepted by another driver',
            });
          }

          if (role !== 'admin' && !booking.driver_id) {
            const priority = await getPriorityContextForDriver(
              booking.id,
              'pickup',
              acceptingDriverId,
            );
            if (!priority.eligible_to_accept) {
              return res.status(403).json({
                success: false,
                message: 'Please wait for your priority turn to accept this booking',
              });
            }
          }

          booking.driver_id = acceptingDriverId;
          if (!booking.driver_accepted_at) {
            booking.driver_accepted_at = new Date();
          }
          if (booking.status !== 'confirmed') {
            booking.status = 'pending';
          }
          updated = true;
        } else if (status === 'declined') {
          if (role !== 'driver' && role !== 'admin') {
            return res.status(403).json({
              success: false,
              message: 'Only drivers can decline a valet request',
            });
          }

          const decliningDriverId =
            role === 'admin' ? (driver_id || userId) : userId;

          if (
            booking.driver_id &&
            Number(booking.driver_id) !== Number(decliningDriverId) &&
            role !== 'admin'
          ) {
            return res.status(403).json({
              success: false,
              message: 'Only the assigned driver can decline this booking',
            });
          }

          if (!booking.driver_id && role !== 'admin') {
            const priority = await getPriorityContextForDriver(
              booking.id,
              'pickup',
              decliningDriverId,
            );
            if (!priority.eligible_to_accept) {
              return res.status(403).json({
                success: false,
                message: 'Please wait for your priority turn to decline this booking',
              });
            }
          }

          await recordBookingDecline(booking.id, decliningDriverId, 'pickup', {
            declineReason: decline_reason,
            declineNote: decline_note,
          });
          declineNotification = {
            driverId: decliningDriverId,
            requestType: 'pickup',
            declineReason: decline_reason,
            declineNote: decline_note,
          };
          if (
            !booking.driver_id ||
            Number(booking.driver_id) === Number(decliningDriverId) ||
            role === 'admin'
          ) {
            booking.driver_id = null;
            booking.driver_accepted_at = null;
          }
          booking.status = 'pending';
          updated = true;
        } else {
          return res.status(400).json({ success: false, message: 'Invalid status' });
        }
      }

      if (location_id !== undefined) {
        if (!booking.driver_id) {
          return res.status(400).json({
            success: false,
            message: 'Driver must accept booking before assigning location',
          });
        }
        if (role !== 'admin' && Number(booking.driver_id) !== Number(userId)) {
          return res.status(403).json({
            success: false,
            message: 'Only the assigned driver can assign a parking location',
          });
        }
        booking.location_id = location_id;
        updated = true;
      }

      if (slot_number !== undefined) {
        if (!booking.driver_id) {
          return res.status(400).json({
            success: false,
            message: 'Driver must accept booking before assigning slot',
          });
        }
        if (role !== 'admin' && Number(booking.driver_id) !== Number(userId)) {
          return res.status(403).json({
            success: false,
            message: 'Only the assigned driver can assign a slot',
          });
        }
        booking.slot_number = slot_number;
        updated = true;
      }

      if (!updated) {
        return res.status(400).json({
          success: false,
          message: 'No valid fields to update',
        });
      }

      await booking.save();

      if (declineNotification) {
        try {
          await notifyAdminsForBookingDecline(
            booking,
            declineNotification.driverId,
            declineNotification.requestType,
            declineNotification.declineReason,
            declineNotification.declineNote,
          );
        } catch (notifyError) {
          console.error(
            'Failed to notify admins for booking decline:',
            notifyError.message || notifyError
          );
        }
      }

      const hasValetAssignment =
        booking.driver_id != null &&
        booking.location_id != null &&
        booking.slot_number != null;
      const assignmentChanged =
        (prevLocationId == null && booking.location_id != null) ||
        (prevSlotNumber == null && booking.slot_number != null) ||
        (prevLocationId != null && booking.location_id != prevLocationId) ||
        (prevSlotNumber != null && booking.slot_number != prevSlotNumber);

      if (hasValetAssignment && assignmentChanged) {
        try {
          await notifySecurityForValetAssignment(booking);
        } catch (notifyError) {
          console.error(
            'Failed to notify security for valet assignment:',
            notifyError.message || notifyError
          );
        }
      }

      return res.json({ success: true, booking });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  };

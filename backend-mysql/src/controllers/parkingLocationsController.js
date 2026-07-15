// Delete a parking location by id (admin only)
exports.deleteParkingLocation = async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await ParkingLocation.destroy({ where: { id } });
    if (deleted) {
      res.json({ success: true, message: 'Parking location deleted' });
    } else {
      res.status(404).json({ success: false, error: 'Parking location not found' });
    }
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};
const ParkingLocation = require('../models/parking_location');
const ParkingSlot = require('../models/parking_slot');
const sequelize = require('../config');
const { Op } = require('sequelize');

const attachAvailabilityCounts = async (locations) => {
  if (!locations || locations.length === 0) return [];

  const locationIds = locations.map((loc) => loc.id);
  const slotCounts = await ParkingSlot.findAll({
    attributes: [
      'location_id',
      [sequelize.fn('COUNT', sequelize.col('id')), 'total_count'],
      [
        sequelize.fn(
          'SUM',
          sequelize.literal("CASE WHEN status = 'available' THEN 1 ELSE 0 END")
        ),
        'available_count'
      ]
    ],
    where: { location_id: { [Op.in]: locationIds } },
    group: ['location_id']
  });

  const countsByLocation = new Map();
  slotCounts.forEach((row) => {
    const data = row.toJSON();
    const locId = data.location_id;
    const total = Number(data.total_count) || 0;
    const available = Number(data.available_count) || 0;
    countsByLocation.set(locId, { total, available });
  });

  return locations.map((loc) => {
    const json = loc.toJSON ? loc.toJSON() : { ...loc };
    const counts = countsByLocation.get(json.id);
    if (counts && counts.total >= 0) {
      return {
        ...json,
        available_slots: counts.available,
        total_slots: json.total_slots ?? counts.total
      };
    }
    return json;
  });
};

// Create a new parking location
exports.createParkingLocation = async (req, res) => {
  try {
    const {
      name,
      address,
      latitude,
      longitude,
      total_slots,
      available_slots
    } = req.body;

    const location = await ParkingLocation.create({
      name,
      address,
      latitude,
      longitude,
      total_slots,
      available_slots
    });

    res.status(201).json({ success: true, location });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get all parking locations
exports.getAllParkingLocations = async (req, res) => {
  try {
    const locations = await ParkingLocation.findAll();
    const enriched = await attachAvailabilityCounts(locations);
    res.json({ success: true, locations: enriched });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Get nearby parking locations (within radius)
exports.getNearbyParkingLocations = async (req, res) => {
  try {
    const { latitude, longitude, radiusKm = 5 } = req.query;

    if (!latitude || !longitude) {
      return res.status(400).json({ success: false, error: 'Latitude and longitude are required' });
    }

    const userLat = parseFloat(latitude);
    const userLng = parseFloat(longitude);

    const locations = await ParkingLocation.findAll();

    // Haversine formula to calculate distance
    const calculateDistance = (lat1, lon1, lat2, lon2) => {
      const R = 6371; // Earth's radius in km
      const dLat = (lat2 - lat1) * (Math.PI / 180);
      const dLon = (lon2 - lon1) * (Math.PI / 180);
      const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * (Math.PI / 180)) *
          Math.cos(lat2 * (Math.PI / 180)) *
          Math.sin(dLon / 2) *
          Math.sin(dLon / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      return R * c;
    };

    const withCounts = await attachAvailabilityCounts(locations);
    const nearby = withCounts
      .map((loc) => {
        const distance = calculateDistance(
          userLat,
          userLng,
          parseFloat(loc.latitude),
          parseFloat(loc.longitude)
        );
        return { ...loc, distance };
      })
      .filter((loc) => loc.distance <= radiusKm)
      .sort((a, b) => a.distance - b.distance);

    res.json({ success: true, locations: nearby, count: nearby.length });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

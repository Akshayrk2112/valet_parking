const express = require('express');
const router = express.Router();

const parkingLocationsController = require('../controllers/parkingLocationsController');
const parkingSlotsController = require('../controllers/parkingSlotsController');
const auth = require('../middleware/auth');
const adminOnly = require('../middleware/adminOnly');

// Example: GET /api/parking/test
router.get('/test', (req, res) => {
  res.json({ message: 'Parking route working' });
});

// Create a new parking location (admin only)
router.post('/locations', auth, adminOnly, parkingLocationsController.createParkingLocation);

// Get all parking locations
router.get('/locations', parkingLocationsController.getAllParkingLocations);

// Get nearby parking locations based on user location
router.get('/locations/nearby', parkingLocationsController.getNearbyParkingLocations);

// Delete a parking location (admin only)
router.delete('/locations/:id', auth, adminOnly, parkingLocationsController.deleteParkingLocation);

// ===== Parking Slots Endpoints =====

// Create slots for a location (admin only)
router.post('/slots', auth, adminOnly, parkingSlotsController.createSlots);

// Get all slots for a location
router.get('/slots/:location_id', parkingSlotsController.getSlotsByLocation);

// Update slot status
router.patch('/slots/:slot_id', auth, parkingSlotsController.updateSlotStatus);

// Get all slots (admin view)
router.get('/slots', parkingSlotsController.getAllSlots);

module.exports = router;

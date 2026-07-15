const express = require('express');
const router = express.Router();

const bookingsController = require('../controllers/bookingsController');

// Example: GET /api/bookings/test
router.get('/test', (req, res) => {
  res.json({ message: 'Bookings route working' });
});

const auth = require('../middleware/auth');
// Create a new booking (require authentication)
router.post('/', auth, bookingsController.createBooking);

// Get available bookings for drivers (auth required for eligibility)
router.get('/available', auth, bookingsController.getAvailableBookings);

// Get return requests available for drivers
router.get('/return/available', auth, bookingsController.getAvailableReturnRequests);

// Get all bookings
router.get('/', bookingsController.getAllBookings);

// Get user's current booking
router.get('/current', auth, bookingsController.getUserCurrentBooking);

// Get driver's current accepted/active booking
router.get('/driver/current', auth, bookingsController.getDriverCurrentBooking);

// Get payment estimate for vehicle return
router.get('/:token/return-estimate', auth, bookingsController.getReturnPaymentEstimate);

// Driver accepts or declines return request
router.post('/:token/accept-return', auth, bookingsController.acceptReturnRequest);
router.post('/:token/decline-return', auth, bookingsController.declineReturnRequest);
router.post('/:token/confirm-driver-handover', auth, bookingsController.confirmDriverReturnHandover);
router.post('/:token/confirm-return-completed', auth, bookingsController.confirmReturnCompleted);
router.post('/:token/cancel-self', auth, bookingsController.cancelSelfParkingBooking);

// Get booking by token
router.get('/:token', bookingsController.getBookingByToken);

// Customer requests vehicle return for a confirmed parking booking
router.post('/:token/request-return', auth, bookingsController.requestVehicleReturn);

// Update booking status (accept/decline)
router.patch('/:token', auth, bookingsController.updateBookingStatus);

module.exports = router;

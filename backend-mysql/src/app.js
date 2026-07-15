const express = require('express');
const dotenv = require('dotenv');
const authRoutes = require('./routes/auth');
const parkingRoutes = require('./routes/parking');
const bookingRoutes = require('./routes/bookings');
const driverRoutes = require('./routes/drivers');
const notificationRoutes = require('./routes/notifications');
const { errorHandler } = require('./middleware/errorHandler');

dotenv.config();

const app = express();
app.use(express.json());

// Root endpoint
app.get('/', (req, res) => {
	res.json({ message: 'Valet Parking API is running!' });
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/parking', parkingRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/drivers', driverRoutes);
app.use('/api/notifications', notificationRoutes);

// Error handler
app.use(errorHandler);

module.exports = app;

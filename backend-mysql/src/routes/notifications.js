const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const notificationsController = require('../controllers/notificationsController');

router.get('/mine', auth, notificationsController.getMyNotifications);
router.patch('/read-all', auth, notificationsController.markAllRead);

module.exports = router;

const Notification = require('../models/notification');

function parseLimit(value, fallback = 30) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(1, Math.min(100, Math.trunc(parsed)));
}

exports.getMyNotifications = async (req, res) => {
  try {
    const userId = req.user && req.user.id;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const unreadOnly = String(req.query.unreadOnly || '').toLowerCase() === 'true';
    const limit = parseLimit(req.query.limit, 30);
    const where = { user_id: userId };
    if (unreadOnly) {
      where.is_read = false;
    }

    const notifications = await Notification.findAll({
      where,
      order: [['created_at', 'DESC'], ['id', 'DESC']],
      limit
    });

    const unreadCount = await Notification.count({
      where: { user_id: userId, is_read: false }
    });

    return res.json({
      success: true,
      notifications,
      unread_count: unreadCount
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

exports.markAllRead = async (req, res) => {
  try {
    const userId = req.user && req.user.id;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    await Notification.update(
      { is_read: true },
      { where: { user_id: userId, is_read: false } }
    );

    return res.json({ success: true });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};

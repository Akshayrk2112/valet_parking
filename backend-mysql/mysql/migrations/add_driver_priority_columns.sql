ALTER TABLE bookings
  ADD COLUMN driver_accepted_at DATETIME NULL AFTER payment_time;

ALTER TABLE booking_declines
  ADD COLUMN request_type ENUM('pickup','return') NOT NULL DEFAULT 'pickup' AFTER driver_id;

ALTER TABLE booking_declines
  ADD COLUMN decline_reason VARCHAR(100) NULL AFTER request_type,
  ADD COLUMN decline_note TEXT NULL AFTER decline_reason;

ALTER TABLE booking_declines
  ADD COLUMN decline_reason VARCHAR(100) NULL AFTER request_type,
  ADD COLUMN decline_note TEXT NULL AFTER decline_reason;

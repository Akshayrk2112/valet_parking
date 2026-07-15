-- Migration: Add slot_no column to bookings table
-- Description: Add slot_no column to store parking slot information in bookings

ALTER TABLE bookings ADD COLUMN slot_no VARCHAR(20) AFTER location_id;

-- Optional: Add index on slot_no for faster queries
CREATE INDEX idx_bookings_slot_no ON bookings(slot_no);

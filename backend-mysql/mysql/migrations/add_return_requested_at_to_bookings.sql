-- Migration: Add return_requested_at column to bookings table
-- Description: Track customer return requests for self-parking retrieval.

ALTER TABLE bookings
ADD COLUMN return_requested_at DATETIME NULL AFTER payment_time;

CREATE INDEX idx_bookings_return_requested_at ON bookings(return_requested_at);

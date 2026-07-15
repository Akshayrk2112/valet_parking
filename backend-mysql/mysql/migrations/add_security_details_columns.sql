-- Migration: Add missing columns to security_details table
-- Description: Ensure schema matches SecurityDetails Sequelize model.

ALTER TABLE security_details
ADD COLUMN parking_location VARCHAR(255) NULL AFTER user_id,
ADD COLUMN status ENUM('active','inactive') NOT NULL DEFAULT 'active' AFTER parking_location,
ADD COLUMN phone VARCHAR(20) NULL AFTER status;

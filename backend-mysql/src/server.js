const sequelize = require('./config');
const app = require('./app');
const { startReservationExpiryJob } = require('./services/slotReservationExpiryService');
require('dotenv').config();

const PORT = process.env.PORT || 5000;

async function ensureBookingColumns() {
  // Keep runtime schema compatible across DB variants:
  // some databases use slot_no, others use slot_number.
  const [slotNoColumn] = await sequelize.query(
    "SHOW COLUMNS FROM bookings LIKE 'slot_no';"
  );
  if (!(Array.isArray(slotNoColumn) && slotNoColumn.length > 0)) {
    const [slotNumberColumn] = await sequelize.query(
      "SHOW COLUMNS FROM bookings LIKE 'slot_number';"
    );

    if (Array.isArray(slotNumberColumn) && slotNumberColumn.length > 0) {
      await sequelize.query(
        "ALTER TABLE bookings ADD COLUMN slot_no VARCHAR(20) NULL AFTER location_id;"
      );
      await sequelize.query(
        "UPDATE bookings SET slot_no = slot_number WHERE slot_no IS NULL;"
      );
      console.log("Applied migration: added bookings.slot_no from slot_number");
    } else {
      await sequelize.query(
        "ALTER TABLE bookings ADD COLUMN slot_no VARCHAR(20) NULL AFTER location_id;"
      );
      console.log("Applied migration: added bookings.slot_no");
    }
  }

  const [returnRequestedAtColumn] = await sequelize.query(
    "SHOW COLUMNS FROM bookings LIKE 'return_requested_at';"
  );
  if (!(Array.isArray(returnRequestedAtColumn) && returnRequestedAtColumn.length > 0)) {
    await sequelize.query(
      "ALTER TABLE bookings ADD COLUMN return_requested_at DATETIME NULL AFTER payment_time;"
    );
    console.log("Applied migration: added bookings.return_requested_at");
  }

  const bookingColumnsToEnsure = [
    {
      name: 'driver_accepted_at',
      sql: "ALTER TABLE bookings ADD COLUMN driver_accepted_at DATETIME NULL AFTER payment_time;",
    },
    {
      name: 'parked_confirmed_at',
      sql: "ALTER TABLE bookings ADD COLUMN parked_confirmed_at DATETIME NULL AFTER payment_time;",
    },
    {
      name: 'desired_return_location',
      sql: "ALTER TABLE bookings ADD COLUMN desired_return_location VARCHAR(255) NULL AFTER return_requested_at;",
    },
    {
      name: 'desired_return_latitude',
      sql: "ALTER TABLE bookings ADD COLUMN desired_return_latitude DECIMAL(10,8) NULL AFTER desired_return_location;",
    },
    {
      name: 'desired_return_longitude',
      sql: "ALTER TABLE bookings ADD COLUMN desired_return_longitude DECIMAL(11,8) NULL AFTER desired_return_latitude;",
    },
    {
      name: 'return_status',
      sql: "ALTER TABLE bookings ADD COLUMN return_status VARCHAR(20) NULL AFTER desired_return_longitude;",
    },
    {
      name: 'return_driver_id',
      sql: "ALTER TABLE bookings ADD COLUMN return_driver_id INT NULL AFTER return_status;",
    },
    {
      name: 'return_accepted_at',
      sql: "ALTER TABLE bookings ADD COLUMN return_accepted_at DATETIME NULL AFTER return_driver_id;",
    },
    {
      name: 'return_completed_at',
      sql: "ALTER TABLE bookings ADD COLUMN return_completed_at DATETIME NULL AFTER return_accepted_at;",
    },
  ];

  for (const col of bookingColumnsToEnsure) {
    const [column] = await sequelize.query(
      `SHOW COLUMNS FROM bookings LIKE '${col.name}';`
    );
    if (!(Array.isArray(column) && column.length > 0)) {
      await sequelize.query(col.sql);
      console.log(`Applied migration: added bookings.${col.name}`);
    }
  }
}

async function ensureBookingDeclineColumns() {
  const [declineTables] = await sequelize.query(
    "SHOW TABLES LIKE 'booking_declines';"
  );
  if (!(Array.isArray(declineTables) && declineTables.length > 0)) {
    return;
  }

  const declineColumnsToEnsure = [
    {
      name: 'request_type',
      sql: "ALTER TABLE booking_declines ADD COLUMN request_type ENUM('pickup','return') NOT NULL DEFAULT 'pickup' AFTER driver_id;",
    },
    {
      name: 'decline_reason',
      sql: "ALTER TABLE booking_declines ADD COLUMN decline_reason VARCHAR(100) NULL AFTER request_type;",
    },
    {
      name: 'decline_note',
      sql: "ALTER TABLE booking_declines ADD COLUMN decline_note TEXT NULL AFTER decline_reason;",
    },
  ];

  for (const col of declineColumnsToEnsure) {
    const [column] = await sequelize.query(
      `SHOW COLUMNS FROM booking_declines LIKE '${col.name}';`
    );
    if (!(Array.isArray(column) && column.length > 0)) {
      await sequelize.query(col.sql);
      console.log(`Applied migration: added booking_declines.${col.name}`);
    }
  }
}

async function ensureSecurityDetailsColumns() {
  const [parkingLocationColumn] = await sequelize.query(
    "SHOW COLUMNS FROM security_details LIKE 'parking_location';"
  );
  if (!(Array.isArray(parkingLocationColumn) && parkingLocationColumn.length > 0)) {
    await sequelize.query(
      "ALTER TABLE security_details ADD COLUMN parking_location VARCHAR(255) NULL AFTER user_id;"
    );
    console.log("Applied migration: added security_details.parking_location");
  }

  const [statusColumn] = await sequelize.query(
    "SHOW COLUMNS FROM security_details LIKE 'status';"
  );
  if (!(Array.isArray(statusColumn) && statusColumn.length > 0)) {
    await sequelize.query(
      "ALTER TABLE security_details ADD COLUMN status ENUM('active','inactive') NOT NULL DEFAULT 'active' AFTER parking_location;"
    );
    console.log("Applied migration: added security_details.status");
  }

  const [phoneColumn] = await sequelize.query(
    "SHOW COLUMNS FROM security_details LIKE 'phone';"
  );
  if (!(Array.isArray(phoneColumn) && phoneColumn.length > 0)) {
    await sequelize.query(
      "ALTER TABLE security_details ADD COLUMN phone VARCHAR(20) NULL AFTER status;"
    );
    console.log("Applied migration: added security_details.phone");
  }

  // Backfill parking_location from legacy parking_location_id when available.
  const [legacyParkingLocationIdColumn] = await sequelize.query(
    "SHOW COLUMNS FROM security_details LIKE 'parking_location_id';"
  );
  if (Array.isArray(legacyParkingLocationIdColumn) && legacyParkingLocationIdColumn.length > 0) {
    await sequelize.query(
      "UPDATE security_details sd JOIN parking_locations pl ON sd.parking_location_id = pl.id SET sd.parking_location = pl.name WHERE sd.parking_location IS NULL OR sd.parking_location = '';"
    );
  }
}

(async () => {
  try {
    await sequelize.authenticate();
    await ensureBookingColumns();
    await ensureBookingDeclineColumns();
    await ensureSecurityDetailsColumns();
    await sequelize.sync();
    startReservationExpiryJob();
    console.log('MySQL connected and models synced');
    app.listen(PORT, '0.0.0.0', () => console.log(`Server running on port ${PORT}`));
  } catch (err) {
    console.error('MySQL connection error:', err);
    process.exit(1);
  }
})();

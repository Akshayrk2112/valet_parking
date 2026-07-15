# Valet Parking Backend (Node.js + Express + MySQL)

This backend provides REST APIs for the valet parking app, using Node.js, Express, MySQL (with Sequelize), and JWT authentication.

## Features
- User registration & login
- Parking locations CRUD
- Booking management
- Driver/agent management
- JWT authentication

## Setup
1. Install dependencies: `npm install`
2. Copy `.env.example` to `.env` and set your MySQL credentials
3. Start server: `npm start` or `npm run dev`

## Folder Structure
- `/src`
  - `/models` (Sequelize models)
  - `/routes` (Express routers)
  - `/controllers` (Business logic)
  - `/middleware` (Auth, error handling)
  - `config.js` (Sequelize config)
  - `app.js` (Express app)
  - `server.js` (Entry point)
- `.env.example` (Environment config sample)

## API Endpoints
- `/api/auth` - Register/Login
- `/api/parking` - Parking locations
- `/api/bookings` - Bookings
- `/api/drivers` - Driver management

---
Replace this README as you build out the backend.
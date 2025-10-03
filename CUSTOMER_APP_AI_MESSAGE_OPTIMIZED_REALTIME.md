# SwiftDash — Message to Customer App AI: Optimized Realtime Migration

Hi Customer App AI team,

We performed a coordinated backend change to introduce an optimized realtime model for SwiftDash. This message explains what changed, why we did it, and what you need to do on the Customer App side to remain compatible and take advantage of the improvements.

## TL;DR

- Added lightweight, cost-aware realtime tables and policies:
  - `driver_current_status` — lightweight, always-up-to-date driver status
  - `driver_location_history` — stores *only critical* location events (pickups, deliveries, shifts, breaks)
  - `analytics_events` — batched analytics events for off-line processing
- Reworked RLS policies for stricter, granular access.
- Introduced new channel / event conventions for realtime (broadcast-only GPS channels + per-delivery and per-driver channels).
- Migration SQL updated to run safely inside Supabase SQL Editor (we removed `CONCURRENTLY` from index creation statements).

## What changed (high level)

1. Schema
   - New tables:
     - `driver_current_status` — one row per driver with current lat/lon, status, last_updated, battery_level, device/app info, and current_delivery_id.
     - `driver_location_history` — append-only records for important events like `pickup`, `delivery`, `shift_start`, `break_start`, etc.
     - `analytics_events` — queued/batched JSON events for processing.
   - `driver_profiles` now contains `ltfrb_picture_url` (we also ensured `profile_picture_url` and `vehicle_picture_url` exist).

2. RLS (Row-Level Security)
   - Drivers can only access their own status and location history rows (via `auth.uid()` checks).
   - Customers can access driver status and location history only when tied to their deliveries (queries check `deliveries.customer_id = auth.uid()`).
   - Ensure your queries run with an authenticated session (Supabase `auth` user) and the app uses `auth.uid()` as the identity of the calling user.

3. Realtime channels & conventions
   - Broadcast-only GPS channel (non-persistent):
     - Channel name: `driver-location-{deliveryId}` (for delivery-scoped live GPS)
     - The driver app broadcasts frequent location updates here; these are not stored by default.
     - Customer App should subscribe to the channel while a delivery is active to show live position.
   - Delivery channel (per-delivery): `delivery-{deliveryId}` — subscribe for delivery-level events and updates.
   - Driver deliveries channel (per-driver): `driver-deliveries-{driverId}` — subscribe to offers and assigned deliveries for that driver.

4. Persistence policy
   - Only critical location events are persisted to `driver_location_history`. Frequent GPS pings are broadcast only to save costs and minimize DB write load.
   - When critical events occur (e.g., pickup, delivery, shift start/end), the driver app triggers a store to `driver_location_history` (or the server does it via a secured endpoint).

5. Migration note
   - We removed `CREATE INDEX CONCURRENTLY` from the migration script so it can be run inside the Supabase SQL Editor (which runs statements in a transaction).
   - Indexes are created with `IF NOT EXISTS` to be safe for repeated runs.

## Actions required on Customer App side


1. Update realtime subscriptions
   - Subscribe to `driver-location-{deliveryId}` for live GPS updates while a delivery is active.
   - Subscribe to `delivery-{deliveryId}` for delivery lifecycle events.
   - Use `driver-deliveries-{driverId}` if you want driver-focused offer/assignment notifications.
   - Expected event payloads (example):
     - GPS broadcast: { "driver_id": "<uuid>", "lat": 12.345678, "lon": 98.765432, "speed_kmh": 32.1, "heading": 180, "battery_level": 87, "timestamp": "2025-10-03T...Z" }
     - Delivery update: { "delivery_id": "<uuid>", "status": "driver_assigned|package_collected|in_transit|delivered", "driver_id": "<uuid>", "timestamp": "..." }

3. Use authenticated sessions and expect RLS
   - Ensure every request/subscription is performed with an authenticated user so `auth.uid()` maps correctly.
   - Customers will only be able to read driver locations/status when they are the `customer_id` on the corresponding `deliveries` row.
   - Drivers will only be able to access their own `driver_current_status` and `driver_location_history` rows.

4. Displaying driver profile pictures / LTFRB
   - The driver profile now includes `ltfrb_picture_url`. If you show driver documents or profiles, include the new `ltfrb_picture_url` as appropriate (only visible per RLS rules).

5. Testing checklist
   - After migration, verify tables exist: `driver_current_status`, `driver_location_history`, `analytics_events`.
   - Create a test delivery and assign a test driver.
   - From the driver app, start broadcasting GPS to `driver-location-{deliveryId}` and verify Customer App receives the broadcasts.
   - Trigger a critical event (pickup/delivery) and verify a row appears in `driver_location_history` and that customers assigned to that delivery can `SELECT` it.
   - Verify driver status changes propagate (or are updated by the trigger on `deliveries`) to `driver_current_status`.

## Verifying access and troubleshooting

- Common failure: RLS blocks your queries
  - Symptoms: queries returning empty sets or permission errors.
  - Check: are you signed in as an authenticated user? Does `auth.uid()` match either `customer_id` on `deliveries` or the driver `id`? Use a debug endpoint to `SELECT auth.uid()` from a function (server-side) or check your Supabase client session.

- Common failure: No realtime events arriving
  - Check channel name correctness and that you're connected to Supabase Realtime with the correct token.
  - Ensure driver app is broadcasting to the agreed channel convention (`driver-location-{deliveryId}`).

- Migration failure due to index locks
  - If you need minimal locking in production, run index creation statements separately with `CREATE INDEX CONCURRENTLY` from a psql session (not in the SQL Editor transaction).

## Optional improvements / follow-ups

- If the Customer App needs historic, high-resolution GPS for analytics, request periodic batched upload endpoints rather than subscribing to every broadcast
- Consider caching the most recent `driver_current_status` row in your app for immediate UI (and refresh on events)
- Schedule cleanup functions (`cleanup_old_location_history()`, `cleanup_processed_analytics()`) via `pg_cron` or a daily job to keep tables lean


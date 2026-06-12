-- 003_indexes.sql

-- Geospatial indexes (GIST) — essential for ST_DWithin and ST_Distance queries
CREATE INDEX IF NOT EXISTS idx_trips_origin_point        ON trips USING GIST (origin_point);
CREATE INDEX IF NOT EXISTS idx_trips_destination_point   ON trips USING GIST (destination_point);
CREATE INDEX IF NOT EXISTS idx_trips_route_polyline      ON trips USING GIST (route_polyline);
CREATE INDEX IF NOT EXISTS idx_shipments_pickup_point    ON shipments USING GIST (pickup_point);
CREATE INDEX IF NOT EXISTS idx_shipments_dropoff_point   ON shipments USING GIST (dropoff_point);

-- Status-based filtering (used in nearly every query)
CREATE INDEX IF NOT EXISTS idx_trips_status              ON trips (status);
CREATE INDEX IF NOT EXISTS idx_bookings_status           ON bookings (status);
CREATE INDEX IF NOT EXISTS idx_bookings_trip_id          ON bookings (trip_id);
CREATE INDEX IF NOT EXISTS idx_bookings_hold_expires     ON bookings (hold_expires_at) WHERE status = 'capacity_held';

-- Composite index for capacity check queries
CREATE INDEX IF NOT EXISTS idx_bookings_trip_active      ON bookings (trip_id, status)
    WHERE status IN ('capacity_held', 'confirmed', 'picked_up');

-- Audit log entity lookup
CREATE INDEX IF NOT EXISTS idx_audit_entity              ON audit_log (entity_type, entity_id);

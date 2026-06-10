-- 002_core_tables.sql

-- ─────────────────────────────────────────────────
-- DRIVERS
-- ─────────────────────────────────────────────────
CREATE TABLE drivers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT NOT NULL,
    phone           TEXT NOT NULL UNIQUE,
    license_number  TEXT NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────
-- TRUCKS
-- ─────────────────────────────────────────────────
CREATE TABLE trucks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id           UUID NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,
    registration_number TEXT NOT NULL UNIQUE,
    max_weight_kg       NUMERIC(10,2) NOT NULL,   -- total payload capacity
    max_volume_m3       NUMERIC(10,2) NOT NULL,   -- cubic metres
    truck_type          TEXT NOT NULL,             -- e.g. 'mini', 'medium', 'large'
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────
-- TRIPS
-- A trip is one planned journey by a driver.
-- The route_polyline stores the driver's planned path
-- as a PostGIS LineString in WGS84 (SRID 4326).
-- ─────────────────────────────────────────────────
CREATE TABLE trips (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    truck_id        UUID NOT NULL REFERENCES trucks(id) ON DELETE RESTRICT,
    driver_id       UUID NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,

    origin_name     TEXT NOT NULL,
    origin_point    GEOGRAPHY(POINT, 4326) NOT NULL,    -- PostGIS point

    destination_name    TEXT NOT NULL,
    destination_point   GEOGRAPHY(POINT, 4326) NOT NULL,

    -- Full planned route as a LineString (from Google Maps / OSRM)
    route_polyline      GEOGRAPHY(LINESTRING, 4326) NOT NULL,

    -- Planned departure / arrival
    departure_at    TIMESTAMPTZ NOT NULL,
    arrival_at      TIMESTAMPTZ,

    -- Total route distance and duration (from Maps API at trip creation)
    base_distance_km    NUMERIC(10,2) NOT NULL,
    base_duration_min   NUMERIC(10,2) NOT NULL,

    -- Operational limits that define when we reject detours
    max_detour_km       NUMERIC(10,2) NOT NULL DEFAULT 30.0,
    max_detour_min      NUMERIC(10,2) NOT NULL DEFAULT 30.0,

    status          TEXT NOT NULL DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled','in_progress','completed','cancelled')),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────
-- SHIPMENTS
-- A shipment request from a customer.
-- ─────────────────────────────────────────────────
CREATE TABLE shipments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id     UUID NOT NULL,              -- FK to auth/customers table (Niranjan's domain)

    pickup_name     TEXT NOT NULL,
    pickup_point    GEOGRAPHY(POINT, 4326) NOT NULL,

    dropoff_name    TEXT NOT NULL,
    dropoff_point   GEOGRAPHY(POINT, 4326) NOT NULL,

    -- Cargo specification
    weight_kg       NUMERIC(10,2) NOT NULL,
    volume_m3       NUMERIC(10,2) NOT NULL,
    goods_type      TEXT NOT NULL,             -- 'general', 'fragile', 'perishable', 'hazardous'
    declared_value  NUMERIC(12,2) NOT NULL DEFAULT 0,

    -- Lifecycle
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','quoted','booked','in_transit','delivered','cancelled')),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────
-- BOOKINGS
-- A confirmed match between a trip and a shipment.
-- This is the central transactional table.
-- ─────────────────────────────────────────────────
CREATE TABLE bookings (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE RESTRICT,
    shipment_id     UUID NOT NULL REFERENCES shipments(id) ON DELETE RESTRICT,

    -- Pricing snapshot at time of booking (denormalized for auditability)
    price_amount    NUMERIC(12,2) NOT NULL,
    price_breakdown JSONB NOT NULL DEFAULT '{}',    -- detailed breakdown for display

    -- Route deviation this booking adds to the trip
    detour_distance_km  NUMERIC(10,2) NOT NULL DEFAULT 0,
    detour_duration_min NUMERIC(10,2) NOT NULL DEFAULT 0,

    -- Booking lifecycle
    status          TEXT NOT NULL DEFAULT 'pending_payment'
                        CHECK (status IN (
                            'capacity_held',   -- temporary hold during booking flow
                            'pending_payment',
                            'confirmed',
                            'picked_up',
                            'delivered',
                            'cancelled',
                            'expired'
                        )),

    -- Hold expiry: if payment not completed, hold auto-releases
    hold_expires_at TIMESTAMPTZ,

    -- Optimistic concurrency version for capacity updates
    version         INTEGER NOT NULL DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (trip_id, shipment_id)
);

-- ─────────────────────────────────────────────────
-- CAPACITY RESERVATIONS
-- Tracks current used capacity per trip, derived from
-- confirmed/held bookings. Maintained as a denormalized
-- summary for fast reads and advisory-lock target.
-- ─────────────────────────────────────────────────
CREATE TABLE trip_capacity (
    trip_id             UUID PRIMARY KEY REFERENCES trips(id) ON DELETE CASCADE,
    used_weight_kg      NUMERIC(10,2) NOT NULL DEFAULT 0,
    used_volume_m3      NUMERIC(10,2) NOT NULL DEFAULT 0,
    -- version for optimistic concurrency
    version             INTEGER NOT NULL DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────
-- PRICING PARAMETERS
-- Configurable pricing knobs stored in DB so they
-- can be updated without code deployments.
-- ─────────────────────────────────────────────────
CREATE TABLE pricing_parameters (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Scope: 'global' or city-specific
    scope                   TEXT NOT NULL DEFAULT 'global',
    city                    TEXT,

    -- Base rates
    base_rate_per_km        NUMERIC(10,4) NOT NULL,  -- ₹ per km of shipment distance
    rate_per_kg             NUMERIC(10,4) NOT NULL,  -- ₹ per kg
    rate_per_m3             NUMERIC(10,4) NOT NULL,  -- ₹ per m³

    -- Goods type multipliers (stored as JSONB)
    -- e.g. {"general": 1.0, "fragile": 1.4, "perishable": 1.6, "hazardous": 2.0}
    goods_type_multipliers  JSONB NOT NULL DEFAULT '{"general":1.0,"fragile":1.4,"perishable":1.6,"hazardous":2.0}',

    -- Detour surcharge
    detour_surcharge_per_km NUMERIC(10,4) NOT NULL DEFAULT 12.0,

    -- Utilization-based demand pricing
    -- When truck utilization > threshold, apply surge multiplier
    utilization_surge_threshold NUMERIC(5,2) NOT NULL DEFAULT 0.75,  -- 75%
    utilization_surge_multiplier NUMERIC(5,2) NOT NULL DEFAULT 1.25,

    -- Driver profitability floor
    min_driver_rate_per_km  NUMERIC(10,4) NOT NULL DEFAULT 15.0,    -- ₹/km after all costs
    platform_fee_pct        NUMERIC(5,2) NOT NULL DEFAULT 0.10,     -- 10%

    -- Declared value insurance
    declared_value_pct      NUMERIC(5,4) NOT NULL DEFAULT 0.005,    -- 0.5% of declared value

    -- Validity
    effective_from          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_until         TIMESTAMPTZ,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────
-- AUDIT LOG
-- Append-only log for all booking state transitions
-- and capacity changes. Useful for debugging and disputes.
-- ─────────────────────────────────────────────────
CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    entity_type TEXT NOT NULL,          -- 'booking', 'trip_capacity', etc.
    entity_id   UUID NOT NULL,
    action      TEXT NOT NULL,          -- 'capacity_held', 'confirmed', 'released', etc.
    payload     JSONB NOT NULL DEFAULT '{}',
    actor_id    UUID,                   -- agent system user UUID
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

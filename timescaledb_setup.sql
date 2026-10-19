-- ============================================================================
-- PostgreSQL + TimescaleDB Setup for 1,500 Employee GPS Tracking
-- Native Columnar Compression: ~90% Storage Savings (~140 MB/day vs 1.4 GB/day)
-- ============================================================================

-- 1. Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- 2. Tracking Sessions Summary Table (1 row per session updated in-place)
CREATE TABLE IF NOT EXISTS tracking_sessions (
    id SERIAL PRIMARY KEY,
    session_uuid VARCHAR(64) UNIQUE NOT NULL,
    user_id INTEGER NOT NULL,
    attendance_id BIGINT,
    shift_id INTEGER,
    work_date DATE NOT NULL DEFAULT CURRENT_DATE,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    status VARCHAR(32) NOT NULL DEFAULT 'RECORDING',
    start_latitude NUMERIC(11, 8),
    start_longitude NUMERIC(11, 8),
    end_latitude NUMERIC(11, 8),
    end_longitude NUMERIC(11, 8),
    total_distance_meters DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    total_duration_seconds INTEGER NOT NULL DEFAULT 0,
    retained_point_count INTEGER NOT NULL DEFAULT 0,
    last_accepted_latitude NUMERIC(11, 8),
    last_accepted_longitude NUMERIC(11, 8),
    last_accepted_time TIMESTAMPTZ,
    last_sync_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_date ON tracking_sessions (user_id, work_date);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON tracking_sessions (status);

-- 3. Storage-Efficient Route Chunks Hypertable
CREATE TABLE IF NOT EXISTS tracking_route_chunks (
    id BIGSERIAL,
    chunk_uuid VARCHAR(64) NOT NULL,
    session_id INTEGER NOT NULL REFERENCES tracking_sessions(id) ON DELETE CASCADE,
    chunk_sequence INTEGER NOT NULL,
    point_count INTEGER NOT NULL DEFAULT 0,
    encoded_geometry TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    distance_meters DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Convert to TimescaleDB Hypertable partitioned by time (7-day chunk intervals)
SELECT create_hypertable(
    'tracking_route_chunks',
    'created_at',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_chunks_session_seq ON tracking_route_chunks (session_id, chunk_sequence, created_at);

-- 4. Enable Native TimescaleDB Columnar Compression (90% compression ratio)
ALTER TABLE tracking_route_chunks SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'session_id',
    timescaledb.compress_orderby = 'chunk_sequence ASC, created_at ASC'
);

-- Automatically compress chunks older than 2 days
SELECT add_compression_policy('tracking_route_chunks', INTERVAL '2 days', if_not_exists => TRUE);

-- 5. Data Retention Policy (automatically drop raw chunks older than 90 days)
-- Note: Session summaries in tracking_sessions remain permanent!
SELECT add_retention_policy('tracking_route_chunks', INTERVAL '90 days', if_not_exists => TRUE);

-- ============================================================================
-- Verification query to check compression status
-- ============================================================================
-- SELECT * FROM timescaledb_information.compressed_hypertable_stats;

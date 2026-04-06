-- =============================================================================
-- Data Warehouse Schema (PostgreSQL)
-- Database: datawarehouse
-- Purpose:  Store CDC events from testdb.users with operation metadata
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table: dw_users
-- Mirrors the source MySQL users table plus CDC metadata columns
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw_users (
    -- Source columns (mirroring MySQL users table)
    id          INTEGER       NOT NULL,
    name        VARCHAR(100),
    email       VARCHAR(150),
    created_at  TIMESTAMP,
    updated_at  TIMESTAMP,

    -- CDC metadata columns
    cdc_operation   CHAR(1)    NOT NULL,   -- 'c' = create, 'u' = update, 'd' = delete
    cdc_timestamp   BIGINT,                -- Debezium ts_ms: Unix epoch in milliseconds
    cdc_loaded_at   TIMESTAMP  NOT NULL DEFAULT NOW(),  -- When NiFi inserted this record

    -- Surrogate key for the warehouse row (auto-increment)
    dw_id       BIGSERIAL PRIMARY KEY
);

-- Index for lookups by source PK
CREATE INDEX IF NOT EXISTS idx_dw_users_id         ON dw_users (id);
-- Index for filtering by operation type
CREATE INDEX IF NOT EXISTS idx_dw_users_cdc_op     ON dw_users (cdc_operation);
-- Index for time-range queries
CREATE INDEX IF NOT EXISTS idx_dw_users_cdc_ts     ON dw_users (cdc_timestamp);

-- -----------------------------------------------------------------------------
-- View: dw_users_latest
-- Shows only the most recent state of each user (useful for analytics queries)
-- Shows deletes as well (filter WHERE cdc_operation != 'd' to exclude them)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dw_users_latest AS
SELECT DISTINCT ON (id)
    id,
    name,
    email,
    created_at,
    updated_at,
    cdc_operation,
    cdc_timestamp,
    cdc_loaded_at
FROM dw_users
ORDER BY id, cdc_timestamp DESC, dw_id DESC;

-- -----------------------------------------------------------------------------
-- View: dw_users_active
-- Shows only currently active (non-deleted) users latest state
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dw_users_active AS
SELECT *
FROM dw_users_latest
WHERE cdc_operation != 'd';

-- Verification
SELECT 'Data Warehouse schema ready.' AS status;

-- =============================================================================
-- MySQL Initialization Script
-- Database: testdb
-- Purpose:  Create source table and grant Debezium replication privileges
-- =============================================================================

-- Use the testdb database (created automatically by MYSQL_DATABASE env var)
USE testdb;

-- -----------------------------------------------------------------------------
-- Table: users
-- This is the source table monitored by Debezium CDC
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id         INT          NOT NULL AUTO_INCREMENT,
    name       VARCHAR(100) NOT NULL,
    email      VARCHAR(150) NOT NULL UNIQUE,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Grant Debezium the privileges it needs:
--   SELECT       → read current table state (snapshot phase)
--   RELOAD       → flush tables to get consistent snapshot
--   SHOW DATABASES → list databases
--   REPLICATION SLAVE / CLIENT → read binlog events
-- -----------------------------------------------------------------------------
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
    ON *.* TO 'cdc_user'@'%';

FLUSH PRIVILEGES;

-- -----------------------------------------------------------------------------
-- Seed data: initial rows to verify the snapshot on startup
-- -----------------------------------------------------------------------------
INSERT INTO users (name, email) VALUES
    ('Alice Johnson',  'alice@example.com'),
    ('Bob Smith',      'bob@example.com'),
    ('Carol Williams', 'carol@example.com');

-- Show initial state
SELECT 'Initial users loaded:' AS log_message;
SELECT * FROM users;

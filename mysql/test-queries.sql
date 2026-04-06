-- =============================================================================
-- MySQL Test Queries
-- Purpose: Trigger INSERT, UPDATE, DELETE events observed via Debezium/Kafka
-- Usage:   Run these after the pipeline is fully started
-- =============================================================================

USE testdb;

-- =============================================================================
-- 1. INSERT — generates Debezium event with op = "c" (create)
-- =============================================================================
INSERT INTO users (name, email)
VALUES ('Dave Brown', 'dave@example.com');

INSERT INTO users (name, email)
VALUES ('Eve Davis', 'eve@example.com');

-- Verify
SELECT 'After INSERTs:' AS status;
SELECT * FROM users;

-- =============================================================================
-- 2. UPDATE — generates Debezium event with op = "u" (update)
--    Note: Debezium captures both "before" and "after" states of the row
-- =============================================================================
UPDATE users
SET    name = 'Alice Johnson-Updated', email = 'alice.updated@example.com'
WHERE  id = 1;

UPDATE users
SET    name = 'Bob Smith Jr'
WHERE  email = 'bob@example.com';

-- Verify
SELECT 'After UPDATEs:' AS status;
SELECT * FROM users;

-- =============================================================================
-- 3. DELETE — generates Debezium event with op = "d" (delete)
-- =============================================================================
DELETE FROM users
WHERE  email = 'carol@example.com';

-- Verify
SELECT 'After DELETE:' AS status;
SELECT * FROM users;

-- =============================================================================
-- 4. Bulk Insert — useful for load/performance observation
-- =============================================================================
INSERT INTO users (name, email)
VALUES
    ('Frank Miller',   'frank@example.com'),
    ('Grace Lee',      'grace@example.com'),
    ('Henry Wilson',   'henry@example.com');

SELECT 'After bulk insert:' AS status;
SELECT * FROM users;

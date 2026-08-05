-- ============================================================
-- 03: CLEAN TABLE CREATION & TRANSFORMATION
-- Builds transactions_clean from staging_transactions, applying
-- every decision documented in the data quality audit.
-- ============================================================

USE dirty_transactions_project;

-- ============================================================
-- Relax strict mode for this session only.
-- Needed because a small number of rows contain impossible
-- calendar dates (e.g. month 13) which would otherwise hard-fail
-- the insert. This converts them safely to NULL instead of
-- crashing the entire batch.
-- ============================================================
SET sql_mode = (SELECT REPLACE(@@sql_mode, 'STRICT_TRANS_TABLES', ''));

-- ============================================================
-- CLEAN TABLE
-- Notes on design decisions:
--   - row_id is a surrogate AUTO_INCREMENT primary key, NOT
--     transaction_id. The audit found transaction_id is not
--     reliably unique in the source data (some IDs are reused
--     for different transactions), so it cannot safely be a key.
--   - quantity_was_negative / price_was_negative preserve the
--     original sign as a flag before the value is converted to
--     ABS(), so no information is silently discarded.
-- ============================================================
DROP TABLE IF EXISTS transactions_clean;

CREATE TABLE transactions_clean (
    row_id                 INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id         VARCHAR(50),
    transaction_date       DATE,
    customer_id            VARCHAR(50),
    product_name           VARCHAR(150),
    quantity                INT,
    quantity_was_negative   TINYINT DEFAULT 0,
    price                    DECIMAL(10,2),
    price_was_negative      TINYINT DEFAULT 0,
    payment_method           VARCHAR(50),
    transaction_status       VARCHAR(50)
);

-- ============================================================
-- CLEAN + LOAD
-- Cleaning rules applied, matching the audit table in the README:
--   transaction_id      -> surrogate 'GEN-' ID assigned if missing/blank
--   transaction_date    -> parsed from YYYY-MM-DD; anything else -> NULL
--   quantity / price     -> ABS() applied; original sign flagged
--   payment_method       -> normalized to Cash / Credit Card / PayPal
--   transaction_status   -> normalized to Completed / Failed / Pending /
--                            Unknown (blank -> Unknown, not dropped)
--   duplicates            -> exact duplicate rows removed via DISTINCT
--                            in the source subquery
-- ============================================================
INSERT INTO transactions_clean
    (transaction_id, transaction_date, customer_id, product_name,
     quantity, quantity_was_negative, price, price_was_negative,
     payment_method, transaction_status)
SELECT
    CASE
        WHEN transaction_id IS NULL OR TRIM(transaction_id) = ''
            THEN CONCAT('GEN-', ROW_NUMBER() OVER (ORDER BY transaction_date, customer_id, product_name))
        ELSE TRIM(transaction_id)
    END,
    CASE
        WHEN transaction_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(transaction_date, '%Y-%m-%d')
        ELSE NULL
    END,
    TRIM(customer_id),
    TRIM(product_name),
    ABS(CAST(CAST(NULLIF(TRIM(quantity), '') AS DECIMAL(10,2)) AS SIGNED)),
    CASE WHEN CAST(CAST(NULLIF(TRIM(quantity), '') AS DECIMAL(10,2)) AS SIGNED) < 0 THEN 1 ELSE 0 END,
    ABS(CAST(NULLIF(REGEXP_REPLACE(TRIM(price), '[^0-9.-]', ''), '') AS DECIMAL(10,2))),
    CASE WHEN CAST(NULLIF(REGEXP_REPLACE(TRIM(price), '[^0-9.-]', ''), '') AS DECIMAL(10,2)) < 0 THEN 1 ELSE 0 END,
    CASE
        WHEN LOWER(REPLACE(TRIM(payment_method), ' ', '')) = 'cash' THEN 'Cash'
        WHEN LOWER(REPLACE(TRIM(payment_method), ' ', '')) = 'creditcard' THEN 'Credit Card'
        WHEN LOWER(REPLACE(TRIM(payment_method), ' ', '')) = 'paypal' THEN 'PayPal'
        ELSE 'Other/Unmapped'
    END,
    CASE
        WHEN TRIM(transaction_status) = '' OR transaction_status IS NULL THEN 'Unknown'
        WHEN LOWER(TRIM(transaction_status)) IN ('complete','completed') THEN 'Completed'
        WHEN LOWER(TRIM(transaction_status)) = 'failed' THEN 'Failed'
        WHEN LOWER(TRIM(transaction_status)) = 'pending' THEN 'Pending'
        ELSE 'Other/Unmapped'
    END
FROM (
    SELECT DISTINCT transaction_id, transaction_date, customer_id, product_name,
           quantity, price, payment_method, transaction_status
    FROM staging_transactions
) AS deduped_staging;

-- ============================================================
-- VERIFICATION
-- ============================================================
SELECT COUNT(*) FROM transactions_clean;

SELECT quantity_was_negative, COUNT(*) FROM transactions_clean GROUP BY quantity_was_negative;
SELECT price_was_negative, COUNT(*) FROM transactions_clean GROUP BY price_was_negative;
SELECT COUNT(*) AS still_missing_dates FROM transactions_clean WHERE transaction_date IS NULL;
SELECT COUNT(*) AS still_missing_price FROM transactions_clean WHERE price IS NULL;

-- ============================================================
-- SCORECARD: raw vs. clean, for the README
-- ============================================================
SELECT
    (SELECT COUNT(*) FROM staging_transactions) AS raw_row_count,
    (SELECT COUNT(*) FROM transactions_clean)   AS clean_row_count,
    (SELECT COUNT(*) FROM staging_transactions) - (SELECT COUNT(*) FROM transactions_clean) AS rows_removed,
    ROUND(((SELECT COUNT(*) FROM staging_transactions) - (SELECT COUNT(*) FROM transactions_clean))
          / (SELECT COUNT(*) FROM staging_transactions) * 100, 2) AS pct_rows_removed;

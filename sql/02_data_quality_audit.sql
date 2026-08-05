-- ============================================================
-- 02: DATA QUALITY AUDIT
-- Run every query below BEFORE cleaning. Log each result into
-- the audit table in the README (issue -> rows affected -> %
-- of data -> decision -> rationale).
-- ============================================================

USE dirty_transactions_project;

-- ============================================================
-- 2A: Total row count
-- ============================================================
SELECT COUNT(*) AS total_rows FROM staging_transactions;

-- ============================================================
-- 2B: Missing values per column
-- ============================================================
SELECT
    SUM(transaction_id IS NULL OR transaction_id = '')       AS missing_transaction_id,
    SUM(transaction_date IS NULL OR transaction_date = '')   AS missing_date,
    SUM(customer_id IS NULL OR customer_id = '')             AS missing_customer_id,
    SUM(product_name IS NULL OR product_name = '')           AS missing_product,
    SUM(quantity IS NULL OR quantity = '')                   AS missing_quantity,
    SUM(price IS NULL OR price = '')                         AS missing_price,
    SUM(payment_method IS NULL OR payment_method = '')       AS missing_payment_method,
    SUM(transaction_status IS NULL OR transaction_status = '') AS missing_status
FROM staging_transactions;

-- ============================================================
-- 2C: Duplicate transaction_id (raw count of any repeats)
-- ============================================================
SELECT transaction_id, COUNT(*) AS occurrences
FROM staging_transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- ============================================================
-- 2D: Distinguish TRUE duplicates from reused/corrupted IDs
-- distinct_versions = 1  -> exact duplicate, safe to drop extras
-- distinct_versions > 1  -> same ID reused for different data,
--                            a real data integrity issue
-- ============================================================
SELECT
    transaction_id,
    COUNT(DISTINCT CONCAT(transaction_date, customer_id, product_name,
          quantity, price, payment_method, transaction_status)) AS distinct_versions,
    COUNT(*) AS total_occurrences
FROM staging_transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY distinct_versions DESC;

-- ============================================================
-- 2E: Inconsistent casing/spacing in categorical columns
-- Reveals variants like 'PayPal' / 'pay pal' / 'PayPal ' being
-- treated as different categories
-- ============================================================
SELECT DISTINCT payment_method, COUNT(*) AS row_count
FROM staging_transactions
GROUP BY payment_method
ORDER BY payment_method;

SELECT DISTINCT transaction_status, COUNT(*) AS row_count
FROM staging_transactions
GROUP BY transaction_status
ORDER BY transaction_status;

-- ============================================================
-- 2F: Non-numeric / malformed quantity and price values
-- ============================================================
SELECT quantity, COUNT(*) AS row_count
FROM staging_transactions
WHERE quantity NOT REGEXP '^-?[0-9]+(\.[0-9]+)?$'
GROUP BY quantity
ORDER BY row_count DESC;

SELECT price, COUNT(*) AS row_count
FROM staging_transactions
WHERE price NOT REGEXP '^-?[0-9]+(\.[0-9]+)?$'
GROUP BY price
ORDER BY row_count DESC
LIMIT 30;

-- ============================================================
-- 2G: Negative quantity / price — quantify and check correlation
-- with transaction_status (tests whether it looks like genuine
-- returns vs. a systemic sign-flip data bug)
-- ============================================================
SELECT
    SUM(CAST(CAST(quantity AS DECIMAL(10,2)) AS SIGNED) < 0) AS negative_quantity_rows,
    SUM(CAST(CAST(quantity AS DECIMAL(10,2)) AS SIGNED) = 0) AS zero_quantity_rows,
    COUNT(*) AS total_rows
FROM staging_transactions
WHERE quantity REGEXP '^-?[0-9]+(\.[0-9]+)?$';

SELECT
    transaction_status,
    COUNT(*) AS negative_qty_count
FROM staging_transactions
WHERE CAST(CAST(quantity AS DECIMAL(10,2)) AS SIGNED) < 0
GROUP BY transaction_status;

-- Overlap check: do negative quantity and negative price occur on
-- the same rows (one shared cause) or independently (two separate issues)?
SELECT COUNT(*) AS both_negative
FROM staging_transactions
WHERE CAST(CAST(NULLIF(TRIM(quantity), '') AS DECIMAL(10,2)) AS SIGNED) < 0
  AND REGEXP_REPLACE(TRIM(price), '[^0-9.-]', '') REGEXP '^-';

-- ============================================================
-- 2H: Date format inspection
-- Pulls distinct raw date strings so every format variant is visible
-- ============================================================
SELECT DISTINCT transaction_date
FROM staging_transactions
LIMIT 20;

-- Confirms what % of dates match the expected YYYY-MM-DD pattern
SELECT COUNT(*) AS matching_format
FROM staging_transactions
WHERE transaction_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';

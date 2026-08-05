-- ============================================================
-- 04: BUSINESS ANALYSIS
-- Run against transactions_clean. These queries produce the
-- metrics used in the README findings and the Power BI dashboard.
-- ============================================================

USE dirty_transactions_project;

-- ============================================================
-- 4A: Transaction status breakdown
-- ============================================================
SELECT
    transaction_status,
    COUNT(*) AS total,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM transactions_clean) * 100, 2) AS pct_of_total
FROM transactions_clean
GROUP BY transaction_status
ORDER BY total DESC;

-- ============================================================
-- 4B: Failure rate by payment method
-- Tests whether failures are concentrated in one payment channel
-- or systemic across all of them
-- ============================================================
SELECT
    payment_method,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) AS failed_count,
    ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS failure_rate_pct
FROM transactions_clean
GROUP BY payment_method
ORDER BY failure_rate_pct DESC;

-- ============================================================
-- 4C: Revenue impact by status
-- Only includes rows with a valid (non-NULL) price, per the
-- audit decision not to impute blank prices
-- ============================================================
SELECT
    transaction_status,
    COUNT(*) AS transaction_count,
    SUM(quantity * price) AS total_value
FROM transactions_clean
WHERE price IS NOT NULL
GROUP BY transaction_status
ORDER BY total_value DESC;

-- Combined confirmed vs. unresolved revenue summary
SELECT
    SUM(CASE WHEN transaction_status = 'Completed' THEN quantity * price ELSE 0 END) AS confirmed_revenue,
    SUM(CASE WHEN transaction_status <> 'Completed' THEN quantity * price ELSE 0 END) AS unresolved_revenue,
    SUM(quantity * price) AS total_transaction_value
FROM transactions_clean
WHERE price IS NOT NULL;

-- ============================================================
-- 4D: Monthly trend (valid dates only — ~68% of dates were
-- missing/invalid per the audit, so this reflects a partial
-- population, not the full dataset)
-- ============================================================
SELECT
    DATE_FORMAT(transaction_date, '%Y-%m') AS month,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) AS failed_transactions,
    ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS failure_rate_pct
FROM transactions_clean
WHERE transaction_date IS NOT NULL
GROUP BY month
ORDER BY month;

-- ============================================================
-- 4E: Recoverable revenue estimate
-- Models the dollar impact of recovering a percentage of
-- currently Failed transactions (used in the dashboard's
-- "Recoverable Revenue" card, default scenario: 10%)
-- ============================================================
SELECT
    SUM(quantity * price) AS failed_transaction_value,
    ROUND(SUM(quantity * price) * 0.10, 2) AS recoverable_at_10_pct
FROM transactions_clean
WHERE transaction_status = 'Failed'
  AND price IS NOT NULL;

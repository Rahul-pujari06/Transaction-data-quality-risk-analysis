-- ============================================================
-- 01: DATABASE & STAGING TABLE SETUP
-- Dataset: "Dirty Financial Transactions Dataset" (Kaggle)
-- ============================================================

CREATE DATABASE IF NOT EXISTS dirty_transactions_project;
USE dirty_transactions_project;

-- ============================================================
-- STAGING TABLE
-- Every column is TEXT/VARCHAR by design. Raw source data is
-- messy (currency symbols, inconsistent casing, blank values,
-- mixed formats), so nothing is typed/constrained at this stage.
-- Cleaning and type-casting happens later, in script 03.
-- ============================================================
DROP TABLE IF EXISTS staging_transactions;

CREATE TABLE staging_transactions (
    transaction_id      VARCHAR(50),
    transaction_date    VARCHAR(50),
    customer_id         VARCHAR(50),
    product_name        VARCHAR(150),
    quantity            VARCHAR(20),
    price                VARCHAR(20),
    payment_method       VARCHAR(50),
    transaction_status   VARCHAR(50)
);

-- ============================================================
-- LOAD THE RAW CSV
-- Recommended: MySQL Workbench > right-click staging_transactions
-- > Table Data Import Wizard > select the source CSV.
-- Map columns as: Transaction_ID -> transaction_id,
-- Transaction_date -> transaction_date, Coustmer_ID -> customer_id,
-- Product name -> product_name, quantity -> quantity, price -> price,
-- payment method -> payment_method, transaction status -> transaction_status
-- ============================================================

-- ============================================================
-- VERIFY THE LOAD
-- ============================================================
SELECT COUNT(*) AS raw_row_count FROM staging_transactions;

SELECT * FROM staging_transactions LIMIT 10;

-- ============================================================
-- SAFETY NET: dedupe staging in case of an accidental double import
-- (only run this if raw_row_count above looks roughly double what
-- you expect from the source CSV)
-- ============================================================
-- CREATE TABLE staging_transactions_deduped AS
-- SELECT DISTINCT * FROM staging_transactions;
--
-- DROP TABLE staging_transactions;
-- RENAME TABLE staging_transactions_deduped TO staging_transactions;

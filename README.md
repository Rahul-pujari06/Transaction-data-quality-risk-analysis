# Transaction Data Quality & Payment Risk Analysis

## Dashboard Preview

![Executive Summary](dashboard/screenshots/page1_executive_summary.png)
![Payment Method Risk](dashboard/screenshots/page2_payment_method_risk.png)
![Revenue Impact](dashboard/screenshots/page3_revenue_impact.png)

## Business Problem

A financial transactions dataset was provided in a raw, uncleaned state, with no
reliable indicator of which records could be trusted for reporting. Before any
business question can be answered, the data itself needs to be audited, cleaned,
and validated. This project asks two questions:

1. **How reliable is this dataset, and what specifically is wrong with it?**
2. **Once cleaned, what does the data say about payment failure risk and revenue
   exposure — and is that risk concentrated anywhere actionable?**

## Dataset

- Source: "Dirty Financial Transactions Dataset" (Kaggle)
- Raw columns: `Transaction_ID`, `Transaction_date`, `Coustmer_ID`, `Product name`,
  `quantity`, `price`, `payment method`, `transaction status`
  *(column names are reproduced as-is from the raw source, including the original
  typo in `Coustmer_ID`)*
- Raw row count: 100,000 (a duplicate CSV import inflated the staging table to
  200,000 rows during ingestion; this was caught and corrected — see audit table)
- Final clean row count: **99,006**

## Data Quality Audit

| Issue | Rows Affected | % of Data | Decision | Rationale |
|---|---|---|---|---|
| Duplicate CSV import (staging table) | 100,000 | 50% (of inflated staging table) | Deduplicated staging table before analysis | Accidental double-import during ingestion, caught via row-count sanity check |
| Duplicate `transaction_id` (true exact duplicates) | ~929 IDs / ~980 rows | ~1% | Removed via `SELECT DISTINCT` | Confirmed byte-for-byte identical across all columns |
| Duplicate `transaction_id` (same ID, different data) | small subset | <1% | Assigned surrogate primary key (`row_id`, auto-increment) instead of trusting `transaction_id` as unique | Source `transaction_id` was found to be unreliable as a unique key — a real data integrity issue, not just messy formatting |
| Missing `transaction_id` | 5,018 rows | ~5% | Assigned surrogate ID (`GEN-` prefix) | Too large and valuable a chunk of data to drop |
| Inconsistent `payment_method` casing/spacing (6 raw variants → 3 real categories) | ~85,000+ rows normalized | ~85% | Standardized to `Cash`, `Credit Card`, `PayPal` | Same real category, differing only in text formatting |
| Blank `transaction_status` | 16,679 rows | ~16.7% | Labeled `Unknown` (not dropped) | Verified proportionally distributed across all payment methods — not concentrated, appears to be random system/logging gaps rather than a channel-specific issue |
| Negative `quantity` | 31,310 rows | ~31.6% | Converted to absolute value; original sign preserved in `quantity_was_negative` flag | Evenly distributed across all transaction statuses (not concentrated in Failed/returns), suggesting a systematic data export/sign bug rather than genuine returns |
| Non-numeric / currency-symbol `price` (e.g. `$182.38`, blank) | ~33,131 rows blank; additional rows had a `$` prefix | ~33% blank | Stripped currency symbols via regex; blank prices kept as `NULL` (not imputed) | Blank price is not safely imputable without inventing revenue figures |
| Negative `price` | subset overlapping ~33% with negative quantity | — | Converted to absolute value; original sign preserved in `price_was_negative` flag | Only ~33% overlap with negative-quantity rows — evidence of two independent data corruption issues, not one shared cause |
| Missing/invalid `transaction_date` (including impossible calendar dates, e.g. month 13) | 67,566 rows | ~68% | Left as `NULL`; explicitly excluded from any time-trend analysis | Too large a share of the data to impute; any trend analysis on the remaining ~31,440 valid-date rows is a partial-data view, not a full-population trend |

**Net result:** 99,006 of 100,000 original unique transactions were retained
(~99%), with every exclusion or correction explicitly logged above rather than
silently dropped.

## Key Findings

**1. Transaction status is roughly evenly split outside of "Completed."**

| Status | % of Transactions |
|---|---|
| Completed | 49.9% |
| Failed | 16.8% |
| Unknown | 16.7% |
| Pending | 16.6% |

*(Based on the full cleaned population of 99,006 transactions — see the note
below on why the revenue table in Finding 3 uses a different denominator.)*

**2. Failure rate is uniform across all payment methods (~16.5–16.9%).**

Cash, Credit Card, and PayPal all show statistically similar failure rates.
This rules out a payment-provider-specific integration problem and points
toward a systemic cause — for example, a shared backend validation step,
inventory/stock check, or fraud-screening layer — rather than an issue with
any single payment channel.

| Payment Method | Transactions | Failure Rate |
|---|---|---|
| Credit Card | 42,604 | 16.91% |
| PayPal | 42,349 | 16.77% |
| Cash | 14,053 | 16.54% |
| **Total** | **99,006** | **16.80%** |

**3. Unresolved transaction value is nearly equal to confirmed revenue —
these are two separate buckets, not parts of one total.**

| Status | Transactions | Value | Bucket |
|---|---|---|---|
| Completed | 32,940 | $3,061,527,976 | **Confirmed Revenue** |
| Failed | 11,034 | $1,052,063,029 | Unresolved |
| Pending | 10,995 | $1,037,733,227 | Unresolved |
| Unknown | 10,906 | $1,023,044,055 | Unresolved |
| **All statuses combined** | **65,875** | **$6,174,368,287** | Total value processed |

- **Confirmed Revenue** (Completed only): **$3.06B**
- **Unresolved Revenue** (Failed + Pending + Unknown): **$3.11B**
- These are independent totals that happen to be similar in size — not one
  number split into a subset. Combined, they represent the full $6.17B in
  transaction value that passed through the system.

This means roughly half of all transaction value processed through this
system never resolves into confirmed revenue.

*Note: the revenue table above covers only the 65,875 transactions with a
valid, non-blank `price` value (66.5% of the cleaned 99,006-row dataset) —
the remaining 33,131 rows had blank prices in the source data and are
excluded from all dollar-value calculations, consistent with the
"not imputed" decision in the audit table above. This is why the status
percentages here (e.g. Failed at 11,034 / 65,875 ≈ 16.8%) will differ
slightly from the full-population percentages in Finding 1 — they're drawn
from different denominators, and both are correct for what they measure.*

## Business Recommendation

Given that failure rates are uniform across payment methods rather than
concentrated in one channel, the highest-leverage next step is a **root-cause
investigation into the shared step(s) all payment methods pass through**
(e.g. fraud/risk screening, inventory validation, or a backend processing
step) rather than auditing any single payment provider relationship.

With an estimated **$1.05B in Unresolved revenue from Failed transactions
alone**, even a modest reduction in the failure rate — for example,
recovering 10% of currently failed transactions — would represent roughly
**$105M in recovered revenue** ($105.21M precisely), making this one of the
highest-value investigations the business could prioritize from this dataset.

## Limitations

- **68% of transaction dates were missing or invalid**, which prevents a
  reliable full-population time-trend analysis. Any date-based trend shown
  in the accompanying dashboard reflects only the ~31,440 transactions with
  valid dates and should be read as directional, not comprehensive.
- The dataset is not explicitly labeled for fraud; `transaction_status` was
  used as a proxy risk signal rather than a confirmed fraud indicator.
- Negative quantity/price values were assumed to be data corruption based on
  their even distribution across categories; this is an inference, not a
  confirmed root cause, and would benefit from validation against the
  original source system if access were available.

## Dashboard Notes

To avoid the confusing appearance of "risk" exceeding "total revenue," the
Power BI dashboard's summary cards are explicitly labeled:
- **Confirmed Revenue (Completed)** — not "Total Revenue"
- **Unresolved Revenue (Failed + Pending + Unknown)** — not "Revenue at Risk"
- **Total Transaction Value (All Statuses)** — shown separately so viewers
  can see both buckets are subsets of one larger total, not competing figures

## Repository Structure

```
sql/
├── 01_create_database_and_staging.sql   -- database + raw staging setup
├── 02_data_quality_audit.sql            -- full audit: missing values, duplicates,
│                                            format issues, sign-flip checks
├── 03_clean_and_transform.sql           -- clean table schema + transformation logic
└── 04_analysis_queries.sql              -- status, payment risk, revenue, trend queries

dashboard/
└── screenshots/                          -- Power BI dashboard pages (see preview above)
```

## Tools Used

MySQL (staging → cleaning → analysis pipeline), Power BI (dashboard)

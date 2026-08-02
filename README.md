# Customer Retention & Funnel Analytics Engine

SQL analytics on the UCI "Online Retail" dataset (~541,909 invoice lines, Dec 2010 – Dec 2011).
Normalised schema, cohort retention, RFM segmentation, and funnel analysis using CTEs, window
functions, and a view.

## Data

[UCI Online Retail dataset](https://archive.ics.uci.edu/dataset/352/online+retail) — UK-based
online gift retailer, transaction-level export. Imported via `LOAD DATA INFILE` and cleaned in
MySQL 8.0. Not included in this repo; download the CSV from the link above and place it where
`01_import_data.sql` expects it.

| | |
|---|---|
| Cohorts | 13 monthly |
| Date range | Dec 2010 – Dec 2011 |
| Customers analysed | 4,338 |

## Schema

```
customers 1 ──< orders 1 ──< order_items >── 1 products
```

Raw CSV → 3NF, with cancelled orders (`Invoice` prefixed `C`) flagged via `is_cancellation`
rather than removed.

## Results

**Cohort retention** (weighted by cohort size)

| Month | Retention |
|---|---|
| 1 | 22.7% |
| 3 | 25.6% |
| 6 | 27.2% |

**RFM segmentation**

| Segment | % customers | % revenue |
|---|---|---|
| Champions | 22.0% | 67.1% |
| Loyal | 26.3% | 16.5% |
| Hibernating | 28.4% | 6.1% |
| At Risk | 6.5% | 5.6% |
| Needs Attention | 12.0% | 3.9% |
| New / Promising | 4.8% | 0.8% |

**Purchase-lifecycle funnel**

| Stage | Customers | % of top | Drop-off |
|---|---|---|---|
| Acquired | 4,338 | 100% | — |
| Repeat buyer | 2,845 | 65.6% | 34.4% |
| Established (3+) | 2,010 | 46.3% | 29.3% |
| High value (top quintile) | 867 | 20.0% | 56.9% |

## Techniques

- CTEs for staged query construction
- `NTILE(5)` for RFM scoring and value banding
- `LAG()` / `FIRST_VALUE()` for funnel step conversion and drop-off
- A view (`v_customer_rfm`) over the RFM calculation
- 3NF normalisation with composite indexes on `(customer_id, order_ts)`

## Run it

Requires MySQL 8.0+.

```sql
SOURCE 01_import_data.sql;
SOURCE 02_schema_and_analysis.sql;
SOURCE 03_create_view.sql;
```

## Files

| File | Purpose |
|---|---|
| `01_import_data.sql` | CSV import |
| `02_schema_and_analysis.sql` | Schema build + cohort, RFM, and funnel queries |
| `03_create_view.sql` | RFM view |
| `Result_1.csv` | Cohort retention output |
| `Result_2.csv` | RFM segment summary |
| `Result_3.csv` | Funnel output |

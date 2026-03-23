# RetailIQ — Production-Grade MySQL Data Cleaning & ETL Pipeline

> A hands-on MySQL project cleaning a synthetically corrupted 77,000-row e-commerce database —  
> table by table, column by column, with documented reasoning for every transformation decision.

---

## Project Description

RetailIQ simulates the first and most critical step in any real data pipeline: **making raw data trustworthy before analysis begins.** The source database (`ecommerce_dirty`) was intentionally built with 15 categories of dirty data — format inconsistencies, impossible values, malformed strings, multi-format date columns, duplicate records, and referential integrity violations — mirroring exactly what data analysts encounter when working with live production systems.

This project covers the full cleaning workflow: schema inspection, collation audit, column-by-column data quality analysis, in-place transformation using `UPDATE`, and verification at every step. All cleaning was performed in **MySQL Workbench 8.0** using pure SQL — no scripts, no external tools.

---

## Table of Contents

1. [Project Scope](#1-project-scope)
2. [Technical Environment & Schema Inspection](#2-technical-environment--schema-inspection)
3. [Collation — The Foundation of String Comparison](#3-collation--the-foundation-of-string-comparison)
4. [Table Cleaning — Deep Dive](#4-table-cleaning--deep-dive)
   - [raw_customers](#41-raw_customers)
   - [raw_employees](#42-raw_employees)
   - [raw_order_items](#43-raw_order_items)
   - [raw_orders](#44-raw_orders)
5. [Cross-Cutting Patterns & Concepts](#5-cross-cutting-patterns--concepts)
   - [Title Case Without INITCAP](#51-title-case-without-initcap)
   - [String-to-Date Transformation](#52-string-to-date-transformation)
   - [Handling Negative Numeric Values](#53-handling-negative-numeric-values)
   - [NULL Strategy](#54-null-strategy)
   - [COLLATE utf8mb4_bin for Auditing](#55-collate-utf8mb4_bin-for-auditing)
6. [Dirty Data Taxonomy](#6-dirty-data-taxonomy)
7. [Transformation Summary](#7-transformation-summary)
8. [Skills Demonstrated](#8-skills-demonstrated)
9. [Project File Structure](#9-project-file-structure)

---

## 1. Project Scope

| Field | Detail |
|---|---|
| **Domain** | E-Commerce Operations |
| **Database** | MySQL 8.0 (InnoDB, `utf8mb4_unicode_ci`) |
| **Tool** | MySQL Workbench 8.0 |
| **Total Dataset** | 77,346 rows across 8 tables |
| **Tables Cleaned** | 4 — `raw_customers`, `raw_employees`, `raw_order_items`, `raw_orders` |
| **Approach** | In-place `UPDATE` on raw tables (with `SET SQL_SAFE_UPDATES = 0/1` guards) |
| **Dirty Pattern Categories** | 15 documented |

**Design philosophy:** Every cleaning operation targets exactly the problem observed — no over-engineering, no assumptions beyond what the data shows. Observations are noted as SQL comments before each section, a production-standard habit for auditable data work.

---

## 2. Technical Environment & Schema Inspection

Every table was inspected using the same three-query audit pattern before writing a single `UPDATE`:

```sql
SHOW FULL COLUMNS FROM raw_customers;    -- data types, collation, nullability per column
SHOW TABLE STATUS LIKE 'raw_customers';  -- row count, engine, character set at table level
SELECT @@collation_database;             -- database-level collation
SELECT @@collation_server;               -- server-level collation fallback
```

**Why this matters:**
- `SHOW FULL COLUMNS` reveals the collation assigned per column — critical for understanding whether string comparisons will be case-sensitive or not before writing any `WHERE` or `UPDATE`
- `SHOW TABLE STATUS` gives the authoritative row count before cleaning, so you can verify rows affected after each operation
- Checking `@@collation_database` vs `@@collation_server` tells you whether the database inherited a custom collation or is using the server default — a mismatch can cause unexpected comparison behaviour in JOINs across databases

**Findings across all four tables:**
```
collation_database = utf8mb4_unicode_ci   -- case-insensitive by default
collation_server   = utf8mb4_0900_ai_ci   -- server default (also case-insensitive)
```

Because the database uses `_ci` (case-insensitive) collation, `WHERE department = 'sales'` and `WHERE department = 'SALES'` return the same rows in a `SELECT`. For **auditing** dirty data — where you specifically need to see each distinct casing variant as a separate value — this default collation hides the problem. The solution is covered in §3.

---

## 3. Collation — The Foundation of String Comparison

**This is the most important conceptual section in the project.**

### What collation controls

Collation defines two things: how characters are compared (equality) and how they are sorted (ordering). For data cleaning, the comparison behaviour is what matters.

| Collation | `'Gold' = 'gold'?` | `'café' = 'cafe'?` | Use case |
|---|---|---|---|
| `utf8mb4_unicode_ci` | ✅ Yes | ✅ Yes | Application queries — user-facing |
| `utf8mb4_general_ci` | ✅ Yes | ✅ Yes | Faster but less accurate Unicode |
| `utf8mb4_bin` | ❌ No | ❌ No | **Data auditing — see every variant** |

### The audit problem

With `utf8mb4_unicode_ci` (default), this query hides dirty data:

```sql
SELECT DISTINCT department FROM raw_employees;
-- Returns: 'HR', 'IT', 'Sales', 'Marketing' ...
-- HIDES: 'hr', 'SALES', 'marketing', 'iT' — treated as identical to their clean versions
```

### The `COLLATE utf8mb4_bin` override

Applied inline at query time to force binary (case-sensitive, exact-byte) comparison without permanently altering the table:

```sql
-- This reveals every distinct casing variant as a separate row
SELECT DISTINCT department COLLATE utf8mb4_bin FROM raw_employees;
-- Returns: 'HR', 'hr', 'Hr', 'hR', 'IT', 'it', 'Sales', 'sales', 'SALES' ...
```

```sql
-- Same pattern used for orders
SELECT DISTINCT shipping_city, shipping_state, shipping_country COLLATE utf8mb4_bin
FROM raw_orders;
```

**This is the correct audit workflow:** use `COLLATE utf8mb4_bin` in `SELECT` to discover all variants, then write targeted `CASE` statements in `UPDATE` to normalise them. The collation on the table is never permanently changed — only the query-level comparison is overridden.

**Documented real discovery from the project:**
```sql
-- Comment from raw_customer_cleaning.sql:
-- "one problem — while extracting lowercase entries of UK and USA,
--  getting no valid values. but while exploring manually, seeing the discrepancy."
```
This is the collation problem in practice. `WHERE country = 'usa'` returns no rows because `utf8mb4_unicode_ci` already matches `'USA'` case-insensitively, so the `GROUP BY` audit shows only one value. The variants only became visible after applying `COLLATE utf8mb4_bin`.

---

## 4. Table Cleaning — Deep Dive

---

### 4.1 `raw_customers`

**Rows before cleaning:** ~5,200 | **Most complex table in the project**

```sql
SELECT * FROM raw_customers;
/* Observations: Multiple non-uniform formats in full_name, phone, city, state,
   gender, signup_date, loyalty_tier — and all names should be unique */

-- Verify primary key integrity first
SELECT customer_id, COUNT(*) AS total_count
FROM raw_customers
GROUP BY customer_id
ORDER BY total_count DESC;
-- Result: all customer_ids are unique — no PK duplicates
```

---

#### Column: `full_name`

**Problem:** Names arrived in ALL CAPS, all lowercase, reversed `Last, First` format, and with leading/trailing spaces.

**Solution — custom title-case implementation:**

```sql
UPDATE raw_customers
SET full_name =
CONCAT(
    -- First name: capitalise first letter, lowercase the rest
    CONCAT(
        UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 1, 1)),
        LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 2))
    ),
    ' ',
    -- Last name: same pattern using -1 to extract from the right
    CONCAT(
        UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 1, 1)),
        LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 2))
    )
);
```

**Why MySQL requires this complexity:**
MySQL has no `INITCAP()` function (unlike PostgreSQL/Oracle). The pattern `CONCAT(UPPER(SUBSTRING(...,1,1)), LOWER(SUBSTRING(...,2)))` is the standard MySQL idiom for title-casing a word. Breaking it down:

| Function | Role |
|---|---|
| `TRIM(full_name)` | Remove leading/trailing spaces before any operation |
| `SUBSTRING_INDEX(str, ' ', 1)` | Extract everything before the first space = first name |
| `SUBSTRING_INDEX(str, ' ', -1)` | Extract everything after the last space = last name |
| `UPPER(SUBSTRING(word, 1, 1))` | Capitalise the first character |
| `LOWER(SUBSTRING(word, 2))` | Lowercase all remaining characters from position 2 onward |

**Second pass — remove comma from reversed `Last, First` format:**

```sql
UPDATE raw_customers
SET full_name = REPLACE(full_name, ',', '');
```

This runs after title-casing, so `'Smith, John'` → title-case → `'Smith, John'` → REPLACE → `'Smith John'`. Order of operations matters.

---

#### Column: `email`

**Problem:** Mixed case (`JOHN.DOE@GMAIL.COM`), leading/trailing whitespace.

```sql
UPDATE raw_customers
SET email = LOWER(TRIM(email));
```

Email addresses are case-insensitive by convention (RFC 5321). Storing them consistently in lowercase enables reliable equality checks and deduplication on this column downstream.

---

#### Column: `phone`

**Problem:** Six different formats in one column — `(987) 654-3210`, `987-654-3210`, `+19876543210`, `+1-987-654-3210`, raw digits, and padded with spaces.

**Pre-check:**
```sql
SELECT phone, LENGTH(phone) FROM raw_customers
WHERE LENGTH(phone) < 10 OR LENGTH(phone) > 15;
-- Result: no data entry discrepancy at length level
```

**Goal:** E.164 international format — `+[country_code][number]`

**Approach — chained `REPLACE` to strip all formatting characters:**

```sql
UPDATE raw_customers
SET phone = CONCAT('+',
    REPLACE(
      REPLACE(
        REPLACE(
          REPLACE(
            REPLACE(TRIM(phone), '(', ')'),  -- normalise ( → )
          ')', '+'),                          -- normalise ) → +
        '+', '-'),                            -- normalise + → -
      '-', ' '),                              -- normalise - → space
    ' ', '')                                  -- strip all spaces
);
```

**What this achieves:** By systematically converting all separator characters — parentheses, hyphens, plus signs — into a uniform separator (space), and then stripping all spaces, the result is a raw digit string. Prepending `'+'` reconstructs the E.164 prefix.

**Note on `REGEXP_REPLACE` as an alternative:**
MySQL 8.0 supports `REGEXP_REPLACE(phone, '[^0-9]', '')` which extracts digits directly and is more concise. The chained-REPLACE approach is explicit about exactly which characters are being removed and works on older MySQL versions too.

---

#### Column: `city` / `state` / `country`

**Problem:** Abbreviations mixed with full names (`NY` vs `New York`), inconsistent casing for country names (`usa`, `Usa`, `USA`), and isolated uppercase city entries.

**City — targeted spot fix:**
```sql
SELECT COUNT(*) AS total_count, city
FROM raw_customers
GROUP BY city
ORDER BY total_count;

UPDATE raw_customers SET city = 'Seattle' WHERE city = 'SEATTLE';
```

Not every problem needs a complex CASE. When the audit reveals only one or two rogue values, a direct `WHERE` fix is more readable and less error-prone than a full CASE block.

**State — country-context-aware CASE mapping:**

```sql
UPDATE raw_customers
SET state = CASE
    -- USA: postal abbreviations → full state names
    WHEN country = 'USA' AND state = 'MN' THEN 'Minnesota'
    WHEN country = 'USA' AND state = 'OR' THEN 'Oregon'
    WHEN country = 'USA' AND state = 'MA' THEN 'Massachusetts'
    WHEN country = 'USA' AND state = 'FL' THEN 'Florida'
    WHEN country = 'USA' AND state = 'IL' THEN 'Illinois'
    WHEN country = 'USA' AND state = 'AZ' THEN 'Arizona'
    WHEN country = 'USA' AND state = 'GA' THEN 'Georgia'
    WHEN country = 'USA' AND state = 'PA' THEN 'Pennsylvania'
    WHEN country = 'USA' AND state = 'CO' THEN 'Colorado'
    WHEN country = 'USA' AND state = 'TN' THEN 'Tennessee'
    -- Canada
    WHEN country = 'Canada' AND state = 'ON' THEN 'Ontario'
    WHEN country = 'Canada' AND state = 'QC' THEN 'Quebec'
    WHEN country = 'Canada' AND state = 'BC' THEN 'British Columbia'
    -- Australia, UK, Germany ...
    ELSE state
END;
```

**Why the `country` condition is essential:**
State codes are not globally unique. `'ON'` is Ontario (Canada) but could appear in other contexts. Scoping the mapping with `WHERE country = 'Canada' AND state = 'ON'` makes each branch unambiguous. This is the correct approach for any multi-country geographic dataset.

**Country normalisation:**
```sql
UPDATE raw_customers
SET country = CASE
    WHEN country IN ('USA', 'U.S.A', 'UNITED STATES', 'usa') THEN 'USA'
    WHEN country IN ('UK',  'U.K',   'UNITED KINGDOM',  'uk') THEN 'UK'
    ELSE country
END;
```

---

#### Column: `age`

**Problem:** Biologically impossible values — ages 0–5 and 120–200 — and NULLs.

**Decision: DELETE rows with invalid age (not NULL)**

```sql
SELECT COUNT(*) AS total_count, age
FROM raw_customers
GROUP BY age
ORDER BY total_count;

SELECT * FROM raw_customers WHERE age IS NULL;

DELETE FROM raw_customers WHERE age NOT BETWEEN 10 AND 100;
```

**Why DELETE and not `SET age = NULL`?**
A customer with `age = 185` is not a real record — the value cannot be traced back to a correct one. Setting it to NULL would silently retain that customer in all customer-count analyses. Deleting the row removes entirely untrustworthy records. The threshold of 10–100 is explicitly chosen and documented as a business rule.

**Contrast:** In `raw_employees`, salary used `ABS()` because `-75,000` has a recoverable correct value (just wrong sign). An age of `185` has no recoverable correct value, hence deletion.

---

#### Column: `gender`

```sql
UPDATE raw_customers
SET gender = CASE
    WHEN UPPER(TRIM(gender)) IN ('MALE', 'M')        THEN 'Male'
    WHEN UPPER(TRIM(gender)) IN ('FEMALE', 'F')       THEN 'Female'
    WHEN UPPER(TRIM(gender)) = 'PREFER NOT TO SAY'    THEN 'Prefer not to say'
    WHEN UPPER(TRIM(gender)) = 'NON-BINARY'           THEN 'Non-Binary'
    ELSE NULL
END;
```

**`UPPER(TRIM())` before CASE — the standard normalisation idiom:**
Always reduce the string to a controlled base form before pattern-matching. `UPPER()` collapses all case variants into one form you own. `TRIM()` removes whitespace that would cause `'Male '` to not match `'MALE'`. Empty strings and unrecognised values map to `NULL` — they are genuinely missing, not miscategorised. The `WHERE gender = ''` audit step confirmed empty strings existed and needed to be collapsed to NULL.

---

#### Column: `signup_date`

**Problem:** VARCHAR column storing dates in four distinct formats, plus slash-separated variants.

**Documented date format inventory:**
```sql
/* Dates format — 4 types:
   1. YYYY-MM-DD    -- no problem for conversion
   2. DD-Mon-YYYY   -- safe conversion, no problem (e.g. 31-Mar-2018)
   3. MM-DD-YYYY    -- use when middle segment > 12 (unambiguous: it must be a day)
   4. DD-MM-YYYY    -- default for all other ambiguous numeric dates
*/
```

**Step 1 — Normalise separators before parsing:**
```sql
UPDATE raw_customers
SET signup_date = REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '');
```

This collapses `15/04/2023` and `15-04-2023` into an identical string before the CASE fires. Reducing to one separator eliminates one dimension of ambiguity.

**Step 2 — Multi-format CASE parser with REGEXP and SUBSTRING disambiguation:**

```sql
-- ISO: YYYY-MM-DD — identified by REGEXP, unambiguous
WHERE REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    → STR_TO_DATE(signup_date, '%Y-%m-%d')

-- Abbreviated month: DD-Mon-YYYY (e.g. 31-Mar-2018) — unambiguous, month is alphabetic
WHERE REGEXP '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$'
    → STR_TO_DATE(signup_date, '%d-%b-%Y')

-- Numeric 8-digit: resolve ambiguity using the middle segment
-- If SUBSTRING(date, 4, 2) > 12 → middle is a day → first segment must be month
WHERE REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
    AND SUBSTRING(..., 4, 2) > 12
    → STR_TO_DATE(signup_date, '%m-%d-%Y')

-- Everything else → default DD-MM-YYYY (documented business decision)
WHERE REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
    → STR_TO_DATE(signup_date, '%d-%m-%Y')
```

**The core ambiguity problem — explicitly documented:**
`04-06-2023` could be April 6th or June 4th. There is no programmatic way to resolve this. The decision — *"deciding to go with DD-MM-YYYY interpretation for any ambiguous data"* — is a deliberate, stated business rule. Explicit documentation of an ambiguous decision is better practice than silently guessing.

**Why `STR_TO_DATE` returns NULL on mismatch:**
`STR_TO_DATE('15-Apr-2023', '%d-%m-%Y')` returns `NULL`, not an error. This is the intended behaviour — a failed parse surfaces as NULL (detectable, queryable) rather than crashing the UPDATE. The REGEXP pre-filters ensure each branch only fires for strings matching that pattern.

---

#### Column: `loyalty_tier`

```sql
UPDATE raw_customers
SET loyalty_tier = CASE
    WHEN UPPER(TRIM(loyalty_tier)) IN ('PLATINUM', 'PLATIMUM') THEN 'Platinum'
    WHEN UPPER(TRIM(loyalty_tier)) = 'DIAMOND'                 THEN 'Diamond'
    WHEN UPPER(TRIM(loyalty_tier)) = 'GOLD'                    THEN 'Gold'
    WHEN UPPER(TRIM(loyalty_tier)) = 'SILVER'                  THEN 'Silver'
    WHEN UPPER(TRIM(loyalty_tier)) = 'BRONZE'                  THEN 'Bronze'
    ELSE NULL
END;
```

`'PLATIMUM'` is a genuine typo in the source data (missing the second `I`). The `IN()` list handles both the correct and misspelled forms, mapping both to `'Platinum'`. Explicit enumeration of known variants is the correct approach for typo correction — safer than fuzzy matching or `LIKE`.

---

### 4.2 `raw_employees`

**Rows: 200 | Key complexity: self-referencing `manager_id`, salary sign errors**

```sql
SHOW FULL COLUMNS FROM raw_employees;
SHOW TABLE STATUS LIKE 'raw_employees';
SELECT @@collation_database;
SELECT @@collation_server;
SELECT * FROM raw_employees;
```

---

#### Column: `full_name` / `email`

Same title-case pattern as `raw_customers`. Applied with `SET SQL_SAFE_UPDATES = 0` — a single block at the top of the script covers all subsequent updates, which is cleaner than toggling it per statement.

```sql
UPDATE raw_employees
SET full_name =
CONCAT(
    CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 1, 1)),
           LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 2))),
    ' ',
    CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 1, 1)),
           LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 2))));

UPDATE raw_employees
SET email = LOWER(TRIM(email));
```

---

#### Column: `department`

**Two-step approach — inspect with binary collation first, then clean:**

```sql
-- Step 1: binary collation to see all case variants
SELECT DISTINCT department COLLATE utf8mb4_bin FROM raw_employees;
-- Reveals: 'HR', 'hr', 'Hr', 'hR', 'IT', 'it', 'Customer Support',
--           'customer support', 'customersupport' ...

-- Step 2: TRIM first, then CASE
UPDATE raw_employees SET department = TRIM(department);

UPDATE raw_employees
SET department = CASE
    WHEN department IN ('hr', 'Hr', 'hR')                                        THEN 'HR'
    WHEN department IN ('it', 'It', 'iT')                                        THEN 'IT'
    WHEN department = 'logistics'                                                 THEN 'Logistics'
    WHEN department = 'marketing'                                                 THEN 'Marketing'
    WHEN department = 'operations'                                                THEN 'Operations'
    WHEN department = 'sales'                                                     THEN 'Sales'
    WHEN department = 'finance'                                                   THEN 'Finance'
    WHEN department IN ('Customer Support','Customer support',
                        'customer support','customersupport')                     THEN 'Customer Support'
    ELSE department
END;
```

**Why `TRIM()` before the CASE, not inside it:**
A separate `UPDATE ... SET department = TRIM(department)` runs first so the subsequent CASE does not need to account for `' HR'` (space-prefixed) as a separate variant. Each step narrows the problem for the next step.

**`HR` and `IT` require explicit enumeration in `IN()`:**
The general title-case trick (`CONCAT(UPPER first char, LOWER rest)`) does not work for all-uppercase abbreviations. Lowercasing `'HR'` yields `'Hr'`, not `'HR'`. These must be explicitly listed.

---

#### Column: `salary`

```sql
UPDATE raw_employees
SET salary = ROUND(ABS(salary), 2);
```

`ABS()` as a recovery strategy: a salary of `-75,000` is a sign error — the magnitude is valid and recoverable. `ROUND(..., 2)` enforces two decimal places, eliminating floating-point artifacts like `75000.000000001`.

---

#### Column: `status`

```sql
SELECT DISTINCT status COLLATE utf8mb4_bin FROM raw_employees;

UPDATE raw_employees
SET status = CASE
    WHEN status IN ('active','Active','ACTIVE',
                    'inactive','Inactive',
                    'terminated','Terminated')
        THEN CONCAT(SUBSTRING(UPPER(status), 1, 1), SUBSTRING(LOWER(status), 2))
    WHEN status IN ('On Leave','on leave') THEN 'On Leave'
    ELSE status
END;
```

**The compact single-word title-case pattern:**
`CONCAT(SUBSTRING(UPPER(status), 1, 1), SUBSTRING(LOWER(status), 2))` is a cleaner approach for single-word values. It uppercases character 1 and lowercases the rest in one expression — no `SUBSTRING_INDEX` needed because there's no space to navigate.

`'On Leave'` is a two-word value and cannot rely on this trick — it requires an explicit mapping.

**`/* ALTER TABLE raw_employees MODIFY status VARCHAR(50) COLLATE utf8mb4_bin; */`**
This commented-out line captures an important architectural decision: making the binary collation permanent at column level would enforce exact-case comparisons in all future queries on this column. Leaving it commented means the choice was evaluated and intentionally deferred — a production database would assess the downstream impact before making a permanent collation change.

---

### 4.3 `raw_order_items`

**Rows: ~25,460 | All columns are numeric — most concise cleaning in the project**

```sql
SHOW FULL COLUMNS FROM raw_order_items;   -- confirms: all numeric types, no string issues
SHOW TABLE STATUS LIKE 'raw_order_items'; -- 25,460 rows
SELECT @@collation_database;
SELECT @@collation_server;
```

The schema audit confirmed there are no string columns, so no case normalisation or TRIM operations are needed. The only problems are numeric integrity issues.

```sql
UPDATE raw_order_items
SET unit_price = ROUND(ABS(unit_price), 2),
    discount   = ROUND(ABS(discount),   2);
```

**Two operations in one `UPDATE` statement:**
Combining multiple column updates in a single `SET` clause is more efficient than two separate UPDATE statements — MySQL performs one table scan and one write pass.

**`ABS()` for negatives:** A `unit_price` of `-199.99` is a sign error; the magnitude is valid. `ABS()` recovers the correct value without data loss.

**`discount` and NULL:** NULL in the discount column is left as NULL intentionally — it preserves the distinction between "no discount applied" (value = 0) and "discount value not recorded" (NULL). Downstream queries handle this with `COALESCE(discount, 0)` at query time.

---

### 4.4 `raw_orders`

**Rows: ~20,092 | Geographic and numeric cleaning — same patterns applied at larger scale**

```sql
SHOW FULL COLUMNS FROM raw_orders;
SHOW TABLE STATUS LIKE 'raw_orders';
SELECT @@collation_database;
SELECT @@collation_server;
```

---

#### Columns: `shipping_city` / `shipping_state` / `shipping_country`

```sql
-- Audit with binary collation first
SELECT DISTINCT shipping_city, shipping_state, shipping_country COLLATE utf8mb4_bin
FROM raw_orders;

-- Targeted city fix
UPDATE raw_orders SET shipping_city = 'Houston' WHERE shipping_city = 'HOUSTON';

-- Country-scoped state expansion (same pattern as raw_customers, more states)
UPDATE raw_orders
SET shipping_state = CASE
    WHEN shipping_country = 'USA' AND shipping_state = 'NY' THEN 'New York'
    WHEN shipping_country = 'USA' AND shipping_state = 'CA' THEN 'California'
    WHEN shipping_country = 'USA' AND shipping_state = 'TX' THEN 'Texas'
    WHEN shipping_country = 'USA' AND shipping_state = 'WA' THEN 'Washington'
    -- ... full mapping including Canada, Australia, UK, Germany
    ELSE shipping_state
END;

-- Country normalisation
UPDATE raw_orders
SET shipping_country = CASE
    WHEN shipping_country IN ('USA', 'usa', 'Usa')                  THEN 'USA'
    WHEN shipping_country IN ('UK',  'uk',  'Uk')                   THEN 'UK'
    WHEN shipping_country IN ('Australia','australia','AUSTRALIA')   THEN 'Australia'
    WHEN shipping_country IN ('Canada','CANADA','canada')            THEN 'Canada'
    ELSE 'Germany'
END;
```

---

#### Columns: `total_amount` / `discount_pct`

```sql
UPDATE raw_orders
SET total_amount = ROUND(ABS(total_amount), 2),
    discount_pct = ROUND(ABS(discount_pct), 2);
```

Consistent with the numeric cleaning strategy from `raw_order_items` — `ABS()` for sign recovery, `ROUND(..., 2)` for currency precision standardisation. Both columns in one pass.

---

## 5. Cross-Cutting Patterns & Concepts

---

### 5.1 Title Case Without INITCAP

MySQL has no native `INITCAP()` function. Two patterns were used depending on the value type:

**For multi-word names (First Last) — used in `raw_customers` and `raw_employees`:**
```sql
CONCAT(
    -- First word
    CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(name), ' ', 1), 1, 1)),
           LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(name), ' ', 1), 2))),
    ' ',
    -- Last word
    CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(name), ' ', -1), 1, 1)),
           LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(name), ' ', -1), 2)))
)
```

**For single-word values (status, department) — used in `raw_employees`:**
```sql
CONCAT(SUBSTRING(UPPER(value), 1, 1), SUBSTRING(LOWER(value), 2))
```

`SUBSTRING_INDEX(str, ' ', 1)` returns everything before the first space. `SUBSTRING_INDEX(str, ' ', -1)` returns everything after the last space. For a two-word name this correctly isolates first and last name. `SUBSTRING(word, 1, 1)` and `SUBSTRING(word, 2)` then split each word for capitalisation.

---

### 5.2 String-to-Date Transformation

**The complete decision framework used in this project:**

```
Raw VARCHAR date
    ↓
Step 1: TRIM() + REPLACE('/', '-') + REPLACE(' ', '')
    → normalise to hyphen-delimited, no spaces
    ↓
Step 2: REGEXP pattern matching to identify format
    → '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'    → YYYY-MM-DD    → '%Y-%m-%d'
    → '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$' → DD-Mon-YYYY   → '%d-%b-%Y'
    → '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'    → ambiguous     → resolve below
    ↓
Step 3: Ambiguity resolution for numeric-only DD/MM formats
    → SUBSTRING(normalised_date, 4, 2) > 12
      → middle segment is a day → use '%m-%d-%Y'
    → else
      → default to '%d-%m-%Y' (documented business decision)
    ↓
Step 4: STR_TO_DATE(normalised_string, format_specifier)
    → returns proper DATE value or NULL on mismatch — never an error
```

**Key format specifiers:**

| Specifier | Meaning | Example |
|---|---|---|
| `%Y` | 4-digit year | 2023 |
| `%m` | Month, zero-padded | 04 |
| `%d` | Day, zero-padded | 09 |
| `%b` | Abbreviated month name | Apr |

**After conversion — all date arithmetic becomes possible:**
```sql
-- Before (VARCHAR): subtraction is meaningless
SELECT ship_date - order_date FROM raw_orders;  -- returns string arithmetic garbage

-- After (DATE): meaningful arithmetic
SELECT
    DATEDIFF(ship_date_clean, order_date_clean)       AS processing_days,
    TIMESTAMPDIFF(MONTH, order_date_clean, CURDATE()) AS months_ago,
    YEAR(order_date_clean)                             AS order_year,
    QUARTER(order_date_clean)                          AS order_quarter
FROM clean_orders;
```

---

### 5.3 Handling Negative Numeric Values

Three strategies were applied across the four tables depending on the business meaning of the column:

| Column | Negative Example | Strategy | Reasoning |
|---|---|---|---|
| `salary` | `-75000` | `ABS()` | Sign error — magnitude is valid and recoverable |
| `unit_price` | `-199.99` | `ABS()` | Sign error — price magnitude is valid |
| `discount` | `-0.15` | `ABS()` | Sign error — discount magnitude is valid |
| `total_amount` | `-450.00` | `ABS()` | Sign error — order total magnitude is valid |
| `age` | `185` | `DELETE` | Impossible value — no valid interpretation exists |

**The decision rule:** Use `ABS()` when the magnitude carries true information and only the sign is wrong (recoverable). Use `DELETE` when the entire value is untrustworthy and there is no correct version to recover.

---

### 5.4 NULL Strategy

NULLs in this dataset fall into three categories, each handled differently:

| Type | Description | Example | Treatment |
|---|---|---|---|
| **Missing** | Data was never collected | `phone = NULL` | Preserved as NULL |
| **Invalid → NULL** | Value existed but was uncleanable | Unparseable date | `CASE ELSE NULL` |
| **Invalid → DELETE** | Entire row is untrustworthy | `age = 185` | `DELETE` |

**The `COALESCE` pattern for NULL-safe arithmetic:**
```sql
-- Without COALESCE: NULL propagates — entire expression becomes NULL
SELECT quantity * unit_price * (1 - discount) FROM raw_order_items;
-- If discount IS NULL → result IS NULL → revenue silently underreported

-- With COALESCE: NULL treated as 0
SELECT quantity * unit_price * (1 - COALESCE(discount, 0)) FROM raw_order_items;
```

**`NULLIF` for safe division:**
```sql
SELECT total_revenue / NULLIF(order_count, 0) AS avg_value;
-- If order_count = 0, NULLIF returns NULL → NULL / 0 never fires — no error
```

**Empty string ≠ NULL — a critical SQL distinction:**
```sql
SELECT * FROM raw_customers WHERE gender = '';     -- finds empty strings
SELECT * FROM raw_customers WHERE gender IS NULL;  -- finds NULLs
-- These are two different populations. The CASE ELSE NULL pattern converts
-- empty strings to proper NULLs, merging both into one consistent unknown state.
```

---

### 5.5 COLLATE utf8mb4_bin for Auditing

The workflow established in this project for any string column:

```sql
-- 1. Audit — force binary comparison to reveal all casing variants
SELECT COUNT(*) AS cnt, column_name COLLATE utf8mb4_bin
FROM table_name
GROUP BY column_name COLLATE utf8mb4_bin
ORDER BY cnt DESC;

-- 2. Clean — write CASE targeting the specific variants found
UPDATE table_name
SET column_name = CASE
    WHEN column_name IN ('variant1', 'variant2') THEN 'CanonicalValue'
    ...
END;

-- 3. Verify — re-run audit to confirm all variants collapsed to one
SELECT COUNT(*) AS cnt, column_name COLLATE utf8mb4_bin
FROM table_name
GROUP BY column_name COLLATE utf8mb4_bin;
```

`COLLATE utf8mb4_bin` is applied only in the `SELECT` — it does not change the table's storage collation. It is a query-level lens for auditing, not a permanent schema change. The commented-out `ALTER TABLE ... MODIFY ... COLLATE utf8mb4_bin` line in `raw_employees` documents that making it permanent was considered and deferred.

---

## 6. Dirty Data Taxonomy

Complete reference of all 15 dirty data categories handled across the four cleaned tables:

| # | Category | Tables | Detection | Fix Applied |
|---|---|---|---|---|
| 1 | Inconsistent string casing | all four | `GROUP BY col COLLATE utf8mb4_bin` | `LOWER/UPPER(TRIM()) + CASE` |
| 2 | Leading/trailing whitespace | all four | `WHERE col != TRIM(col)` | `TRIM()` |
| 3 | Phone number format inconsistency | customers | Length check + visual audit | Chained `REPLACE` → E.164 |
| 4 | Reversed name format (`Last, First`) | customers | `SELECT * LIMIT` observation | `REPLACE(name, ',', '')` post title-case |
| 5 | Multi-format date strings (VARCHAR) | customers, employees, orders | `REGEXP` pattern analysis | `REPLACE` normalise + `CASE STR_TO_DATE` |
| 6 | Ambiguous date formats (`04/06/2023`) | customers, employees, orders | `SUBSTRING` segment > 12 check | DD-MM-YYYY as default (documented rule) |
| 7 | Impossible numeric values | customers (age) | `WHERE age NOT BETWEEN 10 AND 100` | `DELETE` |
| 8 | Negative numeric values (sign errors) | employees, order_items, orders | `WHERE col < 0` | `ABS()` |
| 9 | Typos in categorical values | customers (`PLATIMUM`) | `GROUP BY COLLATE utf8mb4_bin` | `IN('PLATINUM','PLATIMUM')` in CASE |
| 10 | State abbreviations vs full names | customers, orders | `SELECT DISTINCT state` | Country-scoped `CASE` mapping |
| 11 | Country name variants | customers, orders | `SELECT DISTINCT country COLLATE utf8mb4_bin` | `IN()` list normalisation |
| 12 | NULL in arithmetic columns | order_items (discount) | `WHERE discount IS NULL` | `COALESCE(discount, 0)` at query time |
| 13 | Decimal precision inconsistency | order_items, orders | `SELECT unit_price` inspect | `ROUND(col, 2)` |
| 14 | Gender free-text vs controlled vocabulary | customers | `GROUP BY gender COLLATE utf8mb4_bin` | `UPPER(TRIM()) + CASE` |
| 15 | Empty string ≠ NULL | customers (gender) | `WHERE gender = ''` | `CASE ELSE NULL` converts to proper NULL |

---

## 7. Transformation Summary

| Table | Input Rows | Post-Clean Rows | Δ Rows | Primary Reason |
|---|---|---|---|---|
| `raw_customers` | ~5,200 | ~4,970 | ~-230 | `DELETE` on age outside 10–100 |
| `raw_employees` | 200 | 200 | 0 | All issues resolved in-place |
| `raw_order_items` | ~25,460 | ~25,460 | 0 | Numeric fixes only — no deletions |
| `raw_orders` | ~20,092 | ~20,092 | 0 | Numeric and string fixes — no deletions |

---

## 8. Skills Demonstrated

**Schema Inspection**
- `SHOW FULL COLUMNS` — per-column data type, collation, nullability
- `SHOW TABLE STATUS` — row count, engine, charset
- `SELECT @@collation_database` / `@@collation_server`
- `DESCRIBE` / `SHOW COLUMNS FROM`

**String Functions**
- `TRIM`, `LTRIM`, `RTRIM`
- `UPPER`, `LOWER`
- `SUBSTRING`, `SUBSTRING_INDEX`
- `CONCAT`
- `REPLACE` — character-level substitution (chained)
- `LENGTH`, `CHAR_LENGTH`
- `REGEXP` — pattern validation and format detection

**Conditional Logic**
- `CASE WHEN ... THEN ... ELSE ... END` — multi-branch transformation
- `IN(...)` — multi-value matching within CASE
- `COALESCE` — NULL-safe value substitution
- `NULLIF` — NULL-on-equality for division safety
- `ABS` — absolute value for sign-error recovery
- `ROUND` — decimal precision enforcement

**Date Functions**
- `STR_TO_DATE` — string-to-date parsing with format specifiers
- `DATE_FORMAT` — date-to-string formatting
- `DATEDIFF`, `TIMESTAMPDIFF` — date arithmetic
- `YEAR`, `MONTH`, `QUARTER`, `DAYNAME` — component extraction
- `CURDATE` — current date reference

**Data Auditing**
- `GROUP BY COUNT(*)` — distribution analysis
- `COLLATE utf8mb4_bin` — case-sensitive distinct value inspection
- `SELECT DISTINCT` — categorical column auditing
- `WHERE col NOT BETWEEN` — range violation detection
- `WHERE col IS NULL` / `WHERE col = ''` — null vs empty string

**DML & Safe Update Practices**
- `UPDATE ... SET ... WHERE` — targeted in-place transformation
- `DELETE ... WHERE` — row-level removal with explicit conditions
- `SET SQL_SAFE_UPDATES = 0 / 1` — safe mode management for bulk updates
- Multi-column `UPDATE` in a single `SET` for efficiency

**Database Concepts**
- `utf8mb4` vs `utf8` character sets
- `_ci` (case-insensitive) vs `_bin` (binary/exact) collations and their impact on query behaviour
- NULL semantics in SQL arithmetic and comparisons
- Empty string vs NULL distinction
- Primary key integrity verification before cleaning
- Country-scoped conditional logic for geographic data
- E.164 international phone number standard
- Recovery strategies: `ABS()` for sign errors vs `DELETE` for impossible values

---

## 9. Project File Structure

```
RetailIQ-MySQL-Cleaning/
│
├── README.md
│
├── data/
│   └── ecommerce_dirty.sql               ← Source database (77,346 rows, 8 tables)
│
├── cleaning/
│   ├── raw_customer_cleaning.sql         ← full_name, email, phone, city/state/country,
│   │                                        age, gender, signup_date, loyalty_tier
│   ├── raw_employees_cleaning.sql        ← full_name, email, department, salary,
│   │                                        status (hire_date: same date pattern)
│   ├── raw_order_items_cleaning.sql      ← unit_price, discount (numeric precision)
│   └── raw_orders_cleaning.sql           ← shipping geo columns, total_amount,
│                                            discount_pct, date columns
│
└── reference/
    └── mysql_practice_guide.sql          ← Full concept reference: CTEs, window
                                             functions, views, procedures, triggers,
                                             indexes, transactions, RFM analysis
```

---

*Built entirely in MySQL Workbench 8.0. No external libraries. No scripts. Pure SQL.*

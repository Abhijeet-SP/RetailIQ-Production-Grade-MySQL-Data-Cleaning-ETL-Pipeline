# 🧠 Data Cleaning Strategy

## 📌 Objective

The goal of this project is to transform raw, inconsistent, and unreliable e-commerce data into a **clean, standardized, and analysis-ready dataset** using SQL.

The cleaning strategy focuses on **repeatable, scalable, and logically consistent transformations** rather than one-off fixes.

---

## 🔍 Overall Approach

The cleaning process follows a structured pipeline:

1. **Understand the data**
2. **Identify inconsistencies and anomalies**
3. **Standardize formats**
4. **Fix invalid values**
5. **Normalize categorical data**
6. **Convert data types**
7. **Ensure data integrity**

Each table is cleaned independently while maintaining relational consistency.

---

## 🧩 Core Cleaning Principles

### 1. Idempotent Transformations

All cleaning queries are written such that:

* Running them multiple times does not corrupt data
* Results remain consistent

Example:

```sql
UPDATE raw_reviews
SET helpful_votes = ABS(helpful_votes)
WHERE helpful_votes < 0;
```

---

### 2. Minimal Data Loss

* Records are only deleted when absolutely invalid (e.g., impossible age)
* Prefer correction over deletion

Example:

* Age < 10 or > 100 → removed
* Negative values → corrected using `ABS()`

---

### 3. Standardization First, Then Transformation

Before applying logic:

* Trim spaces
* Normalize casing

This avoids fragmented categories.

---

## 🧹 Table-wise Cleaning Strategy

---

## 👤 Customers Table

### Problems Identified

* Names in inconsistent formats
* Emails with casing and spacing issues
* Phone numbers in multiple formats
* Invalid ages
* Inconsistent gender values

### Strategy

#### Name Cleaning

* Convert to lowercase → trim → convert to proper case

#### Email Cleaning

* Normalize using `LOWER(TRIM())`

#### Phone Formatting

* Convert into pseudo **E.164 format**
* Remove symbols like `() - spaces`

#### Age Validation

* Keep only realistic values (10–100)
* Delete invalid rows

#### Gender Normalization

* Map variations:

  * `m`, `male` → Male
  * `f`, `female` → Female
  * Others standardized or set NULL

---

## 👨‍💼 Employees Table

### Problems

* Negative salaries and IDs
* Inconsistent department names
* Mixed status values
* Dates stored as strings

### Strategy

* Numeric correction using `ABS()` and `ROUND()`
* Department normalization:

  * `hr`, `it` → uppercase
  * others → proper case
* Status standardized (e.g., `on leave` → `On Leave`)
* Date normalization:

  * Replace `/` → `-`
  * Convert using `STR_TO_DATE()`

---

## 📦 Products Table

### Problems

* Category/sub-category inconsistencies
* Mixed casing
* Special characters (`&`, `-`)

### Strategy

* Normalize casing
* Handle special cases:

  * Split and reformat `&`, `-`, and multi-word values
* Ensure consistent naming across categories

---

## 🛒 Orders Table

### Problems

* Status spelling errors
* Inconsistent city/state/country formatting
* Negative monetary values

### Strategy

#### Status Cleaning

* Fix spelling variations:

  * `procesing` → `processing`
  * `deliverd` → `delivered`

#### Location Standardization

* Normalize city/state/country names using proper casing

#### Numeric Cleaning

* Convert negative values to positive
* Round monetary values

---

## 📦 Order Items Table

### Problems

* Negative quantity, price, discount
* Invalid IDs

### Strategy

* Apply `ABS()` to all numeric fields
* Round monetary values

---

## 💳 Payments Table

### Problems

* Inconsistent payment method formatting
* Invalid transaction references
* Date format inconsistencies

### Strategy

#### Payment Method

* Normalize casing
* Convert multi-word values to proper case

#### Transaction Reference

* Ensure fixed length (12 characters)
* Trim and uppercase

#### Date Cleaning

* Normalize string format
* Convert using conditional parsing

---

## 🔁 Returns Table

### Problems

* Negative refund amounts
* Date inconsistencies
* Status formatting issues

### Strategy

* Fix numeric values using `ABS()`
* Standardize status
* Convert dates using multi-format parsing
* Remove future dates

---

## ⭐ Reviews Table

### Problems

* Negative ratings
* Invalid helpful votes
* Multiple date formats

### Strategy

* Convert negative values using `ABS()`
* Ensure ratings fall within valid range
* Normalize dates using:

  * `REGEXP`
  * `STR_TO_DATE()`
* Remove future dates

---

## 📅 Date Handling Strategy (Critical)

Across all tables, date columns were:

### Step 1: Normalize Strings

* Replace `/` → `-`
* Remove extra spaces

### Step 2: Identify Format Using REGEXP

Handled formats:

* `YYYY-MM-DD`
* `YYYY-DD-MM`
* `DD-MM-YYYY`
* `MM-DD-YYYY`
* `DD-MMM-YYYY`

### Step 3: Convert Using STR_TO_DATE

Conditional parsing applied to ensure correct interpretation.

### Step 4: Validate Dates

* Remove future dates
* Set invalid conversions to NULL

---

## 🔗 Data Integrity Considerations

* Maintained relationships between tables
* Avoided breaking joins (order_id, customer_id, etc.)
* Cleaned orphan references where necessary

---

## ⚖️ Trade-offs Made

| Decision                       | Reason                                       |
| ------------------------------ | -------------------------------------------- |
| Deleted invalid ages           | Cannot be reliably corrected                 |
| Used ABS() for negatives       | Assumed sign error rather than real negative |
| Set unknown categories to NULL | Avoid incorrect assumptions                  |

---

## 🚀 Outcome

After cleaning:

* Data is **consistent and standardized**
* Ready for:

  * Analysis
  * Dashboarding
  * Feature engineering
  * Machine learning

---

## 📌 Key Takeaways

* Real-world data is messy and inconsistent
* Cleaning requires both **logic + assumptions**
* SQL is powerful enough for complex data transformation
* Proper structuring makes pipelines reusable

---

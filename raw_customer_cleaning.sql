USE ecommerce_dirty;

SELECT * FROM raw_customers;
/* Observations - Multiple non-uniform formats in full_name, phone, city, state, gender, signup_date, loyalty tier - and all names should be unique */

SELECT customer_id, COUNT(*) AS 'total_count' FROM raw_customers GROUP BY customer_id ORDER BY total_count DESC; -- all unique customer_id entry
# Cleaning the column full_name
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET full_name = 
CONCAT(
       CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 1, 1)), LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 2))),
       ' ',
       CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 1, 1)), LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 2))));
SET SQL_SAFE_UPDATES = 1;

SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET full_name = REPLACE(full_name, ',', '');
SET SQL_SAFE_UPDATES = 1;

# Cleaning the column email
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET email = LOWER(TRIM(email));
SET SQL_SAFE_UPDATES = 1;

# Cleaning the column phone 
-- using the E.164 international format (e.g., +15551234567) (+[country_code][phone_number])
SELECT phone, LENGTH(phone) FROM raw_customers WHERE LENGTH(phone) < 10 or LENGTH(phone) > 15; -- no data entry discrepency
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET phone = CONCAT('+', REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(phone), '(', ')'), ')','+'), '+', '-'), '-', ' '), ' ', ''));
SET SQL_SAFE_UPDATES = 1;

# cleaning the column city
SELECT COUNT(*) AS 'total_count', state FROM raw_customers GROUP BY state ORDER BY total_count;
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET state = 
    CASE 
        -- USA
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

        -- Australia
        WHEN country = 'Australia' AND state = 'NSW' THEN 'New South Wales'
        WHEN country = 'Australia' AND state = 'VIC' THEN 'Victoria'

        -- Germany
        WHEN country = 'Germany' AND state = 'Bavaria' THEN 'Bavaria'
        WHEN country = 'Germany' AND state = 'Berlin' THEN 'Berlin'

        -- UK
        WHEN country = 'UK' AND state = 'England' THEN 'England'

        ELSE state
    END;
SET SQL_SAFE_UPDATES = 1;

# Cleaning the column state
SELECT COUNT(*) AS 'total_count', city FROM raw_customers GROUP BY city ORDER BY total_count; # Minor formatting changes
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers SET city = 'Seattle' WHERE city = 'SEATTLE';
SET SQL_SAFE_UPDATES = 1;

# Cleaning the column country
SELECT COUNT(*) AS 'total_count', country FROM raw_customers GROUP BY country ORDER BY total_count; # no problem with country column
-- one problem - while extracting lower case entry of UK and USA, i am getting none valid values. but while exploring manually i am seeing the data discrepency.

SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET country =
    CASE
        WHEN country IN ('USA', 'U.S.A', 'UNITED STATES', 'usa') THEN 'USA'
        WHEN country IN ('UK', 'U.K', 'UNITED KINGDOM', 'uk') THEN 'UK'
        ELSE country
    END;
SET SQL_SAFE_UPDATES = 1;

# Clenaing the column age
# Considering the age bracket b/w 10 to 100. 
SELECT COUNT(*) AS 'total_count', age FROM raw_customers GROUP BY age ORDER BY total_count;
SELECT * FROM raw_customers WHERE age IS NULL;

SET SQL_SAFE_UPDATES = 0;
DELETE FROM raw_customers WHERE age NOT BETWEEN 10 and 100;
SET SQL_SAFE_UPDATES = 1;

# Clenaing the column gender
SELECT COUNT(*) AS 'total_count', gender FROM raw_customers GROUP BY gender ORDER BY total_count; 
SELECT * FROM raw_customers WHERE gender = '' LIMIT 10;
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET gender = 
    CASE 
        WHEN UPPER(TRIM(gender)) IN ('MALE', 'M') THEN 'Male'
        WHEN UPPER(TRIM(gender)) IN ('FEMALE', 'F') THEN 'Female'
        WHEN UPPER(TRIM(gender)) = 'PREFER NOT TO SAY' THEN 'Prefer not to say'
        WHEN UPPER(TRIM(gender)) = 'NON-BINARY' THEN 'Non-Binary'
        ELSE NULL
    END;
SET SQL_SAFE_UPDATES = 1;

# Cleaning the column signup_date
-- ISO 8601 standard, is YYYY-MM-DD
-- Deciding to go with DD-MM-YYYY interpretation for any ambigious data
SELECT COUNT(*) AS 'total_count', signup_date FROM raw_customers GROUP BY signup_date ORDER BY total_count DESC; # Count all null values
SELECT * FROM raw_customers WHERE signup_date = '31-Mar-2018';
/*
Dates format 4 types 
1. YYYY-MM-DD    -- no problem for conversion
2. DD-month-YYYY -- safe conversion no problem
3. MM-DD-YYYY    -- considering this format for ambigious data with -XX-, XX>12 
4. DD-MM-YYYY    -- for all other dates
*/
SELECT * FROM raw_customers;

ALTER TABLE raw_customers ADD COLUMN dates2 DATE;
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET signup_date = REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '');

/*
WHEN signup_date = signup_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND SUBSTRING(signup_date, 6,7) > 12 THEN STR_TO_DATE(signup_date, '%Y-%d-%m')
WHEN signup_date = signup_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' AND SUBSTRING(signup_date, 4,5) < 12 THEN STR_TO_DATE(signup_date, '%d-%m-%Y')
WHEN signup_date = signup_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' AND SUBSTRING(signup_date, 4,5) > 12 THEN STR_TO_DATE(signup_date, '%m-%d-%y')
*/

UPDATE raw_customers
SET dates2 = 
CASE 
    WHEN signup_date = signup_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND SUBSTRING(signup_date, 6,7) < 12 THEN STR_TO_DATE(signup_date, '%Y-%m-%d') = dates2
    ELSE dates2
END;
ALTER TABLE raw_customers DROP COLUMN dates;
ALTER TABLE raw_customers DROP COLUMN dates2;

SELECT 
TRIM(signup_date) AS dates,
REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '')
FROM raw_customers
WHERE REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '') REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';

SELECT 
STR_TO_DATE(t.Final_dates, '%m-%d-%Y'),
t.Final_dates
FROM
    (SELECT 
     TRIM(signup_date) AS dates,
     REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '') AS Final_dates
     FROM raw_customers
     WHERE 
          REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '') REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' 
          AND 
          SUBSTRING(REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', ''), 4,5) > 12) AS t;

SELECT 
     TRIM(signup_date) AS dates,
     REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '') AS Final_dates
     FROM raw_customers
     WHERE 
          REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', '') REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' 
          AND 
          SUBSTRING(REPLACE(REPLACE(TRIM(signup_date), '/', '-'), ' ', ''), 4,5) > 12;
SELECT * FROM raw_customers;


# Cleaning the column loyalty_tier
SELECT COUNT(*) AS 'total_count', loyalty_tier FROM raw_customers GROUP BY loyalty_tier ORDER BY total_count; -- Count all null values
SET SQL_SAFE_UPDATES = 0;
UPDATE raw_customers
SET loyalty_tier = 
    CASE 
        WHEN UPPER(TRIM(loyalty_tier)) IN ('PLATINUM', 'PLATIMUM') THEN 'Platinum'
        WHEN UPPER(TRIM(loyalty_tier)) = 'DIAMOND' THEN 'Diamond'
        WHEN UPPER(TRIM(loyalty_tier)) = 'GOLD' THEN 'Gold'
        WHEN UPPER(TRIM(loyalty_tier)) = 'SILVER' THEN 'Silver'
        WHEN UPPER(TRIM(loyalty_tier)) = 'BRONZE' THEN 'Bronze'
        ELSE NULL
    END;
SET SQL_SAFE_UPDATES = 1;
                    
# Clenaing the column referral_source 
SELECT COUNT(*) AS 'total_count', referral_source FROM raw_customers GROUP BY referral_source ORDER BY total_count; 
# Requires no cleaning
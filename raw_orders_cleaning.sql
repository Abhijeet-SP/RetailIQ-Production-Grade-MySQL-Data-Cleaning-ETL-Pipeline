USE ecommerce_dirty;
SHOW FULL COLUMNS FROM raw_orders; # all case insensitive
SHOW TABLE STATUS LIKE 'raw_orders'; # 20092 rows
SELECT @@collation_database;
SELECT @@collation_server;
SELECT * FROM raw_orders;

SET SQL_SAFE_UPDATES = 0;

# cleaning the dates


# cleaning the column shipping_city
SELECT DISTINCT shipping_city, shipping_state,shipping_country COLLATE utf8mb4_bin FROM raw_orders; -- need small fix 
UPDATE raw_orders
SET shipping_city = 'Houston' WHERE shipping_city = 'HOUSTON';

# cleaning the column shipping_state
SELECT DISTINCT shipping_state, shipping_country COLLATE utf8mb4_bin FROM raw_orders;
UPDATE raw_orders
SET shipping_state =
CASE 

        -- USA
        WHEN shipping_country = 'USA' AND shipping_state = 'NY' THEN 'New York'
        WHEN shipping_country = 'USA' AND shipping_state = 'FL' THEN 'Florida'
        WHEN shipping_country = 'USA' AND shipping_state = 'MN' THEN 'Minnesota'
        WHEN shipping_country = 'USA' AND shipping_state = 'TN' THEN 'Tennessee'
        WHEN shipping_country = 'USA' AND shipping_state = 'TX' THEN 'Texas'
        WHEN shipping_country = 'USA' AND shipping_state = 'GA' THEN 'Georgia'
        WHEN shipping_country = 'USA' AND shipping_state = 'CA' THEN 'California'
        WHEN shipping_country = 'USA' AND shipping_state = 'OR' THEN 'Oregon'
        WHEN shipping_country = 'USA' AND shipping_state = 'AZ' THEN 'Arizona'
        WHEN shipping_country = 'USA' AND shipping_state = 'MA' THEN 'Massachusetts'
        WHEN shipping_country = 'USA' AND shipping_state = 'WA' THEN 'Washington'
        WHEN shipping_country = 'USA' AND shipping_state = 'PA' THEN 'Pennsylvania'
        WHEN shipping_country = 'USA' AND shipping_state = 'CO' THEN 'Colorado'
        WHEN shipping_country = 'USA' AND shipping_state = 'IL' THEN 'Illinois'

        -- Canada
        WHEN shipping_country = 'Canada' AND shipping_state = 'ON' THEN 'Ontario'
        WHEN shipping_country = 'Canada' AND shipping_state = 'QC' THEN 'Quebec'
        WHEN shipping_country = 'Canada' AND shipping_state = 'BC' THEN 'British Columbia'

        -- Australia
        WHEN shipping_country = 'Australia' AND shipping_state = 'VIC' THEN 'Victoria'
        WHEN shipping_country = 'Australia' AND shipping_state = 'NSW' THEN 'New South Wales'

        -- UK
        WHEN shipping_country = 'UK' AND shipping_state = 'England' THEN 'England'

        -- Germany
        WHEN shipping_country = 'Germany' AND shipping_state = 'Berlin' THEN 'Berlin'
        WHEN shipping_country = 'Germany' AND shipping_state = 'Bavaria' THEN 'Bavaria'

        ELSE shipping_state

END;

# cleaning the column shipping_country
SELECT DISTINCT shipping_country COLLATE utf8mb4_bin FROM raw_orders;
UPDATE raw_orders
SET shipping_country =
    CASE
        WHEN shipping_country IN ('USA', 'usa', 'Usa') THEN 'USA'
        WHEN shipping_country IN ('UK', 'uk', 'Uk') THEN 'UK'
        WHEN shipping_country IN ('Australia', 'australia', 'AUSTRALIA') THEN 'Australia'
        WHEN shipping_country IN ('Canada', 'CANADA', 'canada') THEN 'Canada'
        ELSE 'Germany'
    END;

# cleaning the columns total_amount and discount_pct
UPDATE raw_orders
SET total_amount = ROUND(ABS(total_amount), 2),
    discount_pct = ROUND(ABS(discount_pct), 2);

SET SQL_SAFE_UPDATES = 1;
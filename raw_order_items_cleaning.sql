USE ecommerce_dirty;
SHOW FULL COLUMNS FROM raw_order_items; # all numeric columns
SHOW TABLE STATUS LIKE 'raw_order_items'; # rows 25460
SELECT @@collation_database;
SELECT @@collation_server;
SELECT * FROM raw_order_items;

SET SQL_SAFE_UPDATES = 0;

UPDATE raw_order_items
SET unit_price = ROUND(ABS(unit_price), 2),
    discount = ROUND(ABS(discount), 2);

SET SQL_SAFE_UPDATES = 1;
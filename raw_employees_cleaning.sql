USE ecommerce_dirty;
SHOW FULL COLUMNS FROM raw_employees;
SHOW TABLE STATUS LIKE 'raw_employees';
SELECT @@collation_database;
SELECT @@collation_server;
SELECT * FROM raw_employees;

SET SQL_SAFE_UPDATES = 0;
# Cleaning the column full_name
UPDATE raw_employees
SET full_name = 
CONCAT(
       CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 1, 1)), LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', 1), 2))),
       ' ',
       CONCAT(UPPER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 1, 1)), LOWER(SUBSTRING(SUBSTRING_INDEX(TRIM(full_name), ' ', -1), 2))));

# Cleaning the column email
UPDATE raw_employees
SET email = LOWER(TRIM(email));

# Cleaning the column department
SELECT DISTINCT department COLLATE utf8mb4_bin FROM raw_employees;
UPDATE raw_employees
SET department = TRIM(department);

UPDATE raw_employees
SET department =
    CASE
        WHEN department IN ('hr', 'Hr', 'hR') THEN 'HR'
        WHEN department IN ('it', 'It', 'iT') THEN 'IT'
        WHEN department = 'logistics' THEN 'Logistics'
        WHEN department = 'marketing' THEN 'Marketing'
        WHEN department = 'operations' THEN 'Operations'
        WHEN department = 'sales' THEN 'Sales'
        WHEN department = 'finance' THEN 'Finance'
        WHEN department IN ('Customer Support', 'Customer support', 'customer support', 'customersupport') THEN 'Customer Support'
        ELSE department
    END;

# cleaning the column salary 
UPDATE raw_employees
SET salary = ROUND(ABS(salary), 2);

# cleaning the column status
SELECT DISTINCT status COLLATE utf8mb4_bin FROM raw_employees;
/* ALTER TABLE raw_employees MODIFY status VARCHAR(50) COLLATE utf8mb4_bin; */ -- For permanent changes 

UPDATE raw_employees
SET status = 
CASE 
     WHEN status IN ('active', 'Active', 'ACTIVE', 'inactive', 'Inactive', 'terminated', 'Terminated' ) 
         THEN CONCAT(SUBSTRING(UPPER(status), 1,1), SUBSTRING(LOWER(status), 2))
     WHEN status IN ('On Leave','on leave') THEN 'On Leave'
     ELSE status
END;

SELECT * FROM ecommerce_dirty.raw_employees;

# cleaning the column hire_date

SET SQL_SAFE_UPDATES = 1;


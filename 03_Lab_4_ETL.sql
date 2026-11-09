// Optional: Check that dim and fact tables are empty
//SELECT * FROM fact_sales;
//SELECT * FROM fact_returns;
//SELECT * FROM dim_promotion;
//SELECT * FROM dim_store;
//SELECT * FROM dim_product;
//SELECT * FROM dim_customer;
//SELECT * FROM dim_date;
//SELECT * FROM dim_return_reason;

//Run 01_Lab_4_DDL.sql first
//Run 02_Surrogate_Key_Generation.sql second
//Now you can run this script (03_Lab_4_ETL.sql)
//Run 04_Data_Quality_Checks.sql afterwards

alter warehouse compute_wh
set auto_suspend = 60
auto_resume = true;

use database mmis642;
use role ACCOUNTADMIN;
use schema public;

//Empty out the tables to ensure no data is loaded in (Full-Reload)
TRUNCATE TABLE IF EXISTS fact_sales;
TRUNCATE TABLE IF EXISTS fact_returns;
TRUNCATE TABLE IF EXISTS dim_promotion;
TRUNCATE TABLE IF EXISTS dim_store;
TRUNCATE TABLE IF EXISTS dim_product;
TRUNCATE TABLE IF EXISTS dim_customer;
TRUNCATE TABLE IF EXISTS dim_date;
TRUNCATE TABLE IF EXISTS dim_return_reason;

//Promotion_key 0 is a reserved “No_promotion” row, with promotion_id NULL. Sales without any promotion will be mapped to a promotion key of 0.
INSERT INTO dim_promotion (promotion_sk, promotion_id, promo_name, discount_pct, start_date, end_date)
SELECT 0, NULL, 'No_Promotion', 0.00, NULL, NULL

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_promotion pr
    WHERE pr.promotion_sk = 0
);

//Verify the row has been added
//SELECT * FROM dim_promotion;

//Empty the table if load result is inaccurate, remember to re-add the "No promotion" row.
//TRUNCATE TABLE IF EXISTS dim_promotion;

//Load data into dim_promotion
INSERT INTO dim_promotion (promotion_sk, promotion_id, promo_name, discount_pct, start_date, end_date)
SELECT promotion_sk_seq.NEXTVAL, pr.promotion_id, pr.promo_name, pr.discount_pct, pr.start_date, pr.end_date
FROM src_promotion pr 

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_promotion promo
    WHERE promo.promotion_id = pr.promotion_id
);

//Empty the table if load result is inaccurate
//TRUNCATE TABLE IF EXISTS dim_store;

//Load data into dim_store
INSERT INTO dim_store (store_sk, store_id, store_name, city, state, region, channel)
SELECT store_sk_seq.NEXTVAL, st.store_id, st.store_name, st.city, st.state, st.region, st.channel
FROM src_store st 

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_store s
    WHERE s.store_id = st.store_id
);

//Empty the table if load result is inaccurate
//TRUNCATE TABLE IF EXISTS dim_product;

// Load Data into dim_product
INSERT INTO dim_product (product_sk, product_id, product_name, category_name, department, brand, unit_cost, list_price)
SELECT product_sk_seq.NEXTVAL, p.product_id, p.product_name, c.category_name, c.department, p.brand, p.unit_cost, p.list_price

FROM src_product p

JOIN src_category c 
ON p.category_id = c.category_id

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_product prod
    WHERE prod.product_id = p.product_id
);

//Empty the table if load result is inaccurate
//TRUNCATE TABLE IF EXISTS dim_customer;

//Load the initial version from src_customer.csv into dim_customer
INSERT INTO dim_customer (customer_sk, customer_id, first_name, last_name, email, city, 
state, region, segment, signup_date, effective_date, expiration_date, is_current)

SELECT customer_sk_seq.NEXTVAL, c.customer_id, c.first_name, c.last_name, c.email, c.city, 
c.state, c.region, c.segment, c.signup_date, c.signup_date as effective_date,

COALESCE (
DATEADD (day, -1, updates.expire_date_change),
        DATE '9999-12-31'
        ) AS expiration_date,
CASE
    WHEN updates.expire_date_change is NULL
        THEN TRUE
    ELSE FALSE
END AS is_current

FROM src_customer c

LEFT JOIN ( 
SELECT customer_id, MIN(change_date) AS expire_date_change
    FROM src_customer_updates cu
    GROUP BY customer_id
) UPDATES
    ON c.customer_id = updates.customer_id

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_customer d
    WHERE d.customer_id = c.customer_id
    AND d.effective_date = c.signup_date
);

//then process src_customer_updates.csv to create new versions with effective_date, expiration_date, and is_current.
INSERT INTO dim_customer (customer_sk, customer_id, first_name, last_name, email, city, 
state, region, segment, signup_date, effective_date, expiration_date, is_current)

WITH UPDATES AS ( 
SELECT cu.customer_id, cu.first_name, cu.last_name, cu.email, cu.city, cu.state, 
cu.region, cu.segment, c.signup_date, cu.change_date AS effective_date
FROM src_customer_updates cu
JOIN src_customer c
ON cu.customer_id = c.customer_id
),

ordered_updates AS (
SELECT *,
    LEAD(effective_date) OVER (
    PARTITION BY customer_id
    ORDER BY effective_date
    ) AS next_effective_date
FROM UPDATES
) 

SELECT customer_sk_seq.NEXTVAL, customer_id, first_name, last_name, email, city, 
state, region, segment, signup_date, effective_date, 

COALESCE (
DATEADD (day, -1, next_effective_date),
        DATE '9999-12-31'
        ) AS expiration_date,
        
CASE
    WHEN next_effective_date is NULL
        THEN TRUE
    ELSE FALSE
END AS is_current

FROM ordered_updates ou

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_customer d
    WHERE d.customer_id = ou.customer_id
    AND d.effective_date = ou.effective_date
);

-- 1. Expire current rows whose tracked attributes changed
UPDATE dim_customer d
SET expiration_date = DATEADD(day, -1, cu.change_date),
is_current = FALSE

FROM src_customer_updates cu

WHERE d.customer_id = cu.customer_id
AND d.is_current
AND (d.first_name IS DISTINCT FROM cu.first_name OR 
d.last_name IS DISTINCT FROM cu.last_name OR 
d.email IS DISTINCT FROM cu.email OR 
d.city IS DISTINCT FROM cu.city OR 
d.state IS DISTINCT FROM cu.state OR 
d.region IS DISTINCT FROM cu.region OR
d.segment IS DISTINCT FROM cu.segment
);

-- 2. Insert a new current version (new surrogate key)
INSERT INTO dim_customer (customer_sk, customer_id, first_name, last_name, email, city,
state, region, segment, signup_date, effective_date, expiration_date, is_current)

SELECT customer_sk_seq.NEXTVAL, cu.customer_id, cu.first_name, cu.last_name, cu.email, cu.city, cu.state, cu.region, cu.segment, c.signup_date, cu.change_date,
DATE '9999-12-31', TRUE

FROM src_customer_updates cu

JOIN src_customer c
ON cu.customer_id = c.customer_id

WHERE NOT EXISTS (
SELECT 1 FROM dim_customer d
WHERE d.customer_id = cu.customer_id
AND d.is_current
);

//Verify dim_customer has inserted rows from src_custoemr updates
//SELECT *
//FROM dim_customer
//ORDER BY customer_id, effective_date;

//SCD Type 2 example from dim_customer
//SELECT *
//FROM dim_customer
//WHERE customer_id = (
    //SELECT customer_id
   // FROM dim_customer
   // GROUP BY customer_id
   // HAVING COUNT(*) = 2
   // LIMIT 1
//)
//ORDER BY effective_date;

//Empty the table if load result is inaccurate
//TRUNCATE TABLE IF EXISTS dim_date;

//Load data into dim_date
INSERT INTO dim_date
SELECT
   TO_NUMBER(TO_CHAR(d,'YYYYMMDD'))            AS date_key,
   d                                           AS full_date,
   DAYNAME(d)                                  AS day_of_week,
   MONTH(d)                                    AS month_no,
   MONTHNAME(d)                                AS month_name,
   QUARTER(d)                                  AS quarter,
   YEAR(d)                                     AS year,
   (DAYOFWEEKISO(d) >= 6)                      AS is_weekend
 FROM (
   SELECT DATEADD(day, SEQ4(), DATE '2023-01-01') AS d
   FROM TABLE(GENERATOR(ROWCOUNT => 1096))
 )

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_date d
    WHERE d.date_key = TO_NUMBER(TO_CHAR(d, 'YYYYMMDD'))
);

//Empty the table if load result is inaccurate
//TRUNCATE TABLE IF EXISTS dim_return_reason;

//Load data into dim_return_reason
INSERT INTO dim_return_reason (reason_sk, reason)
SELECT return_reason_sk_seq.NEXTVAL, reason

FROM (
SELECT DISTINCT reason FROM src_return r
) r

WHERE NOT EXISTS (
    SELECT 1
    FROM dim_return_reason drr
    WHERE drr.reason = r.reason
);

//Empty the table if load result is inaccurate
TRUNCATE TABLE IF EXISTS fact_sales;

//Load data into fact_sales
INSERT INTO fact_sales (sales_sk, date_key, customer_key,
product_key, store_key, promotion_key, order_id, line_no,
quantity, sales_amount, extended_sales, extended_cost, margin_amount)

SELECT fact_sales_sk_seq.NEXTVAL, d.date_key, c.customer_sk, p.product_sk, s.store_sk,
COALESCE(dpr.promotion_sk, 0),
oi.order_id, oi.line_no, oi.quantity, oi.unit_price AS sales_amount, 
oi.quantity * oi.unit_price AS extended_sales, oi.quantity * p.unit_cost AS extended_cost, 
(oi.quantity * oi.unit_price) - (oi.quantity * p.unit_cost) AS margin_amount

FROM src_order_item oi

JOIN src_orders o 
ON o.order_id = oi.order_id

JOIN dim_date d 
ON d.full_date = TO_DATE(o.order_ts)

JOIN dim_customer c 
ON c.customer_id = o.customer_id
AND TO_DATE(o.order_ts) BETWEEN c.effective_date AND c.expiration_date

JOIN dim_product p 
ON p.product_id = oi.product_id
JOIN dim_store s ON s.store_id = o.store_id

LEFT JOIN dim_promotion dpr
ON dpr.promotion_id = oi.promotion_id

WHERE NOT EXISTS (
    SELECT 1
    FROM fact_sales fs
    WHERE fs.order_id = oi.order_id
    AND fs.line_no = oi.line_no
);

// fact_sales should return 119352
//SELECT COUNT(*)
//FROM fact_sales;

//Empty the table if load result is inaccurate
//TRUNCATE TABLE IF EXISTS fact_returns;

//Load into fact_returns
INSERT INTO fact_returns (return_sk, return_id, product_key, customer_key,
order_key, line_no, reason, return_qty, return_ts, return_date_key)

SELECT fact_returns_sk_seq.NEXTVAL, r.return_id, p.product_sk, c.customer_sk, oi.order_id, 
oi.line_no, drr.reason_sk, r.return_qty, r.return_ts, d.date_key AS return_date_key

FROM src_return r

JOIN src_orders o 
ON o.order_id = r.order_id

JOIN src_order_item oi 
ON oi.order_id = r.order_id
AND oi.line_no = r.line_no

JOIN dim_date d 
ON d.full_date = TO_DATE(r.return_ts)

JOIN dim_customer c 
ON c.customer_id = o.customer_id
AND TO_DATE(o.order_ts) BETWEEN c.effective_date AND c.expiration_date

JOIN dim_product p 
ON p.product_id = oi.product_id

JOIN dim_return_reason drr 
ON drr.reason = r.reason

WHERE NOT EXISTS (
    SELECT 1
    FROM fact_returns fr
    WHERE fr.order_key = oi.order_id
    AND fr.line_no = oi.line_no
);

//VERIFICATION of fact_sales
//SELECT COUNT(*) AS total_sales
//FROM fact_sales;

//SELECT COUNT(*) AS missing_customer_keys
//FROM fact_sales
//WHERE customer_key IS NULL;

-- SELECT COUNT(*) AS incorrect_customer_matches
-- FROM fact_sales f
-- JOIN src_orders o
--     ON f.order_id = o.order_id
-- JOIN dim_customer c
--     ON f.customer_key = c.customer_sk
-- WHERE TO_DATE(o.order_ts) NOT BETWEEN
--       c.effective_date AND c.expiration_date;

--       SELECT
--     COUNT(*) AS total_rows,
--     COUNT(date_key) AS date_keys,
--     COUNT(customer_key) AS customer_keys,
--     COUNT(product_key) AS product_keys,
--     COUNT(store_key) AS store_keys
-- FROM fact_sales;

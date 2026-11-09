alter warehouse compute_wh
set auto_suspend = 60
auto_resume = true;

use database mmis642;
use role ACCOUNTADMIN;
use schema public;

//Drops tables to avoid double creation
DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS fact_returns;
DROP TABLE IF EXISTS dim_promotion;
DROP TABLE IF EXISTS dim_store;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_return_reason;

//DDL Table definitions and creation
CREATE TABLE dim_date (
  date_key      INTEGER PRIMARY KEY,      -- yyyymmdd
  full_date     DATE,
  day_of_week   VARCHAR(10),
  month_no      INTEGER,
  month_name    VARCHAR(10),
  quarter       INTEGER,
  year          INTEGER,
  is_weekend    BOOLEAN
);

CREATE TABLE dim_customer (               -- SCD Type 2
  customer_sk     INTEGER PRIMARY KEY,    -- surrogate key
  customer_id     INTEGER,                -- natural / business key
  first_name      VARCHAR(60),
  last_name       VARCHAR(60),
  email           VARCHAR(120),
  city            VARCHAR(80),
  state           VARCHAR(40),
  region          VARCHAR(40),
  segment         VARCHAR(40),
  signup_date     DATE,
  effective_date  DATE,
  expiration_date DATE,
  is_current      BOOLEAN
);

CREATE TABLE dim_product (
  product_sk    INTEGER PRIMARY KEY,
  product_id    INTEGER,
  product_name  VARCHAR(120),
  category_name VARCHAR(80),
  department    VARCHAR(80),
  brand         VARCHAR(80),
  unit_cost     DECIMAL(12,2),
  list_price    DECIMAL(12,2)
);

CREATE TABLE dim_store (
  store_sk      INTEGER PRIMARY KEY,
  store_id      INTEGER,
  store_name    VARCHAR(80),
  city          VARCHAR(80),
  state         VARCHAR(40),
  region        VARCHAR(40),
  channel       VARCHAR(20)
);

CREATE TABLE dim_promotion (
  promotion_sk  INTEGER PRIMARY KEY,
  promotion_id  INTEGER,
  promo_name    VARCHAR(80),
  discount_pct  DECIMAL(5,2),
  start_date    DATE,
  end_date      DATE
);

CREATE TABLE dim_return_reason (
    reason_sk INTEGER PRIMARY KEY,
    reason VARCHAR(80)
);

CREATE TABLE fact_sales (                 -- grain: one row per order line item
  sales_sk       BIGINT PRIMARY KEY,
  date_key       INTEGER,
  customer_key   INTEGER,
  product_key    INTEGER,
  store_key      INTEGER,
  promotion_key  INTEGER,
  order_id       INTEGER,                 -- degenerate dimension
  line_no        INTEGER,                 
  quantity       INTEGER,
  sales_amount   DECIMAL(12,2),
  extended_sales DECIMAL(12,2),           -- quantity * unit_price
  extended_cost  DECIMAL(12,2),           -- quantity * unit_cost
  margin_amount  DECIMAL(12,2)            -- extended_sales - extended_cost
);

CREATE TABLE fact_returns (
    return_sk BIGINT PRIMARY KEY,
    return_id INTEGER,                    --natural / business key
    product_key INTEGER,
    customer_key INTEGER,
    order_key INTEGER,
    line_no INTEGER,
    reason VARCHAR(80),
    return_qty INTEGER,
    return_ts DATE,
    return_date_key INTEGER
);

-- Add foreign keys after loading if your engine enforces them and you
-- want the constraint (Snowflake does not enforce FKs):
-- ALTER TABLE fact_sales ADD FOREIGN KEY (date_key)     REFERENCES dim_date(date_key);
-- ALTER TABLE fact_sales ADD FOREIGN KEY (customer_sk)  REFERENCES dim_customer(customer_sk);
-- ALTER TABLE fact_sales ADD FOREIGN KEY (product_sk)   REFERENCES dim_product(product_sk);
-- ALTER TABLE fact_sales ADD FOREIGN KEY (store_sk)     REFERENCES dim_store(store_sk);
-- ALTER TABLE fact_sales ADD FOREIGN KEY (promotion_sk) REFERENCES dim_promotion(promotion_sk);
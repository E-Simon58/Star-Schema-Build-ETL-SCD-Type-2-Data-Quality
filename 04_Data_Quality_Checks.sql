alter warehouse wh_name
set auto_suspend = 60
auto_resume = true;

use database db_name;
use role ACCOUNTADMIN;
use schema schema_name;

// Row count + Populated table checks per table to be used before/after loading
SELECT 'dim_customer' AS table_name, COUNT(*) AS row_count
FROM dim_customer
UNION ALL

SELECT 'dim_product', COUNT(*) FROM dim_product
UNION ALL

SELECT 'dim_store', COUNT(*) FROM dim_store
UNION ALL

SELECT 'dim_promotion', COUNT(*) FROM dim_promotion
UNION ALL

SELECT 'dim_date', COUNT(*) FROM dim_date
UNION ALL

SELECT 'dim_return_reason', COUNT(*) FROM dim_return_reason
UNION ALL

SELECT 'fact_sales', COUNT(*)FROM fact_sales
UNION ALL

SELECT 'fact_returns', COUNT(*) FROM fact_returns;

SELECT * FROM dim_customer;
SELECT * FROM dim_date;
SELECT * FROM dim_product;
SELECT * FROM dim_return_reason;
SELECT * FROM dim_store;
SELECT * FROM dim_promotion;
SELECT * FROM fact_sales;
SELECT * FROM fact_returns;

//SCD Type 2 Demonstration with One Customer showing the old and new record
SELECT * FROM dim_customer
WHERE customer_id = (
    SELECT customer_id
    FROM dim_customer
    GROUP BY customer_id
    HAVING COUNT(*) = 2
    LIMIT 1
)
ORDER BY effective_date;

//Run at least four data-quality checks: 
//1. row-count reconciliation (source vs. fact)
SELECT 
'Sales' AS fact_row_count_reconciliation, source_row_count, fact_row_count, source_row_count - fact_row_count AS difference

FROM (
    SELECT
        (SELECT COUNT(*) FROM src_order_item) AS source_row_count,
        (SELECT COUNT(*) FROM fact_sales) AS fact_row_count
)

UNION ALL

SELECT
'Returns', source_row_count, fact_row_count, source_row_count - fact_row_count as difference
FROM (
    SELECT
        (SELECT COUNT(*) FROM src_return) AS source_row_count,
        (SELECT COUNT(*) FROM fact_returns) AS fact_row_count
);

//2. null checks on fact table keys
SELECT
    COUNT_IF(sales_sk IS NULL) AS null_sales_sks,
    COUNT_IF(date_key IS NULL) AS null_date_keys,
    COUNT_IF(customer_key IS NULL) AS null_customer_keys,
    COUNT_IF(product_key IS NULL) AS null_product_keys,
    COUNT_IF(store_key IS NULL) AS null_store_keys,
    COUNT_IF(promotion_key IS NULL) AS null_promotion_keys,
    COUNT_IF(order_id IS NULL) AS null_order_ids,
    COUNT_IF(line_no IS NULL) AS null_line_nos,
    COUNT_IF(quantity IS NULL) AS null_quantity,
    COUNT_IF(sales_amount IS NULL) AS null_sales_amounts,
    COUNT_IF(extended_sales IS NULL) AS null_extended_sales,
    COUNT_IF(extended_cost IS NULL) AS null_extended_cost,
    COUNT_IF(sales_amount IS NULL) AS null_sales_amount
FROM fact_sales;

SELECT
    COUNT_IF(return_sk IS NULL) AS null_return_sks,
    COUNT_IF(return_id IS NULL) AS null_return_ids,
    COUNT_IF(product_key IS NULL) AS null_product_keys,
    COUNT_IF(customer_key IS NULL) AS null_customer_keys,
    COUNT_IF(order_key IS NULL) AS null_order_keys,
    COUNT_IF(line_no IS NULL) AS null_line_nos,
    COUNT_IF(reason IS NULL) AS null_reasons,
    COUNT_IF(return_qty IS NULL) AS null_return_qtys,
    COUNT_IF(return_ts IS NULL) AS null_return_ts,
    COUNT_IF(return_date_key IS NULL) AS null_return_date_keys
FROM fact_returns;

//3. referential integrity (no orphan keys) 
SELECT
    (SELECT COUNT(*)
     FROM fact_sales fs
     LEFT JOIN dim_date d ON fs.date_key = d.date_key
     WHERE d.date_key IS NULL) AS orphan_date_keys,

    (SELECT COUNT(*)
     FROM fact_sales fs
     LEFT JOIN dim_customer c ON fs.customer_key = c.customer_sk
     WHERE c.customer_sk IS NULL) AS orphan_customer_keys,

    (SELECT COUNT(*)
     FROM fact_sales fs
     LEFT JOIN dim_product p ON fs.product_key = p.product_sk
     WHERE p.product_sk IS NULL) AS orphan_product_keys,

    (SELECT COUNT(*)
     FROM fact_sales fs
     LEFT JOIN dim_store s ON fs.store_key = s.store_sk
     WHERE s.store_sk IS NULL) AS orphan_store_keys,

    (SELECT COUNT(*)
     FROM fact_sales fs
     LEFT JOIN dim_promotion pr ON fs.promotion_key = pr.promotion_sk
     WHERE pr.promotion_sk IS NULL) AS orphan_promotion_keys;

SELECT
    (SELECT COUNT(*)
     FROM fact_returns fr
     LEFT JOIN dim_date d ON fr.return_date_key = d.date_key
     WHERE d.date_key IS NULL) AS orphan_return_date_keys,

    (SELECT COUNT(*)
     FROM fact_returns fr
     LEFT JOIN dim_customer c ON fr.customer_key = c.customer_sk
     WHERE c.customer_sk IS NULL) AS orphan_customer_keys,

    (SELECT COUNT(*)
     FROM fact_returns fr
     LEFT JOIN dim_product p ON fr.product_key = p.product_sk
     WHERE p.product_sk IS NULL) AS orphan_product_keys,

    (SELECT COUNT(*)
     FROM fact_returns fr
     LEFT JOIN dim_return_reason rr ON fr.reason = rr.reason_sk
     WHERE rr.reason_sk IS NULL) AS orphan_return_reason_keys;

//4. duplicate detection, supposed to produce no results
SELECT order_id, line_no, COUNT(*) AS duplicate_count
FROM fact_sales
GROUP BY order_id, line_no
HAVING COUNT(*) > 1;

SELECT order_key, line_no, COUNT(*) AS duplicate_count
FROM fact_returns
GROUP BY order_key, line_no
HAVING COUNT(*) > 1;

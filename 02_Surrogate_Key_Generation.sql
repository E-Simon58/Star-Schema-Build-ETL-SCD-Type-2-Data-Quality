alter warehouse compute_wh
set auto_suspend = 60
auto_resume = true;

use database mmis642;
use role ACCOUNTADMIN;
use schema public;

//Generate the dim_promotion Surrogate Key Sequence
CREATE SEQUENCE promotion_sk_seq
START = 1
INCREMENT = 1;

//Generate the dim_store Surrogate Key Sequence
CREATE SEQUENCE store_sk_seq
START = 1
INCREMENT = 1;

//Generate the dim_product Surrogate Key Sequence
CREATE SEQUENCE product_sk_seq
START = 1
INCREMENT = 1;

//Generate the dim_customer Surrogate Key Sequence
CREATE SEQUENCE customer_sk_seq
START = 1
INCREMENT = 1;

//Generate the dim_return_reason Surrogate Key Sequence
CREATE SEQUENCE return_reason_sk_seq
START = 1
INCREMENT = 1;

//Generate the fact_sales Surrogate Key Sequence
CREATE SEQUENCE fact_sales_sk_seq
START = 1
INCREMENT = 1;

//Generate the fact_returns Surrogate Key Sequence
CREATE SEQUENCE fact_returns_sk_seq
START = 1
INCREMENT = 1;
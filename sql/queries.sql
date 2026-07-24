-- ============================================================
-- Foodpanda cancellation analysis — SQL layer
-- Reproduces the EDA from analysis/foodpanda_cancellation_analysis.R
-- against the normalized schema in sql/schema.sql, as a
-- cross-check on the R pipeline (numbers should match README/R output).
-- Run: sqlite3 sql/foodpanda.db < sql/queries.sql
-- ============================================================

-- ---------- 1) Data validation ----------

-- Row counts per table
SELECT 'customers' AS table_name, COUNT(*) AS n FROM customers
UNION ALL
SELECT 'restaurants', COUNT(*) FROM restaurants
UNION ALL
SELECT 'orders', COUNT(*) FROM orders;

-- Orphaned orders: referential integrity check (should return 0 rows)
SELECT o.order_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT o.order_id
FROM orders o
LEFT JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE r.restaurant_id IS NULL;

-- Duplicate primary keys (should return 0 rows)
SELECT customer_id, COUNT(*) FROM customers GROUP BY customer_id HAVING COUNT(*) > 1;
SELECT order_id,    COUNT(*) FROM orders    GROUP BY order_id    HAVING COUNT(*) > 1;

-- Null / out-of-range checks on fields the model depends on
SELECT
    SUM(CASE WHEN price          IS NULL OR price <= 0     THEN 1 ELSE 0 END) AS bad_price,
    SUM(CASE WHEN quantity       IS NULL OR quantity <= 0  THEN 1 ELSE 0 END) AS bad_quantity,
    SUM(CASE WHEN payment_method IS NULL                   THEN 1 ELSE 0 END) AS null_payment_method,
    SUM(CASE WHEN delivery_status IS NULL                  THEN 1 ELSE 0 END) AS null_delivery_status
FROM orders;

-- Unexpected delivery_status values outside the known set
SELECT DISTINCT delivery_status
FROM orders
WHERE LOWER(delivery_status) NOT IN ('delivered', 'delayed', 'cancelled', 'canceled', 'failed', 'rejected');

-- ---------- 2) Cancellation rate by payment method (aggregation) ----------

SELECT
    payment_method,
    COUNT(*) AS n_orders,
    ROUND(AVG(CASE WHEN LOWER(delivery_status) LIKE '%cancel%'
                     OR LOWER(delivery_status) LIKE '%fail%'
                     OR LOWER(delivery_status) LIKE '%reject%'
                THEN 1.0 ELSE 0 END), 3) AS cancellation_rate
FROM orders
GROUP BY payment_method
ORDER BY cancellation_rate DESC;

-- ---------- 3) Cancellation rate by city (JOIN + aggregation, min 50 orders) ----------

SELECT
    c.city,
    COUNT(*) AS n_orders,
    ROUND(AVG(CASE WHEN LOWER(o.delivery_status) LIKE '%cancel%'
                     OR LOWER(o.delivery_status) LIKE '%fail%'
                     OR LOWER(o.delivery_status) LIKE '%reject%'
                THEN 1.0 ELSE 0 END), 3) AS cancellation_rate
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.city
HAVING COUNT(*) >= 50
ORDER BY cancellation_rate DESC;

-- ---------- 4) Cancellation rate by restaurant (JOIN + aggregation) ----------

SELECT
    r.restaurant_name,
    COUNT(*) AS n_orders,
    ROUND(AVG(CASE WHEN LOWER(o.delivery_status) LIKE '%cancel%'
                     OR LOWER(o.delivery_status) LIKE '%fail%'
                     OR LOWER(o.delivery_status) LIKE '%reject%'
                THEN 1.0 ELSE 0 END), 3) AS cancellation_rate
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
GROUP BY r.restaurant_name
ORDER BY cancellation_rate DESC;

-- ---------- 5) Price summary by cancellation outcome ----------

SELECT
    CASE WHEN LOWER(delivery_status) LIKE '%cancel%'
           OR LOWER(delivery_status) LIKE '%fail%'
           OR LOWER(delivery_status) LIKE '%reject%'
      THEN 1 ELSE 0 END AS cancelled,
    COUNT(*)            AS n,
    ROUND(AVG(price), 2) AS avg_price,
    ROUND(MIN(price), 2) AS min_price,
    ROUND(MAX(price), 2) AS max_price
FROM orders
GROUP BY cancelled;

-- ---------- 6) High-value customers x cancellation (JOIN across all 3 tables) ----------

SELECT
    c.city,
    r.restaurant_name,
    COUNT(*) AS n_orders,
    ROUND(AVG(o.price), 2) AS avg_price,
    ROUND(AVG(CASE WHEN LOWER(o.delivery_status) LIKE '%cancel%' THEN 1.0 ELSE 0 END), 3) AS cancellation_rate
FROM orders o
JOIN customers   c ON o.customer_id   = c.customer_id
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE c.loyalty_points > (SELECT AVG(loyalty_points) FROM customers)
GROUP BY c.city, r.restaurant_name
HAVING COUNT(*) >= 20
ORDER BY cancellation_rate DESC
LIMIT 15;

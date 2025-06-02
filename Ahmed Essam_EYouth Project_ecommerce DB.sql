--Identify customers with the highest number of orders + num of support sessions
/* SELECT 
    c.id AS customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    COUNT(o.id) AS total_orders
FROM customers c
JOIN orders o ON c.id = o.customer_id
GROUP BY c.id, c.first_name, c.last_name
ORDER BY total_orders DESC;*/

WITH orders_count AS (
    SELECT customer_id, COUNT(*) AS total_orders
    FROM orders
    GROUP BY customer_id
),
sessions_count AS (
    SELECT customer_id, COUNT(*) AS total_sessions
    FROM customer_sessions
    GROUP BY customer_id
)
SELECT 
    c.id AS customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    ISNULL(o.total_orders, 0) AS total_orders,
    ISNULL(s.total_sessions, 0) AS total_sessions
FROM customers c
LEFT JOIN orders_count o ON c.id = o.customer_id
LEFT JOIN sessions_count s ON c.id = s.customer_id
ORDER BY total_orders DESC;


--Generate an alert for products with stock quantities below 20 units.--> to full it again

SELECT 
    p.id AS product_id,
    p.name AS product_name,
    i.quantity
FROM products p
JOIN inventory_movements i ON p.id = i.product_id
WHERE i.quantity < 20;


--Track inventory turnover trends using a 30-day moving average. 
WITH sales_per_day AS (
    SELECT 
        oi.product_id,
        CAST(o.order_date AS DATE) AS sale_date,
        SUM(oi.quantity) AS daily_quantity
    FROM order_details oi
    JOIN orders o ON oi.order_id = o.id
    GROUP BY oi.product_id, CAST(o.order_date AS DATE)
),
moving_avg AS (
    SELECT 
        product_id,
        sale_date,
        AVG(daily_quantity) OVER (
            PARTITION BY product_id 
            ORDER BY sale_date 
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS moving_avg_30_day
    FROM sales_per_day
)
SELECT * 
FROM moving_avg
ORDER BY product_id, sale_date;


--Identify customers who have purchased every product in a specific category.
WITH category_products AS (
    SELECT id AS product_id
    FROM products
	   WHERE category_id = 10 -- Chose ur category 
),
customer_purchases AS (
    SELECT DISTINCT o.customer_id, oi.product_id
    FROM orders o
    JOIN order_details oi ON o.id = oi.order_id
    WHERE oi.product_id IN (SELECT product_id FROM category_products)
),
customer_product_count AS (
    SELECT 
        customer_id,
        COUNT(DISTINCT product_id) AS purchased_count
    FROM customer_purchases
    GROUP BY customer_id
),
total_category_products AS (
    SELECT COUNT(*) AS total_products
    FROM category_products
)
SELECT 
    cpc.customer_id
FROM customer_product_count cpc
JOIN total_category_products tcp ON cpc.purchased_count = tcp.total_products;

-- total discount for each customer 
SELECT 
    c.id AS customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    SUM(od.unit_price * od.quantity * d.percentage) AS total_discount_received
FROM customers c
JOIN orders o ON c.id = o.customer_id
JOIN order_details od ON o.id = od.order_id
JOIN products p ON od.product_id = p.id
LEFT JOIN discounts d ON d.product_id = p.id 
                     AND o.order_date BETWEEN d.start_date AND d.end_date 
                     AND d.is_active = 1
WHERE d.percentage IS NOT NULL
GROUP BY c.id, c.first_name, c.last_name
ORDER BY total_discount_received DESC;


-- Most loss-making products through discounts --> top 5

SELECT 
    p.name AS product_name,
    SUM(od.unit_price * od.quantity) AS original_total,
    SUM(od.unit_price * od.quantity * (1 - ISNULL(d.percentage, 0))) AS discounted_total,
    SUM(od.unit_price * od.quantity * ISNULL(d.percentage, 0)) AS total_discount_given
FROM order_details od
JOIN products p ON od.product_id = p.id
LEFT JOIN discounts d ON d.product_id = p.id 
                     AND d.is_active = 1 
                     AND d.start_date <= GETDATE() 
                     AND d.end_date >= GETDATE()
GROUP BY p.name
ORDER BY total_discount_given DESC;

-- Best selling products or worst 
SELECT 
    p.name,
    SUM(od.quantity) AS total_units_sold
FROM products p
JOIN order_details od ON p.id = od.product_id
GROUP BY p.name
ORDER BY total_units_sold DESC;

-- Most Products are returned
SELECT 
    p.name AS product_name,
    SUM(od.quantity) AS total_returned_units
FROM returns r
JOIN orders o ON r.order_id = o.id
JOIN order_details od ON od.order_id = o.id
JOIN products p ON od.product_id = p.id
GROUP BY p.name
ORDER BY total_returned_units DESC;
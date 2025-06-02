WITH 
orders_data AS (
    SELECT 
        o.customer_id,
        COUNT(*) AS num_orders,
        MIN(o.order_date) AS first_order,
        MAX(o.order_date) AS last_order,
        SUM(od.unit_price * od.quantity) AS total_spent,
        COUNT(DISTINCT od.product_id) AS distinct_products_count
    FROM orders o
    JOIN order_details od ON o.id = od.order_id
    GROUP BY o.customer_id
),
category_data AS (
    SELECT 
        o.customer_id,
        COUNT(DISTINCT p.category_id) AS distinct_categories_count
    FROM orders o
    JOIN order_details od ON o.id = od.order_id
    JOIN products p ON p.id = od.product_id
    GROUP BY o.customer_id
),
discount_data AS (
    SELECT 
        o.customer_id,
        COUNT(DISTINCT o.id) AS orders_with_discounts_count,
        SUM(od.unit_price * od.quantity * ISNULL(d.percentage, 0)) AS total_discount_value
    FROM orders o
    JOIN order_details od ON o.id = od.order_id
    JOIN products p ON p.id = od.product_id
    LEFT JOIN discounts d 
        ON d.product_id = p.id 
        AND d.is_active = 1 
        AND o.order_date BETWEEN d.start_date AND d.end_date
    WHERE d.percentage IS NOT NULL
    GROUP BY o.customer_id
),
session_data AS (
    SELECT 
        customer_id,
        COUNT(*) AS session_count,
        COUNT(DISTINCT CAST(session_start AS DATE)) AS active_days
    FROM customer_sessions
    GROUP BY customer_id
),
review_data AS (
    SELECT 
        customer_id,
        COUNT(*) AS review_count,
        AVG(CAST(rating AS FLOAT)) AS avg_rating,
        SUM(CASE WHEN rating < 3 THEN 1 ELSE 0 END) AS low_ratings
    FROM reviews
    GROUP BY customer_id
),
return_data AS (
    SELECT 
        o.customer_id,
        COUNT(*) AS total_returns
    FROM returns r
    JOIN orders o ON o.id = r.order_id
    GROUP BY o.customer_id
),
wishlist_data AS (
    SELECT 
        customer_id,
        COUNT(*) AS wishlist_count
    FROM wishlists
    GROUP BY customer_id
)
SELECT 
    c.id AS customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    DATEDIFF(DAY, c.registration_date, GETDATE()) AS customer_age_days,

    ISNULL(o.num_orders, 0) AS num_orders,
    ISNULL(o.total_spent, 0) AS total_spent,
    DATEDIFF(DAY, o.first_order, o.last_order) AS days_between_orders,
    ISNULL(o.distinct_products_count, 0) AS distinct_products_count,

    ISNULL(cat.distinct_categories_count, 0) AS distinct_categories_count,
    
    ISNULL(d.orders_with_discounts_count, 0) AS orders_with_discounts_count,
    ISNULL(d.total_discount_value, 0) AS total_discount_value,

    ISNULL(s.session_count, 0) AS session_count,
    ISNULL(s.active_days, 0) AS active_days,

    ISNULL(rv.review_count, 0) AS review_count,
    ISNULL(rv.avg_rating, 0) AS avg_rating,
    ISNULL(rv.low_ratings, 0) AS low_rating_count,

    ISNULL(rtn.total_returns, 0) AS total_returns,

    ISNULL(wl.wishlist_count, 0) AS wishlist_count
FROM customers c
LEFT JOIN orders_data o ON c.id = o.customer_id
LEFT JOIN category_data cat ON c.id = cat.customer_id
LEFT JOIN discount_data d ON c.id = d.customer_id
LEFT JOIN session_data s ON c.id = s.customer_id
LEFT JOIN review_data rv ON c.id = rv.customer_id
LEFT JOIN return_data rtn ON c.id = rtn.customer_id
LEFT JOIN wishlist_data wl ON c.id = wl.customer_id
ORDER BY total_spent DESC;

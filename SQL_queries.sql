--  Basic Queries
--1 Calculate the total sales revenue from all orders.

SELECT 
    SUM(od.quantity * od.unit_price) AS total_sales_revenue
FROM 
    order_details od
JOIN 
    Orders o ON od.order_id = o.id
WHERE 
    o.status IN ('processing', 'shipped', 'delivered');

--2 List the top 5 best-selling products by quantity sold.
SELECT TOP 5
	p.id,p.name,SUM(od.quantity) AS Total_Quantity
	FROM order_details od
	JOIN products p
	on od.product_id=p.id
	GROUP BY p.id, p.name
	ORDER BY Total_Quantity DESC
--3 Identify customers with the highest number of orders + num of support sessions
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

--4 Generate an alert for products with stock quantities below 20 units.--> to full it again

SELECT 
    p.id AS product_id,
    p.name AS product_name,
    i.quantity
FROM products p
JOIN inventory_movements i ON p.id = i.product_id
WHERE i.quantity < 20;

--5 Determine the percentage of orders that used a discount. 

SELECT 
    ROUND(
        COUNT(DISTINCT od.order_id) * 100.0 / 
        (SELECT COUNT(*) FROM orders),
        2
    ) AS percentage_of_discounted_orders
FROM 
    order_details od
INNER JOIN 
    discounts d
	ON od.product_id = d.product_id
WHERE 
    d.is_active = 1;


--6 Calculate the average rating for each product. 

select  p.name as Product , AVG(rating) as AVG_Rating 
from reviews r
inner join products p
on p.id = r.product_id
group by p.name;

----------------------------------------------------------------------------
---- Advanced Queries

--1 Compute the 30-day customer retention rate after their first purchase

WITH FirstPurchase AS(
SELECT 
	customer_id,
	MIN(order_date) AS first_purchase_date
FROM 
	orders
GROUP BY
		customer_id
),

PurchasesAfter30Days AS(
	SELECT 
		fp.customer_id
	FROM 
		FirstPurchase fp
	join 
		orders o
	on  fp.customer_id = o.customer_id
	WHERE 
	o.order_date>fp.first_purchase_date
	AND o.order_date<=DATEADD(day, 30, fp.first_purchase_date) 
	
)
SELECT 
    (COUNT(DISTINCT pa.customer_id) * 100.0 / COUNT(DISTINCT fp.customer_id)) AS retention_rate
FROM 
    FirstPurchase fp
LEFT JOIN 
    PurchasesAfter30Days pa ON fp.customer_id = pa.customer_id;

--2 Recommend products frequently bought together with items in customer wishlists.

WITH WishlistItems AS (
    SELECT 
        wl.customer_id,
        wl.product_id
    FROM 
        Wishlists wl
    GROUP BY 
        wl.customer_id, wl.product_id  
),

FrequentlyBoughtTogether AS (
    SELECT 
        od.product_id AS main_product,
        od2.product_id AS recommended_product,
        COUNT(*) AS purchase_count
    FROM 
        order_details od
    JOIN 
       order_details od2 ON od.order_id = od2.order_id
    WHERE 
        od.product_id <> od2.product_id
    GROUP BY 
        od.product_id, od2.product_id
)
SELECT 
    wi.product_id AS wishlist_product,
    fbt.recommended_product,
    fbt.purchase_count
FROM 
    WishlistItems wi
JOIN 
    FrequentlyBoughtTogether fbt ON wi.product_id = fbt.main_product
ORDER BY 
   
   fbt.purchase_count DESC;


--
WITH RankedDiscounts AS (
    SELECT
        d.id AS discount_id,
        d.percentage,
        d.product_id AS d_product_id,
        d.category_id,
        d.start_date,
        d.end_date,
        d.is_active,
        od.order_id,
        od.product_id AS od_product_id,
        ROW_NUMBER() OVER (
            PARTITION BY od.order_id, od.product_id
            ORDER BY 
                CASE 
                    WHEN d.product_id IS NOT NULL THEN 1
                    ELSE 2
                END,
                d.percentage DESC
        ) AS rn
    FROM order_details od
    JOIN Orders o ON od.order_id = o.id
    LEFT JOIN Discounts d ON (
        (d.product_id IS NULL OR d.product_id = od.product_id)
        AND (d.category_id IS NULL OR d.category_id = (
            SELECT category_id FROM Products WHERE id = od.product_id
        ))
        AND d.start_date <= o.order_date
        AND d.end_date >= o.order_date
        AND d.is_active = 1
    )
    WHERE o.status IN ('processing', 'shipped', 'delivered')
)

SELECT 
    SUM(od.quantity * od.unit_price * (1 - COALESCE(rd.percentage, 0) / 100.0)) AS total_sales_revenue
FROM 
    order_details od
JOIN 
    Orders o ON od.order_id = o.id
LEFT JOIN 
    RankedDiscounts rd ON rd.order_id = od.order_id 
                      AND rd.od_product_id = od.product_id 
                      AND rd.rn = 1
LEFT JOIN 
    Returns r ON r.order_id = o.id AND r.status = 'approved'
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
    AND r.order_id IS NULL; 

--3 Track inventory turnover trends using a 30-day moving average. 
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

--4 Identify customers who have purchased every product in a specific category.
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


--5  Find pairs of products commonly bought together in the same order. 

SELECT 
    od1.product_id AS product_1,
    od2.product_id AS product_2,
    COUNT(*) AS times_bought_together
FROM 
    order_details od1
JOIN 
    order_details od2 
    ON od1.order_id = od2.order_id
    AND od1.product_id < od2.product_id  -- äÊÌäÈ ÇáÊßÑÇÑ æäÝÓ ÇáãäÊÌ ãÑÊíä
GROUP BY 
    od1.product_id, od2.product_id
ORDER BY 
    times_bought_together DESC;

--6  Calculate the time taken to deliver orders in days. 

select o.id ,
DATEDIFF(day ,o.order_date,sh.shipping_date) as delivery_time
from orders o
inner join shipping sh 
on o.id = sh.order_id 
where sh.status = 'delivered'


------------------------------------------------------------------------------------------------
--------------------------SALES-----------------------------------------------------------------
--MOM SALES
SELECT 
    FORMAT(o.order_date, 'yyyy-MM') AS sales_month,
    SUM(od.quantity * od.unit_price) AS monthly_sales_revenue
FROM 
    order_details od
JOIN 
    orders o ON od.order_id = o.id
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
GROUP BY 
    FORMAT(o.order_date, 'yyyy-MM')
ORDER BY 
    sales_month;

--NET REVENUE
WITH RankedDiscounts AS (
    SELECT
        d.id AS discount_id,
        d.percentage,
        d.product_id AS d_product_id,
        d.category_id,
        d.start_date,
        d.end_date,
        d.is_active,
        od.order_id,
        od.product_id AS od_product_id,
        ROW_NUMBER() OVER (
            PARTITION BY od.order_id, od.product_id
            ORDER BY 
                CASE 
                    WHEN d.product_id IS NOT NULL THEN 1
                    ELSE 2
                END,
                d.percentage DESC
        ) AS rn
    FROM order_details od
    JOIN Orders o ON od.order_id = o.id
    LEFT JOIN Discounts d ON (
        (d.product_id IS NULL OR d.product_id = od.product_id)
        AND (d.category_id IS NULL OR d.category_id = (
            SELECT category_id FROM Products WHERE id = od.product_id
        ))
        AND d.start_date <= o.order_date
        AND d.end_date >= o.order_date
        AND d.is_active = 1
    )
    WHERE o.status IN ('processing', 'shipped', 'delivered')
)

SELECT 
    SUM(od.quantity * od.unit_price * (1 - COALESCE(rd.percentage, 0) / 100.0)) AS total_sales_revenue
FROM 
    order_details od
JOIN 
    Orders o ON od.order_id = o.id
LEFT JOIN 
    RankedDiscounts rd ON rd.order_id = od.order_id 
                      AND rd.od_product_id = od.product_id 
                      AND rd.rn = 1
LEFT JOIN 
    Returns r ON r.order_id = o.id AND r.status = 'approved'
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
    AND r.order_id IS NULL;  -- exclude orders that were approved for return


--AOV MOM
SELECT 
    FORMAT(o.order_date, 'yyyy-MM') AS order_month,
    COUNT(DISTINCT o.id) AS total_orders,
    SUM(od.quantity * od.unit_price) AS total_revenue,
    CAST(SUM(od.quantity * od.unit_price) AS FLOAT) / COUNT(DISTINCT o.id) AS average_order_value
FROM 
    orders o
JOIN 
    order_details od ON o.id = od.order_id
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
GROUP BY 
    FORMAT(o.order_date, 'yyyy-MM')
ORDER BY 
    order_month;

--Regional Sales by State
SELECT 
    -- Extract 2-letter state from address (after comma and space)
    LTRIM(RTRIM(SUBSTRING(c.address, CHARINDEX(',', c.address) + 2, 2))) AS state,

    -- Total revenue per state
    SUM(od.quantity * od.unit_price) AS total_sales
FROM 
    customers c
JOIN 
    orders o ON c.id = o.customer_id
JOIN 
    order_details od ON o.id = od.order_id
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
    AND c.address IS NOT NULL
    AND CHARINDEX(',', c.address) > 0
GROUP BY 
    LTRIM(RTRIM(SUBSTRING(c.address, CHARINDEX(',', c.address) + 2, 2)))
ORDER BY 
    state;

-- Total Sales by Payment Method
SELECT 
    p.payment_method,
    SUM(od.quantity * od.unit_price) AS total_sales
FROM 
    payments p
JOIN 
    orders o ON p.order_id = o.id
JOIN 
    order_details od ON o.id = od.order_id
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
    AND p.status = 'completed'
GROUP BY 
    p.payment_method
ORDER BY 
    total_sales DESC;

--Total Sales by Category
SELECT 
    cat.name AS category_name,
    SUM(od.quantity * od.unit_price) AS total_sales
FROM 
    order_details od
JOIN 
    orders o ON od.order_id = o.id
JOIN 
    products p ON od.product_id = p.id
JOIN 
    categories cat ON p.category_id = cat.id
WHERE 
    o.status IN ('processing', 'shipped', 'delivered')
GROUP BY 
    cat.name
ORDER BY 
    total_sales DESC;


--Combine sessions and sales by hour Monthly 

WITH SessionCounts AS (
    SELECT 
        DATEPART(HOUR, session_start) AS HourOfDay,
        DATEPART(MONTH, session_start) AS SessionMonth,
        COUNT(*) AS SessionCount
    FROM 
        customer_sessions
    GROUP BY 
        DATEPART(HOUR, session_start), DATEPART(MONTH, session_start)
), SalesByHour AS (
    SELECT
        DATEPART(HOUR, o.order_date) AS HourOfDay,
        DATEPART(MONTH, o.order_date) AS OrderMonth,
        SUM(od.quantity * od.unit_price) AS TotalSales
    FROM 
        orders o
    JOIN 
        order_details od ON o.id = od.order_id
    WHERE 
        o.status IN ('processing', 'shipped', 'delivered')
    GROUP BY 
        DATEPART(HOUR, o.order_date), DATEPART(MONTH, o.order_date)
)
SELECT 
    s.SessionMonth AS Month,
    s.HourOfDay,
    s.SessionCount,
    ISNULL(t.TotalSales, 0) AS TotalSales
FROM 
    SessionCounts s
LEFT JOIN 
    SalesByHour t 
    ON s.HourOfDay = t.HourOfDay AND s.SessionMonth = t.OrderMonth
ORDER BY 
    s.SessionMonth, s.HourOfDay;


-- sales & discounts
WITH ActiveDiscounts AS (
    SELECT 
        id,
        product_id,
        category_id,
        start_date,
        end_date
    FROM 
        discounts
    WHERE 
        is_active = 1
),
ProductDiscounts AS (
    SELECT 
        d.id,
        d.product_id,
        d.start_date,
        d.end_date
    FROM ActiveDiscounts d
    WHERE d.product_id IS NOT NULL
),
CategoryDiscounts AS (
    SELECT 
        d.id,
        d.category_id,
        d.start_date,
        d.end_date
    FROM ActiveDiscounts d
    WHERE d.product_id IS NULL AND d.category_id IS NOT NULL
),
SalesWithDiscountPriority AS (
    SELECT 
        o.id AS order_id,
        od.product_id,
        p.category_id,
        o.order_date,
        od.quantity * od.unit_price AS line_total,
        CASE 
            WHEN pd.id IS NOT NULL THEN 'Product Discount'
            WHEN cd.id IS NOT NULL THEN 'Category Discount'
            ELSE 'No Discount'
        END AS DiscountType
    FROM 
        orders o
    JOIN 
        order_details od ON o.id = od.order_id
    JOIN 
        products p ON od.product_id = p.id
    LEFT JOIN 
        ProductDiscounts pd ON 
            pd.product_id = od.product_id 
            AND o.order_date BETWEEN pd.start_date AND pd.end_date
    LEFT JOIN 
        CategoryDiscounts cd ON 
            pd.id IS NULL AND  -- only apply if no product discount
            cd.category_id = p.category_id 
            AND o.order_date BETWEEN cd.start_date AND cd.end_date
    WHERE 
        o.status IN ('processing', 'shipped', 'delivered')
)
SELECT 
    DiscountType,
    COUNT(DISTINCT order_id) AS OrderCount,
    SUM(line_total) AS TotalSales
FROM 
    SalesWithDiscountPriority
GROUP BY 
    DiscountType;

-----------------------------------------------------------------------------------------
--------------------------PRODUCTS------------------------------------------------------
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
-----------------------------------------------------------------------------------
--customer segmentation   

--total customer 

select count(*) as total_customer from customers
select MIN(registration_date) ,MAX(registration_date)  from customers;


--RFM ANALYSIS

WITH rfm_base AS (
    SELECT 
        customer_id,
        DATEDIFF(DAY, MAX(order_date), (SELECT MAX(order_date) FROM orders)) AS recency,
        COUNT(*) AS frequency,
        SUM(total_amount) AS monetary
    FROM orders
    GROUP BY customer_id
),
scored AS (
    SELECT 
        customer_id,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency ASC) AS r_score,      -- Recency ßáãÇ Þáø ßáãÇ ßÇä ÃÝÖá
        NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,    -- Frequency ßáãÇ ÒÇÏ ßáãÇ ßÇä ÃÝÖá
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score      -- Monetary ßáãÇ ÒÇÏ ßáãÇ ßÇä ÃÝÖá
    FROM rfm_base
),
final AS (
    SELECT *,
        CONCAT(r_score, f_score, m_score) AS rfm_score
    FROM scored
)
SELECT *,
    CASE 
        WHEN r_score = 5 AND f_score = 5 AND m_score >= 4 THEN ' Champions'
        WHEN r_score >= 4 AND f_score >= 4 THEN ' Loyal Customers'
        WHEN r_score <= 2 AND f_score >= 4 THEN ' At Risk'
        WHEN r_score = 5 AND f_score = 1 THEN ' New Customers'
        WHEN r_score = 1 AND f_score = 1 THEN ' Lost Customers'
        ELSE ' Others'
    END AS segment
FROM final;




	--AOV per customer
with aov_customer as (
SELECT 
  customer_id,
  SUM(total_amount) / COUNT(*) AS aov
FROM orders
GROUP BY customer_id
)
select round(avg(aov)  ,0)as AOV from aov_customer



	--CLV

	SELECT top 5
    customer_id,
    SUM(total_amount) AS clv
FROM 
    orders
GROUP BY 
    customer_id
order by clv desc





--- % customer with  one order 
WITH order_counts AS (
    SELECT 
        customer_id,
        COUNT(*) AS order_count
    FROM 
        orders
    GROUP BY 
        customer_id
)
SELECT
    ROUND(
        COUNT(CASE WHEN order_count = 1 THEN 1 END) * 100.0 /    (SELECT COUNT(*) AS total_customers FROM customers)
, 
        2
    ) AS one_time_buyers_percentage,
    ROUND(
        COUNT(CASE WHEN order_count > 1 THEN 1 END) * 100.0 /   (SELECT COUNT(*) AS total_customers FROM customers)
, 
        2
    ) AS repeat_buyers_percentage
FROM 
    order_counts;






--average customer ssesion 
 

with cus_sess as (
select * , DATEDIFF(minute , session_start,session_end) as session_time
from customer_sessions
)

select AVG(session_time) AVG_Sessiontime
from cus_sess



--most payment method

select count(customer_id) as times ,
payment_method 
from payments
group by payment_method
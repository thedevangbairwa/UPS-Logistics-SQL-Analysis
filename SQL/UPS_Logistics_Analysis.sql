# TASK 1: DATA CLEANING 7 PREPARATION
--------------------------------------


# TASK 1.1 – Identify & Deleting Duplicate Order_ID

-- Identify Duplicate Order_ID
select order_id, count(*) as duplicate_count
from orders
group by order_id
having count(*) > 1;

-- deleting duplicate
DELETE o1
FROM orders o1
JOIN orders o2
ON o1.Order_ID = o2.Order_ID
AND o1.Order_ID > o2.Order_ID;


# TASK 1.2 – Find & Replace NULL Traffic_Delay_Min

-- checking NULL Traffic_Delay_Min
select * from routes
where Traffic_Delay_Min is null;

-- Update NULL values with route average
UPDATE routes r
JOIN (
    SELECT 
        Route_ID,
        AVG(Traffic_Delay_Min) AS avg_delay
    FROM routes
    GROUP BY Route_ID
) avg_table
ON r.Route_ID = avg_table.Route_ID
SET r.Traffic_Delay_Min = avg_table.avg_delay
WHERE r.Traffic_Delay_Min IS NULL;


# TASK 1.3 – Convert Date Columns to DATE Format

-- Orders table
UPDATE orders 
SET 
    Order_Date = STR_TO_DATE(Order_Date, '%Y-%m-%d'),
    Expected_Delivery_Date = STR_TO_DATE(Expected_Delivery_Date, '%Y-%m-%d'),
    Actual_Delivery_Date = STR_TO_DATE(Actual_Delivery_Date, '%Y-%m-%d');
ALTER TABLE orders
MODIFY Order_Date DATE,
MODIFY Expected_Delivery_Date DATE,
MODIFY Actual_Delivery_Date DATE;

-- Shipment Tracking Table
UPDATE shipment_tracking_table
SET Checkpoint_Time = STR_TO_DATE(Checkpoint_Time, '%Y-%m-%d');
ALTER TABLE shipment_tracking_table
MODIFY Checkpoint_Time DATE;


# TASK 1.4 – Flag Invalid Delivery Dates

-- Find problematic records
SELECT
    Order_ID,
    Order_Date,
    Actual_Delivery_Date
FROM orders
WHERE Actual_Delivery_Date < Order_Date;

-- Add a flag column
ALTER TABLE orders
ADD COLUMN Invalid_Date_Flag INT DEFAULT 0;

-- Update flag
UPDATE orders
SET Invalid_Date_Flag = 1
WHERE Actual_Delivery_Date < Order_Date;




# Task 2: Delivery Delay Analysis
----------------------------------


-- TASK 2.1 – Calculate delivery delay for each order

SELECT
    Order_ID,
    Warehouse_ID,
    Route_ID,
    Expected_Delivery_Date,
    Actual_Delivery_Date,
    DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS Delay_Days,
    AVG(DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date)) over () as Avg_Delay_Days
FROM orders;


-- TASK 2.2 – Top 10 delayed routes (average delay)

SELECT
    Route_ID,
    AVG(DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date)) AS Avg_Delay_Days
FROM orders
GROUP BY Route_ID
ORDER BY Avg_Delay_Days DESC
LIMIT 10;


-- TASK 2.3 – Rank orders by delay within each warehouse

WITH order_delay AS (
    SELECT
        Order_ID,
        Warehouse_ID,
        Route_ID,
        DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS Delay_Days
    FROM orders
)
SELECT
    Order_ID,
    Warehouse_ID,
    Route_ID,
    Delay_Days,
    RANK() OVER (
        PARTITION BY Warehouse_ID
        ORDER BY Delay_Days DESC
    ) AS Delay_Rank_In_Warehouse
FROM order_delay;





# Task 3: Route Optimization Insights
-------------------------------------


-- TASK 3.1 – Average Delivery Time per Route
SELECT
    Route_ID,
    ROUND(AVG(DATEDIFF(Actual_Delivery_Date, Order_Date)),2) AS Avg_Delivery_Time_Days
FROM orders
GROUP BY Route_ID
ORDER BY Avg_Delivery_Time_Days DESC;


-- TASK 3.2 – Average Traffic Delay per Route
SELECT
    Route_ID,
    ROUND(AVG(Traffic_Delay_Min)) AS Avg_Traffic_Delay_Min
FROM routes
GROUP BY Route_ID
ORDER BY Avg_Traffic_Delay_Min DESC;


-- TASK 3.3 – Distance_to_Time Efficiency Ratio
-- Higher ratio = more distance covered per minute
SELECT
    Route_ID,
    Distance_KM,
    Average_Travel_Time_Min,
    round((Distance_KM / Average_Travel_Time_Min),2) AS Efficiency_Ratio
FROM routes
ORDER BY Efficiency_Ratio DESC;


-- TASK 3.4 – 3 Routes with Worst Efficiency Ratio
-- lowest efficiency first (worst)
SELECT
    Route_ID,
    Distance_KM,
    Average_Travel_Time_Min,
    ROUND((Distance_KM / Average_Travel_Time_Min),3) AS Efficiency_Ratio
FROM routes
ORDER BY Efficiency_Ratio ASC
LIMIT 3;


-- TASK 3.5 – Routes with >20% Delayed Shipments
SELECT
    Route_ID,
    COUNT(*) AS Total_Orders,
    SUM(CASE 
            WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) > 0 
            THEN 1 ELSE 0 
        END) AS Delayed_Orders,
    round(
    ((SUM(CASE 
            WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) > 0 
            THEN 1 ELSE 0 
        END) / COUNT(*)) * 100),2) AS Delay_Percentage
FROM orders
GROUP BY Route_ID
HAVING Delay_Percentage > 20;


-- EXTRA: Combined Route Performance View
SELECT
    r.Route_ID,
    r.Distance_KM,
    r.Average_Travel_Time_Min,
    ROUND(r.Distance_KM / r.Average_Travel_Time_Min, 2) AS Efficiency_Ratio,
    ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)), 2) AS Avg_Delivery_Time_Days,
    r.Traffic_Delay_Min AS Avg_Traffic_Delay_Min
FROM routes r
LEFT JOIN orders o
    ON r.Route_ID = o.Route_ID
GROUP BY
    r.Route_ID, r.Distance_KM, r.Average_Travel_Time_Min, r.Traffic_Delay_Min;


-- TASK 3.6 – Recommended potential routes for optimization.  
WITH route_delay AS (
    SELECT
        Route_ID,
        COUNT(*) AS Total_Orders,
        SUM(CASE WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) > 0 THEN 1 ELSE 0 END) AS Delayed_Orders,
        ROUND(SUM(CASE WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Delay_Percentage,
        ROUND(AVG(DATEDIFF(Actual_Delivery_Date, Order_Date)), 2) AS Avg_Delivery_Time_Days
    FROM orders
    GROUP BY Route_ID
)
SELECT
    r.Route_ID,
    ROUND(r.Distance_KM / r.Average_Travel_Time_Min, 2) AS Efficiency_Ratio,
    r.Traffic_Delay_Min,
    rd.Delay_Percentage,
    rd.Avg_Delivery_Time_Days,
    CASE
        WHEN (r.Distance_KM / r.Average_Travel_Time_Min) < 0.30 AND rd.Delay_Percentage > 20 THEN 'High Priority (Inefficient + High Delays)'
        WHEN rd.Delay_Percentage > 20 THEN 'Priority (High Delays)'
        WHEN (r.Distance_KM / r.Average_Travel_Time_Min) < 0.30 THEN 'Priority (Low Efficiency)'
        WHEN r.Traffic_Delay_Min > 40 THEN 'Watchlist (High Traffic Delay)'
        ELSE 'Normal'
    END AS Optimization_Recommendation
FROM routes r
JOIN route_delay rd
    ON r.Route_ID = rd.Route_ID
ORDER BY
    Optimization_Recommendation,
    rd.Delay_Percentage DESC,
    Efficiency_Ratio ASC;




# Task 4: Warehouse Performance
--------------------------------


-- TASK 4.1 – Top 3 Warehouses with Highest Processing Time
SELECT
    Warehouse_ID,
    Location,
    Processing_Time_Min
FROM warehouses
ORDER BY Processing_Time_Min DESC
LIMIT 3;


-- TASK 4.2 – Total vs Delayed Shipments per Warehouse
SELECT
    Warehouse_ID,
    COUNT(*) AS Total_Shipments,
    SUM(
        CASE 
            WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) > 0 
            THEN 1 ELSE 0 
        END
    ) AS Delayed_Shipments
FROM orders
GROUP BY Warehouse_ID;


-- TASK 4.3 – Bottleneck Warehouses Using CTE
WITH global_avg AS (
    SELECT AVG(Processing_Time_Min) AS Avg_Processing_Time
    FROM warehouses
)
SELECT
    w.Warehouse_ID,
    w.Location,
    w.Processing_Time_Min
FROM warehouses w
JOIN global_avg g
    ON w.Processing_Time_Min > g.Avg_Processing_Time
ORDER BY w.Processing_Time_Min DESC;


-- TASK 4.4 – Rank Warehouses by On‑Time Delivery Percentage
SELECT
    Warehouse_ID,
    ROUND(
        (SUM(
            CASE 
                WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) <= 0 
                THEN 1 ELSE 0 
            END
        ) / COUNT(*)) * 100, 
        2
    ) AS On_Time_Percentage,
    RANK() OVER (
        ORDER BY 
        (SUM(
            CASE 
                WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) <= 0 
                THEN 1 ELSE 0 
            END
        ) / COUNT(*)) DESC
    ) AS Warehouse_Rank
FROM orders
GROUP BY Warehouse_ID;




# Task 5: Delivery Agent Performance
-------------------------------------


-- TASK 5.1 – Rank Agents per Route by On Time %
SELECT
    Agent_ID,
    Route_ID,
    On_Time_Percentage,
    RANK() OVER (
        PARTITION BY Route_ID
        ORDER BY On_Time_Percentage DESC ) as Agent_rank_per_Route
FROM deliveryagents
ORDER BY Route_ID, Agent_rank_per_Route;
        
        
-- TASK 5.2 – Agents with On‑Time % < 80
SELECT
    Agent_ID,
    Route_ID,
    On_Time_Percentage
FROM deliveryagents
WHERE On_Time_Percentage < 80
ORDER BY On_Time_Percentage ASC;


-- Extra – Agents with On‑Time % > 95
SELECT
    Agent_ID,
    Route_ID,
    On_Time_Percentage
FROM deliveryagents
WHERE On_Time_Percentage > 95
ORDER BY On_Time_Percentage ASC;


-- TASK 5.3 – Compare Avg Speed of Top 5 vs Bottom 5 Agents
SELECT 'Top 5 Agents' AS Category,
       ROUND(AVG(Avg_Speed_KM_HR), 2) AS Avg_Speed
FROM (
    SELECT Avg_Speed_KM_HR
    FROM deliveryagents
    ORDER BY On_Time_Percentage DESC
    LIMIT 5
) t

UNION ALL

SELECT 'Bottom 5 Agents' AS Category,
       ROUND(AVG(Avg_Speed_KM_HR), 2) AS Avg_Speed
FROM (
    SELECT Avg_Speed_KM_HR
    FROM deliveryagents
    ORDER BY On_Time_Percentage ASC
    LIMIT 5
) b;




# Task 6: Shipment Tracking Analytics
--------------------------------------


-- TASK 6.1 – Last Checkpoint and Time for Each Order
SELECT
    Order_ID,
    Checkpoint AS Last_Checkpoint,
    Checkpoint_Time AS Last_Checkpoint_Time
FROM (
    SELECT
        Order_ID,
        Checkpoint,
        Checkpoint_Time,
        ROW_NUMBER() OVER (
            PARTITION BY Order_ID
            ORDER BY Checkpoint_Time DESC
        ) AS rn
    FROM shipment_tracking_table
) t
WHERE rn = 1;


-- TASK 6.2 – Most Common Delay Reasons (Excluding None)
SELECT
    Delay_Reason,
    COUNT(*) AS Occurrence_Count
FROM shipment_tracking_table
WHERE Delay_Reason IS NOT NULL
  AND Delay_Reason <> 'None'
GROUP BY Delay_Reason
ORDER BY Occurrence_Count DESC;


-- TASK 6.3 – Orders with More Than 2 Delayed Checkpoints
SELECT
    Order_ID,
    COUNT(*) AS Delayed_Checkpoint_Count
FROM shipment_tracking_table
WHERE Delay_Reason IS NOT NULL
  AND Delay_Reason <> 'None'
GROUP BY Order_ID
HAVING COUNT(*) > 2
ORDER BY Delayed_Checkpoint_Count DESC;




# Task 7: Advanced KPI Reporting
---------------------------------


-- TASK 7.1 – Average Delivery Delay per Region (Start_Location)
SELECT
    r.Start_Location AS Region,
    ROUND(
        AVG(DATEDIFF(o.Actual_Delivery_Date, o.Expected_Delivery_Date)),
        2
    ) AS Avg_Delivery_Delay_Days
FROM orders o
JOIN routes r
    ON o.Route_ID = r.Route_ID
GROUP BY r.Start_Location
ORDER BY Avg_Delivery_Delay_Days DESC;


-- TASK 7.2 – On‑Time Delivery Percentage (Overall)
SELECT
    ROUND(
        (SUM(
            CASE
                WHEN DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) <= 0
                THEN 1 ELSE 0
            END
        ) * 100.0 / COUNT(*)),
        2
    ) AS On_Time_Delivery_Percentage
FROM orders;


-- TASK 7.3 – Average Traffic Delay per Route
SELECT
    Route_ID,
    ROUND(AVG(Traffic_Delay_Min), 2) AS Avg_Traffic_Delay_Min
FROM routes
GROUP BY Route_ID
ORDER BY Avg_Traffic_Delay_Min DESC;
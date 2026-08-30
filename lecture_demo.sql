USE ContosoRetailDW;

-- ################################################################
-- PART 1: SUBQUERY vs CTE -- SAME BUSINESS CASE, TWO TECHNIQUES
-- ################################################################

-- ============================================================
-- BUSINESS QUESTION
-- ============================================================
-- "Which products have generated total online sales revenue
--  ABOVE the company's average revenue per product?"
--
-- Why this needs two stages:
--   Stage 1: total SalesAmount per ProductKey        (aggregate)
--   Stage 2: AVG() of those per-product totals        (aggregate of an aggregate)
--   Stage 3: keep only products whose total > Stage 2 result
--
-- A plain GROUP BY ... HAVING SUM(x) > AVG(x) will NOT work here,
-- because the AVG has to run over the already-aggregated per-product
-- totals, not over the raw sales rows. That's what forces a nested
-- query -- and is exactly what makes this a good Subquery/CTE example.
-- ============================================================


-- ============================================================
-- SOLUTION 1: SUBQUERY
-- ============================================================
-- The GROUP BY/HAVING does the per-product aggregation (Stage 1),
-- and a nested derived table inside a scalar subquery computes the
-- company-wide average of those per-product totals (Stage 2).
-- Notice everything is nested inside the WHERE/HAVING clause --
-- you have to read from the inside out to follow the logic.
-- ============================================================
SELECT p.ProductName,
        SUM(f.SalesAmount) AS ProductRevenue
FROM
    FactOnlineSales AS f
LEFT JOIN
    DimProduct AS p
    ON f.ProductKey = p.ProductKey
GROUP BY p.ProductKey, p.ProductName
HAVING SUM(f.SalesAmount) >
(    SELECT AVG(t.ProductRevenue) AS CompanyWideAverage
    FROM
    (
        SELECT p.ProductName,
                SUM(f.SalesAmount) AS ProductRevenue
        FROM FactOnlineSales AS f
        LEFT JOIN DimProduct AS p
            ON f.ProductKey = p.ProductKey
        GROUP BY p.ProductKey, p.ProductName
    ) AS t
)
ORDER BY ProductRevenue DESC;


-- ============================================================
-- SOLUTION 2: CTE (Common Table Expression)
-- ============================================================
-- Same three stages, but each one gets its own named block that
-- reads top-to-bottom like a recipe:
--   1. ProductSales      -> per-product totals
--   2. CompanyWideAverageRevenue -> the single company-wide average
-- The final SELECT just joins the two and filters. No nesting.
-- ============================================================
WITH ProductSales AS
(
    SELECT ProductKey,
            SUM(SalesAmount) AS TotalProductRevenue
    FROM FactOnlineSales
    GROUP BY ProductKey
),
CompanyWideAverageRevenue AS
(
    SELECT AVG(TotalProductRevenue) AS CompanyAvgRevenue
    FROM ProductSales
)
SELECT p.ProductKey, p.ProductName, ps.TotalProductRevenue
FROM ProductSales AS ps
LEFT JOIN DimProduct AS p
    ON ps.ProductKey = p.ProductKey
CROSS JOIN CompanyWideAverageRevenue AS cwr
WHERE ps.TotalProductRevenue > cwr.CompanyAvgRevenue
ORDER BY ps.TotalProductRevenue DESC;


-- ============================================================
-- COMPARISON: Subquery vs CTE (talking points for the lecture)
-- ============================================================
-- 1. Readability
--    - Subquery: logic is nested inside HAVING/WHERE, read inside-out.
--    - CTE: logic is broken into named, sequential steps, read top-down.
--
-- 2. Reusability
--    - Subquery: the derived table only exists inline, can't be reused
--      elsewhere in the same query without repeating it.
--    - CTE: ProductSales could be referenced again later in the same
--      query without rewriting it.
--
-- 3. Debugging
--    - Subquery: to inspect an intermediate result you must temporarily
--      copy it out into its own SELECT.
--    - CTE: you can just run "SELECT * FROM ProductSales" on its own
--      (or comment out the final SELECT) to check each stage.
--
-- 4. Naming/self-documentation
--    - CTE names (ProductSales, CompanyWideAverageRevenue) act as
--      inline documentation of what each step computes; subqueries
--      are anonymous unless you alias them.
--
-- 5. Performance
--    - In SQL Server, both typically produce the same execution plan
--      for a non-recursive CTE like this -- the optimizer treats them
--      equivalently. The choice here is about readability/maintenance,
--      not speed.
-- ============================================================


-- ################################################################
-- PART 2: NON-RECURSIVE CTEs -- STANDALONE vs NESTED
-- ################################################################
-- Note: FactOnlineSales is a flat fact table (no self-referencing
-- parent/child column), so a *recursive* CTE has nothing to walk
-- here -- recursion needs hierarchical data (org chart, BOM, etc).
-- Instead, the useful contrast on this schema is:
--   - STANDALONE CTE : each CTE computes its result straight from the
--                       base tables. No CTE references another CTE.
--   - NESTED CTE     : a later CTE is built on top of an earlier one,
--                       because it needs that earlier result already
--                       aggregated before it can rank/compare/filter it.
-- ################################################################


-- ================================================================
-- PART 2A: NON-RECURSIVE CTE -- STANDALONE TYPE
-- ================================================================
-- What "standalone" means here:
--   - Every CTE in the WITH clause reads only from base tables
--     (FactOnlineSales, DimProduct, DimCustomer, ...) -- never from
--     another CTE.
--   - The outer query may use just ONE standalone CTE (aggregate,
--     then join/filter), or it may CROSS JOIN SEVERAL standalone
--     CTEs together, since each one collapses to a single row.
-- When to reach for it:
--   - The business question only needs one level of aggregation
--     before the final filter/join -- no ranking, no comparing one
--     row to the row before/after it.
-- ================================================================


-- ----------------------------------------------------------------
-- STANDALONE Example 1: VIP customer identification
-- ----------------------------------------------------------------
-- Business case:
--   - Question: which customers have spent more than $2,500 total
--     through the online channel?
--   - Business value: surfaces VIP candidates for a loyalty program.
--   - Why standalone: one CTE aggregates spend per customer; the
--     outer query just joins to DimCustomer and filters. No second
--     CTE is needed.
-- ----------------------------------------------------------------
WITH CustomerRevenue AS (
    SELECT
        CustomerKey,
        SUM(SalesAmount) AS TotalSpend,
        COUNT(DISTINCT SalesOrderNumber) AS OrderCount
    FROM FactOnlineSales
    GROUP BY CustomerKey
)
SELECT
    c.CustomerKey,
    c.FirstName,
    c.LastName,
    cr.TotalSpend,
    cr.OrderCount
FROM CustomerRevenue AS cr
JOIN DimCustomer AS c
    ON c.CustomerKey = cr.CustomerKey
WHERE cr.TotalSpend > 2500
ORDER BY cr.TotalSpend DESC;


-- ----------------------------------------------------------------
-- STANDALONE Example 2: Promotion margin erosion
-- ----------------------------------------------------------------
-- Business case:
--   - Question: which promotions are giving away more than 50% of
--     the revenue they generate in discounts?
--   - Business value: flags promotions eroding margin, for review
--     or discontinuation.
--   - Why standalone: one CTE aggregates revenue and discount per
--     promotion; the outer query just joins to DimPromotion and
--     filters. No second CTE is needed.
-- ----------------------------------------------------------------
WITH PromotionPerformance AS (
    SELECT
        PromotionKey,
        SUM(SalesAmount) AS TotalRevenue,
        SUM(DiscountAmount) AS TotalDiscountGiven
    FROM FactOnlineSales
    GROUP BY PromotionKey
)
SELECT
    pp.PromotionKey,
    promo.PromotionName,
    pp.TotalRevenue,
    pp.TotalDiscountGiven
FROM PromotionPerformance AS pp
JOIN DimPromotion AS promo
    ON promo.PromotionKey = pp.PromotionKey
WHERE pp.TotalRevenue > 0
  AND pp.TotalDiscountGiven > pp.TotalRevenue * 0.5
ORDER BY pp.TotalDiscountGiven DESC;


-- ----------------------------------------------------------------
-- STANDALONE Example 3: Peak-day store performance
-- ----------------------------------------------------------------
-- Business case:
--   - Question: on December 20, 2008, which stores sold more than
--     3,000 units online?
--   - Business value: identifies which stores best capitalized on a
--     single peak sales/promotional day.
--   - Why standalone: one CTE filters to that date and aggregates
--     units sold per store; the outer query just joins to DimStore
--     and filters. No second CTE is needed.
-- ----------------------------------------------------------------
WITH StoreSales AS
(
    SELECT StoreKey, SUM(SalesQuantity) AS UnitSold
    FROM FactOnlineSales
    WHERE DateKey = '2008-12-20'
    GROUP BY StoreKey
)
SELECT ss.StoreKey, ds.StoreName, ss.UnitSold
FROM StoreSales AS ss
LEFT JOIN DimStore AS ds
    ON ss.StoreKey = ds.StoreKey
WHERE ss.UnitSold > 3000
ORDER BY ss.UnitSold DESC;


-- ----------------------------------------------------------------
-- STANDALONE Example 4: Executive online-sales KPI summary
-- ----------------------------------------------------------------
-- Business case:
--   - Question: what are this quarter's headline online-sales
--     numbers -- total revenue, total orders, total customers,
--     total units sold, total returns, average order value, and
--     return rate -- as a single scorecard row?
--   - Business value: the one-row "at a glance" summary leadership
--     sees at the top of a monthly/quarterly business review.
--   - Why standalone (and why FIVE of them at once): each metric is
--     computed independently straight from FactOnlineSales -- none
--     of them depends on another metric's result. Since every CTE
--     here returns exactly one row, CROSS JOINing all five together
--     just glues one row per metric into a single wide summary row,
--     with no risk of row duplication (same CROSS JOIN mechanic used
--     to attach the single average value back in Part 1/Standalone
--     Example 1 -- here it's just done with five CTEs instead of one).
-- ----------------------------------------------------------------
WITH TotalRevenue AS
(
    SELECT SUM(SalesAmount) AS CompanyRevenue
    FROM FactOnlineSales
),
QuantitySold AS
(
    SELECT SUM(SalesQuantity) AS QuantitySold
    FROM FactOnlineSales
),
TotalOrders AS
(
    SELECT COUNT(DISTINCT SalesOrderNumber) AS TotalOrders
    FROM FactOnlineSales
),
TotalCustomers AS
(
    SELECT COUNT(DISTINCT fos.CustomerKey) AS TotalCustomers
    FROM FactOnlineSales AS fos
    JOIN DimCustomer AS dc
        ON fos.CustomerKey = dc.CustomerKey
    WHERE dc.CustomerType = 'Person'
),
TotalReturns AS
(
    SELECT SUM(ReturnAmount) AS TotalReturns
    FROM FactOnlineSales
)
SELECT
    CompanyRevenue,
    TotalOrders,
    TotalCustomers,
    QuantitySold,
    TotalReturns,
    (CompanyRevenue / TotalOrders) AS AvgOrderValue,
    (TotalReturns / CompanyRevenue * 100) AS ReturnRatePct
FROM TotalRevenue
CROSS JOIN TotalOrders
CROSS JOIN TotalCustomers
CROSS JOIN TotalReturns
CROSS JOIN QuantitySold;


-- ================================================================
-- PART 2B: NON-RECURSIVE CTE -- NESTED (CHAINED) TYPE
-- ================================================================
-- What "nested" means here:
--   - A later CTE's FROM clause references an EARLIER CTE by name,
--     not a base table -- e.g. RankedProducts is built FROM
--     ProductYearlySales, not FROM FactOnlineSales.
-- When you're forced into it:
--   - The second step needs to operate on the *result* of the first
--     aggregation -- ranking within a group (ROW_NUMBER/DENSE_RANK
--     over a pre-aggregated total), comparing a period's value to
--     the prior period's (LAG over pre-aggregated totals), or
--     filtering on a value that only exists after aggregating.
--   - Window functions and "aggregate of an aggregate" logic can't
--     see per-group totals until those totals already exist as rows
--     -- so the first aggregation has to happen in its own, earlier
--     CTE before the second stage can use it.
-- Still more readable than the equivalent subquery: each stage keeps
-- its own name and sits at the same indentation level, instead of
-- being buried inside another query's FROM clause.
-- ================================================================


-- ----------------------------------------------------------------
-- NESTED Example 1: Product-category revenue, January 2009
-- ----------------------------------------------------------------
-- Business case:
--   - Question: during January 2009, which product categories
--     generated more than $5,000,000 in online sales revenue?
--   - Business value: shows merchandising which categories drove the
--     most revenue that month -- e.g. to evaluate post-holiday-season
--     demand by category.
--   - Why nested: ProductCategorySales aggregates revenue per
--     category (joining Product -> Subcategory -> Category); HighSales
--     is then built FROM ProductCategorySales to apply the $5M filter
--     as its own named stage.
-- ----------------------------------------------------------------
WITH ProductCategorySales AS
(
    SELECT pc.ProductCategoryKey, SUM(fos.SalesAmount) AS ProductCategoryRevenue
    FROM FactOnlineSales AS fos
    LEFT JOIN DimProduct AS dp
        ON fos.ProductKey = dp.ProductKey
    LEFT JOIN DimProductSubcategory AS psc
        ON dp.ProductSubcategoryKey = psc.ProductSubcategoryKey
    LEFT JOIN DimProductCategory AS pc
        ON psc.ProductCategoryKey = pc.ProductCategoryKey
    WHERE fos.DateKey >= '2009-01-01' AND fos.DateKey < '2009-02-01'
    GROUP BY pc.ProductCategoryKey
),
HighSales AS
(
    SELECT *
    FROM ProductCategorySales
    WHERE ProductCategoryRevenue > 5000000
)
SELECT hs.ProductCategoryKey, pc.ProductCategoryName, hs.ProductCategoryRevenue
FROM HighSales AS hs
LEFT JOIN DimProductCategory AS pc
    ON hs.ProductCategoryKey = pc.ProductCategoryKey
ORDER BY hs.ProductCategoryRevenue DESC;


-- ----------------------------------------------------------------
-- NESTED Example 2: Top 5 best-selling products, per year
-- ----------------------------------------------------------------
-- Business case:
--   - Question: what were the top 5 best-selling products, by
--     revenue, for each calendar year?
--   - Business value: drives the yearly bestseller report used by
--     merchandising for reordering and promotion planning.
--   - Why nested: ProductYearlySales aggregates revenue per product,
--     per year; RankedProducts is then built FROM ProductYearlySales
--     to apply ROW_NUMBER() PARTITION BY year on top of it. You can't
--     rank an aggregate in the same step you compute it.
-- ----------------------------------------------------------------
WITH ProductYearlySales AS (
    SELECT
        d.CalendarYear,
        f.ProductKey,
        SUM(f.SalesAmount) AS YearlyRevenue
    FROM FactOnlineSales AS f
    JOIN DimDate AS d
        ON d.DateKey = f.DateKey
    GROUP BY d.CalendarYear, f.ProductKey
),
RankedProducts AS (
    SELECT
        CalendarYear,
        ProductKey,
        YearlyRevenue,
        ROW_NUMBER() OVER (
            PARTITION BY CalendarYear
            ORDER BY YearlyRevenue DESC
        ) AS RevenueRank
    FROM ProductYearlySales
)
SELECT
    rp.CalendarYear,
    p.ProductName,
    rp.YearlyRevenue,
    rp.RevenueRank
FROM RankedProducts AS rp
JOIN DimProduct AS p
    ON p.ProductKey = rp.ProductKey
WHERE rp.RevenueRank <= 5
ORDER BY rp.CalendarYear, rp.RevenueRank;


-- ----------------------------------------------------------------
-- NESTED Example 3: Months with >10% month-over-month growth
-- ----------------------------------------------------------------
-- Business case:
--   - Question: in which months did online revenue grow more than
--     10% compared to the previous month?
--   - Business value: spikes like this are worth investigating
--     (promo, seasonality, marketing push) so the driver can be
--     identified and repeated.
--   - Why nested: MonthlySales aggregates revenue per calendar month;
--     MonthlyGrowth is then built FROM MonthlySales to apply LAG()
--     on top of it. LAG() needs a row per month to look back across,
--     which only exists after the monthly aggregation.
-- ----------------------------------------------------------------
WITH MonthlySales AS (
    SELECT
        d.CalendarYear,
        d.CalendarMonth,
        SUM(f.SalesAmount) AS MonthlyRevenue
    FROM FactOnlineSales AS f
    JOIN DimDate AS d
        ON d.DateKey = f.DateKey
    GROUP BY d.CalendarYear, d.CalendarMonth
),
MonthlyGrowth AS (
    SELECT
        CalendarYear,
        CalendarMonth,
        MonthlyRevenue,
        LAG(MonthlyRevenue) OVER (
            ORDER BY CalendarYear, CalendarMonth
        ) AS PriorMonthRevenue
    FROM MonthlySales
)
SELECT
    CalendarYear,
    CalendarMonth,
    MonthlyRevenue,
    PriorMonthRevenue,
    (MonthlyRevenue - PriorMonthRevenue) * 100.0 / PriorMonthRevenue AS GrowthPct
FROM MonthlyGrowth
WHERE PriorMonthRevenue IS NOT NULL
  AND MonthlyRevenue > PriorMonthRevenue * 1.10
ORDER BY CalendarYear, CalendarMonth;


-- ----------------------------------------------------------------
-- NESTED Example 4: Top 10 individual customers leaderboard
-- ----------------------------------------------------------------
-- Business case:
--   - Question: who are the top 10 individual customers (not
--     organizations) by total online spending, including anyone
--     tied at the 10th-place revenue?
--   - Business value: a contact-ready leaderboard (name, gender,
--     email) marketing can target with exclusive offers and early
--     access to new products.
--   - Why nested (three stages this time): TopCustomers aggregates
--     revenue per Person-type customer; TopCustomerRank is built
--     FROM TopCustomers to apply DENSE_RANK() (keeping ties) on top
--     of those totals; TopTenCustomers is built FROM TopCustomerRank
--     to keep only rn <= 10. Each stage depends on the previous
--     stage's aggregated/ranked result, so none of them can collapse
--     into a single step.
-- ----------------------------------------------------------------
WITH TopCustomers AS
(
    SELECT
        fos.CustomerKey,
        SUM(fos.SalesAmount) AS CustomerRevenue
    FROM FactOnlineSales AS fos
    JOIN DimCustomer AS dc
        ON fos.CustomerKey = dc.CustomerKey
    WHERE dc.CustomerType = 'Person'
    GROUP BY fos.CustomerKey
),
TopCustomerRank AS
(
    SELECT
        CustomerKey,
        CustomerRevenue,
        DENSE_RANK() OVER (ORDER BY CustomerRevenue DESC) AS rn
    FROM TopCustomers
),
TopTenCustomers AS
(
    SELECT *
    FROM TopCustomerRank
    WHERE rn <= 10
)
SELECT
    tt.CustomerKey,
    CONCAT(dc.FirstName, ' ', dc.LastName) AS CustomerFullName,
    dc.Gender AS CustomerGender,
    dc.EmailAddress,
    tt.CustomerRevenue,
    tt.rn
FROM TopTenCustomers AS tt
LEFT JOIN DimCustomer AS dc
    ON tt.CustomerKey = dc.CustomerKey
ORDER BY tt.rn;


-- ================================================================
-- STANDALONE vs NESTED CTE -- talking points
-- ================================================================
-- 1. When to use standalone:
--    - The business question only needs one level of aggregation
--      before filtering/joining (VIP customers, promo ROI, peak-day
--      stores) -- or several INDEPENDENT one-row aggregates combined
--      via CROSS JOIN into a single summary row (the KPI dashboard).
--
-- 2. When you're forced into nested:
--    - The second step needs to operate on the *result* of the
--      first aggregation -- e.g. ranking within a group (ROW_NUMBER/
--      DENSE_RANK over a pre-aggregated total), comparing a period's
--      value to a prior period's value (LAG over pre-aggregated
--      totals), or filtering on a value that only exists after
--      aggregating. Window functions can't see "totals per group"
--      until those totals already exist as rows, so the aggregation
--      has to happen in an earlier, separate step.
--
-- 3. Readability:
--    - Even nested CTEs stay easier to follow than the equivalent
--      subquery would be, because each stage still has its own name
--      and sits at the same indentation level, rather than being
--      buried inside another query's FROM clause.
-- ================================================================

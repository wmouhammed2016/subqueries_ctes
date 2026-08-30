USE ContosoRetailDW;
GO

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
--   2. AvgProductSales   -> the single company-wide average
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
--      query (e.g., a second CTE using MIN/MAX) without rewriting it.
--
-- 3. Debugging
--    - Subquery: to inspect an intermediate result you must temporarily
--      copy it out into its own SELECT.
--    - CTE: you can just run "SELECT * FROM ProductSales" on its own
--      (or comment out the final SELECT) to check each stage.
--
-- 4. Naming/self-documentation
--    - CTE names (ProductSales, AvgProductSales) act as inline
--      documentation of what each step computes; subqueries are
--      anonymous unless you alias them.
--
-- 5. Performance
--    - In SQL Server, both typically produce the same execution plan
--      for a non-recursive CTE like this -- the optimizer treats them
--      equivalently. The choice here is about readability/maintenance,
--      not speed.
-- ============================================================

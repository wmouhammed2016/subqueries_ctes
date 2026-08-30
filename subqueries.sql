/* =====================================================================
   SUBQUERIES — ContosoRetailDW
   =====================================================================
   Lecture flow:
     1) SCALAR subqueries, across every location they can appear in
     2) ROW subqueries, across every location they can appear in
     3) TABLE subqueries, across every location they can appear in
     4) CONSTRAINTS — what's legal / illegal for each type x location
     5) Subquery types by DEPENDENCY (Correlated / Non-Correlated) -- added later

   Note on the ROW category: strictly, "row" should mean one row with
   one-or-more columns. For this lecture we deliberately broaden it to
   ALSO cover "multiple rows, single column" — i.e. anything bounded to
   a single row OR a single column, but not both multi-row AND
   multi-column at once. TABLE is reserved for that fully two-dimensional
   case (many rows, many columns).

   Note: examples deliberately span multiple dimension/fact tables
   (DimProduct, DimProductSubcategory, DimStore, DimCustomer, DimEmployee,
   DimPromotion, FactOnlineSales) instead of relying only on FactOnlineSales.

   Note on literals: thresholds like UnitCost > 500 or DiscountPercent >= 0.20
   are illustrative. Adjust them if your Contoso instance's data ranges or
   DiscountPercent scale (fraction vs whole number) differ.

   Throughout, where useful, the pieces of a subquery are run standalone
   FIRST so you can see the raw intermediate result, before the full
   combined query that uses it.
   ===================================================================== */


/* =====================================================================
   SECTION 1 — SCALAR SUBQUERIES, BY LOCATION
   =====================================================================
   A scalar subquery returns exactly one row, one column — a single
   value. It can be dropped in almost anywhere a literal value could go.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 1.1 Scalar subquery in the SELECT clause
--     Evaluated once, repeated on every output row.
-- ---------------------------------------------------------------------

-- Business context: Merchandising wants a single baseline number — the
-- average product price across the whole catalog — before comparing
-- individual products against it.
-- Peek at the subquery result alone first:
SELECT AVG(UnitPrice) AS AveragePrice FROM DimProduct;

-- Business context: A pricing analyst reviewing the catalog wants to see
-- each product's price side-by-side with the catalog-wide average, to
-- spot items priced well above or below the norm.
-- Every product's price, alongside the overall average product price.
SELECT
    ProductKey,
    ProductName,
    UnitPrice,
    (SELECT AVG(UnitPrice) FROM DimProduct) AS OverallAvgPrice
FROM DimProduct;

-- Business context: HR wants the company-wide average base pay rate as
-- a reference point before flagging employees who are paid above it.
-- Same idea, different table: every employee's base rate next to the
-- company-wide average base rate.
SELECT AVG(BaseRate) AS AverageBaseRate FROM DimEmployee;

-- Business context: HR is reviewing compensation — this lists every
-- employee's base rate next to the company average, to eyeball wage
-- spread across the workforce.
SELECT
    EmployeeKey,
    FirstName,
    LastName,
    BaseRate,
    (SELECT AVG(BaseRate) FROM DimEmployee) AS AverageBaseRate
FROM DimEmployee;


-- ---------------------------------------------------------------------
-- 1.2 Scalar subquery in the FROM clause / before a JOIN
--     A single value reaches FROM the same way a "row" subquery does
--     (see 2.1) — via CROSS JOIN — just with one column instead of
--     several.
-- ---------------------------------------------------------------------

-- Business context: Retail operations wants one number — the average
-- sale amount across all online orders — to use as a comparison
-- baseline for store performance.
-- Peek at each piece alone first:
SELECT AVG(SalesAmount) AS AvgSale FROM FactOnlineSales;

-- Business context: Quick reference list of stores and their names,
-- before attaching the sales benchmark to each one.
SELECT StoreKey, StoreName FROM DimStore;

-- Business context: Store operations wants every store listed alongside
-- the same company-wide average sale amount, so each store's own
-- numbers can later be measured against a shared benchmark.
-- Attach the single company-wide average sale amount to every store row.
SELECT
    s.StoreKey,
    s.StoreName,
    avgSale.AvgSale
FROM DimStore AS s
CROSS JOIN (
    SELECT AVG(SalesAmount) AS AvgSale FROM FactOnlineSales
) AS avgSale;


-- ---------------------------------------------------------------------
-- 1.3 Scalar subquery in the WHERE clause (comparison operator)
-- ---------------------------------------------------------------------

-- Business context: HR / Finance needs a list of employees paid above
-- the company average — a common input into pay-equity or budget
-- review discussions.
-- (a) Employees whose base rate is above the company-wide average.
SELECT
    EmployeeKey,
    FirstName,
    LastName,
    BaseRate
FROM DimEmployee
WHERE BaseRate > (SELECT AVG(BaseRate) FROM DimEmployee);

-- Business context: Merchandising wants to isolate products priced at
-- or above the catalog average, e.g. to review premium-tier pricing.
-- (b) Products priced at or above the overall average product price.
SELECT
    ProductKey,
    ProductName,
    UnitPrice
FROM DimProduct
WHERE UnitPrice >= (SELECT AVG(UnitPrice) FROM DimProduct);


-- ---------------------------------------------------------------------
-- Bonus: the SAME scalar subquery can appear in more than one location
-- within a single query — here, once in SELECT and once in WHERE.
-- ---------------------------------------------------------------------

-- Business context: A pricing report that both shows the benchmark
-- (SELECT) and filters down to only above-average items (WHERE) in one
-- pass — the same benchmark subquery doing double duty.
SELECT
    ProductKey,
    ProductName,
    UnitPrice,
    (SELECT AVG(UnitPrice) FROM DimProduct) AS ProductAveragePrice
FROM DimProduct
WHERE UnitPrice >= (SELECT AVG(UnitPrice) FROM DimProduct);


/* =====================================================================
   SECTION 2 — ROW SUBQUERIES, BY LOCATION
   =====================================================================
   Covers both flavors bundled under "Row" for this lecture:
     2.1 single row / multiple columns
     2.2 multiple rows / single column
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 2.1 Single row, multiple columns
--     T-SQL has no tuple-comparison syntax like (a,b) = (SELECT a,b...)
--     and no way to inline a multi-column subquery into the SELECT
--     list either. The ONLY practical location for this shape is
--     FROM/JOIN, via CROSS JOIN — see Section 4 for why the other
--     locations don't work.
-- ---------------------------------------------------------------------

-- Business context: Finance wants the company-wide floor, ceiling, and
-- average sale amount as reference figures before comparing individual
-- stores against them.
-- Peek at each piece alone first:
SELECT
    MIN(SalesAmount) AS MinSale,
    MAX(SalesAmount) AS MaxSale,
    AVG(SalesAmount) AS AvgSale
FROM FactOnlineSales;

-- Business context: Full store directory, reviewed before attaching
-- the company-wide sales benchmarks to each row.
SELECT * FROM DimStore;

-- Business context: A store performance dashboard that shows every
-- store next to the same three company benchmarks (min/max/average
-- sale), so any store's own numbers can be judged against the full
-- range, not just the average.
-- Attach company-wide Min/Max/Avg online sale amount to every store row,
-- so each store's own numbers can be compared against the company stats.
SELECT
    s.StoreKey,
    s.StoreName,
    stats.MinSale,
    stats.MaxSale,
    stats.AvgSale
FROM DimStore AS s
CROSS JOIN (
    SELECT
        MIN(SalesAmount) AS MinSale,
        MAX(SalesAmount) AS MaxSale,
        AVG(SalesAmount) AS AvgSale
    FROM FactOnlineSales
) AS stats;


-- ---------------------------------------------------------------------
-- 2.2 Multiple rows, single column
--     Its natural home is WHERE, paired with IN / ANY / ALL.
-- ---------------------------------------------------------------------

-- Business context: Merchandising wants to know which catalog products
-- have actually sold online at least once — useful for spotting
-- products that have never moved.
-- (a) IN — products that have appeared in at least one online sale.
SELECT
    ProductKey,
    ProductName
FROM DimProduct
WHERE ProductKey IN (SELECT DISTINCT ProductKey FROM FactOnlineSales);

-- Business context: An analyst spot-checking a sample — pull the online
-- sales activity for just the first 100 products in the catalog,
-- rather than scanning the whole fact table.
-- (b) IN, combined with TOP — online sales rows belonging to one of the
--     first 100 products (by ProductKey).
SELECT
    *
FROM FactOnlineSales
WHERE ProductKey IN (
    SELECT TOP (100) ProductKey
    FROM DimProduct
);

-- Business context: Marketing wants the contact list of customers who
-- bought something under a steep promotion (20%+ discount), to analyze
-- how discount-driven buyers behave versus full-price customers.
-- (c) IN, nested two levels deep — customers who bought a product under
--     a promotion with a discount of 20% or more.
SELECT DISTINCT
    c.CustomerKey,
    c.FirstName,
    c.LastName,
    c.EmailAddress
FROM DimCustomer AS c
WHERE c.CustomerKey IN (
    SELECT f.CustomerKey
    FROM FactOnlineSales AS f
    WHERE f.PromotionKey IN (
        SELECT PromotionKey FROM DimPromotion WHERE DiscountPercent >= 0.20
    )
);

-- Business context: Pricing wants to find products priced above at
-- least the cheapest item in the "expensive to make" (cost > 500)
-- tier — a loose, exploratory price-positioning check.
-- (d) ANY — products priced higher than AT LEAST ONE product that costs
--     more than 500 to make (i.e., higher than the MIN of that set).
SELECT
    ProductKey,
    ProductName,
    UnitPrice
FROM DimProduct
WHERE UnitPrice > ANY (SELECT UnitPrice FROM DimProduct WHERE UnitCost > 500);

-- Business context: Pricing wants a stricter version of the same check
-- — products priced above every single item in that expensive-to-make
-- tier, i.e. the true price leaders.
-- (e) ALL — products priced higher than EVERY product that costs more
--     than 500 to make (i.e., higher than the MAX of that set).
--     Same subquery as (d) — only the outer comparison logic changes,
--     which is the cleanest way to contrast ANY vs ALL side by side.
SELECT
    ProductKey,
    ProductName,
    UnitPrice
FROM DimProduct
WHERE UnitPrice > ALL (SELECT UnitPrice FROM DimProduct WHERE UnitCost > 500);


/* =====================================================================
   SECTION 3 — TABLE SUBQUERIES, BY LOCATION
   =====================================================================
   Multiple rows AND multiple columns — a full derived result set.
   There is no SELECT-list location for this shape (see Section 4).
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 3.1 Table subquery in the FROM clause (subquery drives FROM, a real
--     table is joined onto it)
-- ---------------------------------------------------------------------

-- Business context: Category management wants total online sales
-- rolled up by product subcategory, before attaching readable
-- subcategory names.
-- Peek at the aggregate alone first:
SELECT
    p.ProductSubcategoryKey,
    SUM(f.SalesAmount) AS TotalAmount
FROM FactOnlineSales AS f
JOIN DimProduct AS p ON p.ProductKey = f.ProductKey
GROUP BY p.ProductSubcategoryKey;

-- Business context: A category performance report ranking product
-- subcategories by total online sales revenue, labeled with
-- human-readable subcategory names instead of raw keys.
-- Roll up online sales to the product-subcategory level, then label
-- the rolled-up totals with their subcategory name.
SELECT
    sc.ProductSubcategoryName,
    subcatSales.TotalAmount
FROM (
    SELECT
        p.ProductSubcategoryKey,
        SUM(f.SalesAmount) AS TotalAmount
    FROM FactOnlineSales AS f
    JOIN DimProduct AS p ON p.ProductKey = f.ProductKey
    GROUP BY p.ProductSubcategoryKey
) AS subcatSales
JOIN DimProductSubcategory AS sc
    ON sc.ProductSubcategoryKey = subcatSales.ProductSubcategoryKey
ORDER BY subcatSales.TotalAmount DESC;

-- Business context: Same idea at the store level — a store performance
-- report ranking stores by total online sales revenue.
-- Same FROM-clause pattern again, at the store level — aggregate first,
-- then join for the label.
SELECT
    storeSales.StoreKey,
    s.StoreName,
    storeSales.TotalAmount
FROM (
    SELECT
        StoreKey,
        SUM(SalesAmount) AS TotalAmount
    FROM FactOnlineSales
    GROUP BY StoreKey
) AS storeSales
JOIN DimStore AS s ON s.StoreKey = storeSales.StoreKey
ORDER BY storeSales.TotalAmount DESC;

-- Business context: Same store performance report, built the
-- "traditional" join-then-group way — useful to hand to someone who
-- wants the same numbers without a subquery in sight, and to compare
-- against the aggregate-then-join version above.
-- Equivalent WITHOUT a subquery, for comparison (join first, then
-- group) — same result, no subquery involved. See the earlier
-- discussion on aggregate-then-join vs join-then-aggregate: the
-- optimizer often produces the same plan either way, but the subquery
-- version protects the SUM from being affected by anything the outer
-- join does, which matters the moment the joined table isn't
-- guaranteed one row per key.
SELECT
    fos.StoreKey,
    ds.StoreName,
    SUM(fos.SalesAmount) AS StoreSales
FROM FactOnlineSales AS fos
INNER JOIN DimStore AS ds
    ON fos.StoreKey = ds.StoreKey
GROUP BY fos.StoreKey, ds.StoreName
ORDER BY StoreSales DESC;


-- ---------------------------------------------------------------------
-- 3.2 Table subquery before a JOIN (a real table drives FROM, the
--     subquery is joined onto it)
-- ---------------------------------------------------------------------

-- Business context: Customer analytics wants total spend per customer
-- as a first pass, before matching it up with customer names.
-- Peek at the aggregate alone first:
SELECT
    CustomerKey,
    SUM(SalesAmount) AS TotalSpent
FROM FactOnlineSales
GROUP BY CustomerKey;

-- Business context: A "top spenders" report for the marketing/loyalty
-- team, showing each customer's name next to their total online spend
-- — the kind of list that feeds a VIP or win-back campaign.
-- Total amount spent per customer, joined to DimCustomer to show who
-- the top spenders actually are (by name).
SELECT
    c.CustomerKey,
    c.FirstName,
    c.LastName,
    custSales.TotalSpent
FROM DimCustomer AS c
JOIN (
    SELECT
        CustomerKey,
        SUM(SalesAmount) AS TotalSpent
    FROM FactOnlineSales
    GROUP BY CustomerKey
) AS custSales ON c.CustomerKey = custSales.CustomerKey
ORDER BY custSales.TotalSpent DESC;


-- ---------------------------------------------------------------------
-- 3.3 Table subquery in the WHERE clause, via EXISTS
--     EXISTS only cares whether the subquery returns any rows at all —
--     column count and values are irrelevant (see Section 4).
-- ---------------------------------------------------------------------

-- Business context: Checking whether any promotion currently on the
-- books offers a steep (20%+) discount, before using that as a gating
-- condition.
-- Peek at the subquery alone first:
SELECT * FROM DimPromotion WHERE DiscountPercent >= 0.20;

-- Business context: A simple compliance/reporting-style check — should
-- the store list even be shown if there's currently a deep-discount
-- promotion active company-wide? (Note: this version can't yet target
-- a specific store's own promotions — that needs correlation, covered
-- later.)
-- A boolean gate: does at least one promotion with a 20%+ discount
-- exist? This is intentionally NON-correlated — it never references
-- DimStore, so the answer is the same for every outer row (either
-- every store passes, or none do). We'll revisit EXISTS once
-- correlation is introduced, where it becomes far more useful —
-- checking a condition PER outer row instead of once globally.
SELECT
    StoreKey,
    StoreName
FROM DimStore
WHERE EXISTS (
    SELECT 1 FROM DimPromotion WHERE DiscountPercent >= 0.20
);

-- Business context: A richer "top spenders" report, narrowed to
-- individual shoppers only (excluding company/B2B accounts), showing
-- how many separate orders each customer placed alongside their total
-- spend and quantity purchased — the kind of view a loyalty team would
-- use to decide who gets a personalized retention offer.
-- Demos for me
-- Get all the customers with their order details
SELECT
    dc.CustomerKey,
    CONCAT(dc.FirstName, ' ', dc.LastName) AS CustomerName,
    gdc.OrdersCount,
    gdc.TotalSales,
    gdc.QuantitySold
FROM DimCustomer AS dc
INNER JOIN (
    SELECT
    CustomerKey,
    COUNT(DISTINCT SalesOrderNumber) AS OrdersCount,
    SUM(SalesAmount) AS TotalSales,
    SUM(SalesQuantity) AS QuantitySold
FROM FactOnlineSales AS fos
GROUP BY CustomerKey
) AS gdc
    ON dc.CustomerKey = gdc.CustomerKey
WHERE CustomerType != 'Company'
ORDER BY gdc.TotalSales DESC;

-- Business context: Peek at the underlying per-customer order count,
-- total spend, and quantity purchased alone, before it gets joined to
-- customer names and filtered down to individuals only above.
SELECT
    CustomerKey,
    COUNT(DISTINCT SalesOrderNumber) AS OrdersCount,
    SUM(SalesAmount) AS TotalSales,
    SUM(SalesQuantity) AS QuantitySold
FROM FactOnlineSales AS fos
GROUP BY CustomerKey;

/* =====================================================================
   SECTION 4 — CONSTRAINTS, BY TYPE AND LOCATION
   =====================================================================
   Real T-SQL rules, not just style preferences. Invalid examples are
   commented out so the file still runs top to bottom.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 4.1 Scalar subquery constraints
-- ---------------------------------------------------------------------

-- Must return at most one row AND exactly one column. If the subquery
-- can return more than one row at runtime, SQL Server raises:
--   Msg 512: "Subquery returned more than 1 value. This is not
--   permitted when the subquery follows =, !=, <, <=, >, >=, or when
--   the subquery is used as an expression."
-- INVALID:
-- SELECT ProductKey, (SELECT UnitPrice FROM DimProduct) AS Price
-- FROM DimProduct;

-- ORDER BY is not allowed inside a subquery / derived table / view /
-- inline function UNLESS it's paired with TOP, OFFSET/FETCH, or FOR XML:
--   Msg 1033: "The ORDER BY clause is invalid in views, inline
--   functions, derived tables, subqueries, and common table
--   expressions, unless TOP, OFFSET or FOR XML is also specified."
-- INVALID:
-- SELECT * FROM (
--     SELECT ProductKey, UnitPrice FROM DimProduct ORDER BY UnitPrice
-- ) AS x;
-- Business context: Merchandising wants the 5 most expensive products
-- in the catalog — a legitimate use of ORDER BY inside a derived
-- table, made valid here by pairing it with TOP.
-- VALID FIX — TOP legitimizes the ORDER BY:
SELECT * FROM (
    SELECT TOP (5) ProductKey, UnitPrice
    FROM DimProduct
    ORDER BY UnitPrice DESC
) AS top5;


-- ---------------------------------------------------------------------
-- 4.2 Row subquery constraints
-- ---------------------------------------------------------------------

-- Single row / multiple columns has no home in SELECT or WHERE in
-- T-SQL — there's no row-constructor / tuple-comparison syntax
-- (unlike PostgreSQL, MySQL, or Oracle). The parser simply rejects it.
-- INVALID (not valid T-SQL syntax at all):
-- SELECT * FROM DimProduct
-- WHERE (ProductSubcategoryKey, UnitPrice) =
--       (SELECT ProductSubcategoryKey, MAX(UnitPrice) FROM DimProduct
--        GROUP BY ProductSubcategoryKey);

-- The CROSS JOIN pattern (2.1) has a silent danger: unlike the scalar
-- case, there's no error if the subquery unexpectedly returns more
-- than one row. Instead, every outer row gets duplicated once per
-- extra row returned — a silent fan-out bug, not a hard failure. E.g.
-- if the stats subquery in 2.1 had a GROUP BY added to it, it would
-- return one row per group instead of one overall, and DimStore's row
-- count would silently multiply.


-- ---------------------------------------------------------------------
-- 4.3 Table subquery constraints
-- ---------------------------------------------------------------------

-- Derived tables in FROM MUST be aliased in T-SQL (this is required by
-- the engine, not just a style choice) — an unaliased derived table
-- fails to bind/parse.
-- INVALID:
-- SELECT * FROM (
--     SELECT StoreKey, SUM(SalesAmount) AS TotalAmount
--     FROM FactOnlineSales GROUP BY StoreKey
-- );

-- IN / ANY / ALL / SOME require the subquery to return EXACTLY ONE
-- COLUMN, or SQL Server raises:
--   Msg 116: "Only one expression can be specified in the select list
--   when the subquery is not introduced with EXISTS."
-- INVALID:
-- SELECT * FROM DimProduct
-- WHERE ProductKey IN (SELECT ProductKey, ProductSubcategoryKey FROM DimProduct);

-- EXISTS is the one exception to the "one column" rule above — it
-- ignores the select list entirely, which is why SELECT 1 is idiomatic
-- inside EXISTS (see 3.3): SELECT 1 and SELECT * behave identically,
-- since only row existence is checked, never the values.

-- A table-shaped (multi-row) subquery cannot sit directly in the
-- SELECT list or behind a plain comparison operator — it must go
-- through FROM/JOIN, or WHERE with IN/ANY/ALL/EXISTS. Using it as a
-- scalar expression hits the same Msg 512 as 4.1 the moment more than
-- one row comes back:
-- INVALID (if DimProduct has more than one row, which it does):
-- SELECT ProductKey, (SELECT ProductKey FROM DimProduct) FROM DimProduct;

-- Forward pointer: a CORRELATED subquery cannot sit in a plain
-- FROM/JOIN at all — T-SQL requires CROSS APPLY / OUTER APPLY instead,
-- because JOIN's ON clause is evaluated after both sides are already
-- materialized, while APPLY re-evaluates its right side per outer row.
-- Covered in Section 5.


/* =====================================================================
   SECTION 5 — SUBQUERY TYPES BY DEPENDENCY (Correlated / Non-Correlated)
   =====================================================================
   A NON-correlated subquery (everything above) is self-contained: it
   could be run on its own, with no knowledge of the outer query, and
   the same result would be reused for every outer row.

   A CORRELATED subquery reaches OUT and references a column from the
   outer row currently being processed. It cannot be run standalone —
   conceptually, it is re-evaluated once per outer row (the optimizer
   may rewrite this into a join internally, but logically that's the
   contract). This is what unlocks "compared to its OWN group" and
   "does THIS row have a match" logic that a non-correlated subquery
   can never express, no matter how it's written.

   Five examples below, gradually harder, each showing something a
   non-correlated subquery genuinely cannot do.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 5.1 (Level 1 — easiest) Correlated scalar subquery in SELECT
--     Callback to 1.1: there, every product was compared to the SAME
--     catalog-wide average, regardless of category. Here, each
--     product is compared to the average of its OWN subcategory —
--     a different number per row, which only correlation can produce.
-- ---------------------------------------------------------------------

-- Business context: Merchandising doesn't want to compare a t-shirt's
-- price to the average of the entire catalog (which includes TVs and
-- furniture) — they want it compared to other shirts. A correlated
-- subquery recomputes the average freshly for each product's own
-- subcategory.
SELECT
    p.ProductKey,
    p.ProductName,
    p.ProductSubcategoryKey,
    p.UnitPrice,
    (
        SELECT AVG(p2.UnitPrice)
        FROM DimProduct AS p2
        WHERE p2.ProductSubcategoryKey = p.ProductSubcategoryKey
    ) AS SubcategoryAvgPrice
FROM DimProduct AS p;


-- ---------------------------------------------------------------------
-- 5.2 (Level 2) Correlated scalar subquery in WHERE
--     Same correlated subquery as 5.1, now used to filter instead of
--     just display — "above average for ITS group," not above average
--     overall.
-- ---------------------------------------------------------------------

-- Business context: Pricing wants the products that are premium-priced
-- relative to their OWN peers — e.g. an expensive shirt relative to
-- other shirts — not just anything pricier than the catalog-wide
-- average, which would be dominated by naturally expensive categories.
SELECT
    p.ProductKey,
    p.ProductName,
    p.ProductSubcategoryKey,
    p.UnitPrice
FROM DimProduct AS p
WHERE p.UnitPrice > (
    SELECT AVG(p2.UnitPrice)
    FROM DimProduct AS p2
    WHERE p2.ProductSubcategoryKey = p.ProductSubcategoryKey
);


-- ---------------------------------------------------------------------
-- 5.3 (Level 3) Correlated EXISTS / NOT EXISTS
--     Callback to 3.3: that EXISTS was a single global yes/no gate,
--     answered once for the whole query. This one is answered fresh
--     for every store — a per-row existence check, which is the whole
--     point of EXISTS and impossible without correlation.
--     (Shown at the store level rather than per-employee, since in
--     this schema sales are attributed to a store, not an individual
--     employee.)
-- ---------------------------------------------------------------------

-- Business context: Operations wants to find stores that have NEVER
-- recorded a single online sale — candidates for a platform-access
-- audit, a re-launch push, or closure review. "Never" is inherently a
-- per-store question; a non-correlated EXISTS could only ever answer
-- it once for the whole company.
SELECT
    s.StoreKey,
    s.StoreName
FROM DimStore AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM FactOnlineSales AS f
    WHERE f.StoreKey = s.StoreKey
);


-- ---------------------------------------------------------------------
-- 5.4 (Level 4) Correlated subquery driving a "top 1 per group" filter
--     Combines a table subquery (aggregation) with a correlated scalar
--     comparison (MAX per subcategory) — the two ideas from Sections
--     1-3 working together.
-- ---------------------------------------------------------------------

-- Business context: Category managers want the single best-selling
-- product WITHIN EACH subcategory — not the top sellers overall (which
-- would just be dominated by whichever category sells the most), but
-- the local champion of every subcategory, so every category gets a
-- fair "best of" spotlight.
-- (Note: the sales-by-product aggregate below is written out twice —
-- once for the outer product, once inside the correlated MAX subquery.
-- That repetition is exactly the kind of duplication CTEs exist to
-- solve — more on that in the next topic.)
SELECT
    p.ProductKey,
    p.ProductName,
    p.ProductSubcategoryKey,
    ps.TotalAmount
FROM DimProduct AS p
JOIN (
    SELECT ProductKey, SUM(SalesAmount) AS TotalAmount
    FROM FactOnlineSales
    GROUP BY ProductKey
) AS ps ON ps.ProductKey = p.ProductKey
WHERE ps.TotalAmount = (
    SELECT MAX(ps2.TotalAmount)
    FROM DimProduct AS p2
    JOIN (
        SELECT ProductKey, SUM(SalesAmount) AS TotalAmount
        FROM FactOnlineSales
        GROUP BY ProductKey
    ) AS ps2 ON ps2.ProductKey = p2.ProductKey
    WHERE p2.ProductSubcategoryKey = p.ProductSubcategoryKey
);


-- ---------------------------------------------------------------------
-- 5.5 (Level 5 — hardest) Correlated subquery in FROM, via CROSS APPLY
--     Fulfils the forward pointer from 4.3: a correlated subquery
--     cannot sit in a plain FROM/JOIN, because JOIN's ON clause is
--     evaluated only after both sides are already materialized — it
--     has nothing to correlate against yet. CROSS APPLY re-evaluates
--     its right side once per outer row, so it CAN reference the
--     outer row, and — unlike 5.4 — it can return more than one
--     matching row per group (a true "top N per group", not just
--     "top 1").
-- ---------------------------------------------------------------------

-- Business context: Store merchandising wants each store's top 3
-- best-selling products by revenue, to plan local promotions and
-- shelf placement. "Top 1 per group" (5.4) can be done with a plain
-- correlated subquery, but "top 3 per group" cannot — there's no
-- single scalar to compare against. CROSS APPLY solves this by running
-- a small correlated TOP query once per store.
SELECT
    s.StoreKey,
    s.StoreName,
    top3.ProductKey,
    top3.TotalAmount
FROM DimStore AS s
CROSS APPLY (
    SELECT TOP (3)
        f.ProductKey,
        SUM(f.SalesAmount) AS TotalAmount
    FROM FactOnlineSales AS f
    WHERE f.StoreKey = s.StoreKey
    GROUP BY f.ProductKey
    ORDER BY SUM(f.SalesAmount) DESC
) AS top3;

-- Note: CROSS APPLY drops stores with zero matching rows (same spirit
-- as CROSS JOIN / INNER JOIN). Swapping in OUTER APPLY instead would
-- keep every store — including ones with no online sales at all — with
-- NULLs in top3's columns, the same way LEFT JOIN would.

-- =========================================================
-- 0) Crear/usar schema analiticas
-- =========================================================
CREATE SCHEMA IF NOT EXISTS analiticas;
SET search_path TO analiticas, public;

-- =========================================================
-- 1) Limpiar (si existieran versiones previas)
-- =========================================================
DROP TABLE IF EXISTS analiticas.fact_sales     CASCADE;
DROP TABLE IF EXISTS analiticas.dim_customer   CASCADE;
DROP TABLE IF EXISTS analiticas.dim_product    CASCADE;
DROP TABLE IF EXISTS analiticas.dim_employee   CASCADE;
DROP TABLE IF EXISTS analiticas.dim_shipper    CASCADE;
DROP TABLE IF EXISTS analiticas.dim_date       CASCADE;

-- =========================================================
-- 2) Dimensiones (CTAS)
-- =========================================================

-- 2.1) Cliente
CREATE TABLE analiticas.dim_customer AS
SELECT DISTINCT
    c."CustomerID"   AS customer_id,
    c."CompanyName"  AS company_name,
    c."ContactName"  AS contact_name,
    c."Country"      AS country,
    c."City"         AS city,
    COALESCE(c."Region",'') AS region
FROM public.customers c;

ALTER TABLE analiticas.dim_customer
  ADD CONSTRAINT pk_dim_customer PRIMARY KEY (customer_id);

-- 2.2) Producto (con categoría y proveedor)
CREATE TABLE analiticas.dim_product AS
SELECT DISTINCT
    p."ProductID"     AS product_id,
    p."ProductName"   AS product_name,
    cat."CategoryName" AS category_name,
    s."CompanyName"    AS supplier_name
FROM public.products   p
LEFT JOIN public.categories cat ON cat."CategoryID" = p."CategoryID"
LEFT JOIN public.suppliers  s   ON s."SupplierID"  = p."SupplierID";

ALTER TABLE analiticas.dim_product
  ADD CONSTRAINT pk_dim_product PRIMARY KEY (product_id);

-- 2.3) Empleado
CREATE TABLE analiticas.dim_employee AS
SELECT DISTINCT
    e."EmployeeID"           AS employee_id,
    e."FirstName"            AS first_name,
    e."LastName"             AS last_name,
    (e."FirstName" || ' ' || e."LastName") AS full_name,
    e."Title"                AS title,
    e."Country"              AS country,
    e."City"                 AS city
FROM public.employees e;

ALTER TABLE analiticas.dim_employee
  ADD CONSTRAINT pk_dim_employee PRIMARY KEY (employee_id);

-- 2.4) Shipper
CREATE TABLE analiticas.dim_shipper AS
SELECT DISTINCT
    s."ShipperID"    AS shipper_id,
    s."CompanyName"  AS company_name
FROM public.shippers s;

ALTER TABLE analiticas.dim_shipper
  ADD CONSTRAINT pk_dim_shipper PRIMARY KEY (shipper_id);

-- 2.5) Calendario (rango según Orders)
CREATE TABLE analiticas.dim_date AS
WITH bounds AS (
  SELECT
    min(o."OrderDate")::date AS min_date,
    max(o."OrderDate")::date AS max_date
  FROM public.orders o
)
SELECT
  gs::date                            AS date_value,
  to_char(gs,'YYYYMMDD')::int         AS date_key,
  EXTRACT(YEAR    FROM gs)::int       AS year,
  EXTRACT(QUARTER FROM gs)::int       AS quarter,
  EXTRACT(MONTH   FROM gs)::int       AS month,
  EXTRACT(DAY     FROM gs)::int       AS day,
  EXTRACT(ISODOW  FROM gs)::int       AS weekday,
  to_char(gs,'Dy')                    AS weekday_name,
  to_char(gs,'Mon')                   AS month_name
FROM bounds b
CROSS JOIN generate_series(b.min_date, b.max_date, interval '1 day') AS gs;

ALTER TABLE analiticas.dim_date
  ADD CONSTRAINT pk_dim_date PRIMARY KEY (date_key);

ALTER TABLE analiticas.dim_date
  ADD CONSTRAINT uq_dim_date_date UNIQUE (date_value);

-- =========================================================
-- 3) Hechos (CTAS) - fact_sales
--    FIX: convertir a NUMERIC para poder redondear / dar escala
-- =========================================================
CREATE TABLE analiticas.fact_sales AS
SELECT
    od."OrderID"                           AS order_id,
    o."OrderDate"::date                    AS order_date,
    to_char(o."OrderDate",'YYYYMMDD')::int AS date_key,

    o."CustomerID"                         AS customer_id,
    o."EmployeeID"                         AS employee_id,
    od."ProductID"                         AS product_id,
    o."ShipVia"                            AS shipper_id,

    od."Quantity"                          AS quantity,
    od."UnitPrice"                         AS unit_price,
    COALESCE(od."Discount",0)              AS discount,

    -- total_amount NUMERIC(18,2) (sin usar round(double,…))
    (
        od."Quantity"::numeric
      * od."UnitPrice"::numeric
      * (1 - COALESCE(od."Discount",0)::numeric)
    )::numeric(18,2)                       AS total_amount
FROM public.order_details od
JOIN public.orders o
  ON o."OrderID" = od."OrderID";

-- PK (orden + producto representa una línea de pedido)
ALTER TABLE analiticas.fact_sales
  ADD CONSTRAINT pk_fact_sales PRIMARY KEY (order_id, product_id);

-- Índices útiles para joins analíticos
CREATE INDEX ix_fact_sales_date_key   ON analiticas.fact_sales (date_key);
CREATE INDEX ix_fact_sales_customer   ON analiticas.fact_sales (customer_id);
CREATE INDEX ix_fact_sales_employee   ON analiticas.fact_sales (employee_id);
CREATE INDEX ix_fact_sales_product    ON analiticas.fact_sales (product_id);
CREATE INDEX ix_fact_sales_shipper    ON analiticas.fact_sales (shipper_id);

-- =========================================================
-- 4) Llaves Foráneas (FKs)
-- =========================================================
ALTER TABLE analiticas.fact_sales
  ADD CONSTRAINT fk_fact_date
      FOREIGN KEY (date_key)
      REFERENCES analiticas.dim_date (date_key);

ALTER TABLE analiticas.fact_sales
  ADD CONSTRAINT fk_fact_customer
      FOREIGN KEY (customer_id)
      REFERENCES analiticas.dim_customer (customer_id);

ALTER TABLE analiticas.fact_sales
  ADD CONSTRAINT fk_fact_product
      FOREIGN KEY (product_id)
      REFERENCES analiticas.dim_product (product_id);

ALTER TABLE analiticas.fact_sales
  ADD CONSTRAINT fk_fact_employee
      FOREIGN KEY (employee_id)
      REFERENCES analiticas.dim_employee (employee_id);

ALTER TABLE analiticas.fact_sales
  ADD CONSTRAINT fk_fact_shipper
      FOREIGN KEY (shipper_id)
      REFERENCES analiticas.dim_shipper (shipper_id);

-- =========================================================
-- 5) (Opcional) Verificación rápida
-- =========================================================
 SELECT * FROM analiticas.dim_date    LIMIT 5;
 SELECT * FROM analiticas.dim_product LIMIT 5;
 SELECT * FROM analiticas.fact_sales  LIMIT 5;
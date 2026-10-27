/* =====================================================================
   INV_VENTAS_DIARIAS.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Venta diaria por línea, TODO EN $, desde el 1 de enero de hace dos años.
   Base para el análisis por semana, mes y año del dashboard.
   venta = reng_neto / tasa (neto de descuento)  |  costo = ult_cos_om del renglón
   Facturas menos devoluciones. Excluye documentos anulados.
   ===================================================================== */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- solo lectura, no bloquea a caja/facturación

DECLARE @desde date = DATEFROMPARTS(YEAR(GETDATE()) - 2, 1, 1);

WITH mov AS (
    SELECT CAST(f.fec_emis AS date)              AS fecha,
           a.co_lin,
           rf.total_art                          AS uds,
           rf.reng_neto / NULLIF(f.tasa, 0)      AS venta,
           rf.total_art * rf.ult_cos_om          AS costo,
           f.fact_num                            AS doc
    FROM dbo.reng_fac rf
    JOIN dbo.factura f ON f.fact_num = rf.fact_num
    JOIN dbo.art a     ON a.co_art   = rf.co_art
    WHERE f.anulada = 0 AND f.fec_emis >= @desde
    UNION ALL
    SELECT CAST(d.fec_emis AS date),
           a.co_lin,
           -rd.total_art,
           -rd.reng_neto / NULLIF(d.tasa, 0),
           -rd.total_art * rd.ult_cos_om,
           NULL
    FROM dbo.reng_dvc rd
    JOIN dbo.dev_cli d ON d.fact_num = rd.fact_num
    JOIN dbo.art a     ON a.co_art   = rd.co_art
    WHERE d.anulada = 0 AND d.fec_emis >= @desde
), dia AS (
    SELECT m.fecha,
           RTRIM(ISNULL(l.lin_des, m.co_lin))   AS linea,
           SUM(m.uds)                           AS uds,
           SUM(m.venta)                         AS venta_usd,
           SUM(m.costo)                         AS costo_usd,
           COUNT(DISTINCT m.doc)                AS facturas
    FROM mov m
    LEFT JOIN dbo.lin_art l ON l.co_lin = m.co_lin
    GROUP BY m.fecha, RTRIM(ISNULL(l.lin_des, m.co_lin))
)
SELECT fila FROM (
    SELECT 0 AS ord, CAST('19000101' AS date) AS k1, '' AS k2,
           'fecha;linea;uds;venta_usd;costo_usd;facturas' AS fila
    UNION ALL
    SELECT 1, fecha, linea, CONCAT(
        CONVERT(varchar(10), fecha, 23), ';', REPLACE(linea, ';', ','), ';',
        CAST(uds AS decimal(20,2)), ';', CAST(venta_usd AS decimal(20,2)), ';',
        CAST(costo_usd AS decimal(20,2)), ';', facturas)
    FROM dia
) x
ORDER BY ord, k1, k2;

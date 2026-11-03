/* =====================================================================
   INV_VENTAS_VENDEDOR.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Venta diaria por vendedor y artículo, TODO EN $, desde el 1 de enero
   del año pasado. Base de la sección "Desempeño de vendedores".
   venta = reng_neto / tasa (neto de descuento)  |  costo = ult_cos_om del renglón
   Vendedor = co_ven del documento. Marca = categoría del artículo en Profit.
   Facturas menos devoluciones. Excluye documentos anulados.
   ===================================================================== */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- solo lectura, no bloquea a caja/facturación

DECLARE @desde date = DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1);

WITH mov AS (
    SELECT CAST(f.fec_emis AS date)              AS fecha,
           f.co_ven,
           rf.co_art,
           rf.total_art                          AS uds,
           rf.reng_neto / NULLIF(f.tasa, 0)      AS venta,
           rf.total_art * rf.ult_cos_om          AS costo
    FROM dbo.reng_fac rf
    JOIN dbo.factura f ON f.fact_num = rf.fact_num
    WHERE f.anulada = 0 AND f.fec_emis >= @desde
    UNION ALL
    SELECT CAST(d.fec_emis AS date),
           d.co_ven,
           rd.co_art,
           -rd.total_art,
           -rd.reng_neto / NULLIF(d.tasa, 0),
           -rd.total_art * rd.ult_cos_om
    FROM dbo.reng_dvc rd
    JOIN dbo.dev_cli d ON d.fact_num = rd.fact_num
    WHERE d.anulada = 0 AND d.fec_emis >= @desde
), dia AS (
    SELECT m.fecha,
           RTRIM(ISNULL(m.co_ven, ''))                    AS co_ven,
           RTRIM(ISNULL(v.ven_des, ISNULL(m.co_ven, ''))) AS vendedor,
           RTRIM(m.co_art)                                AS co_art,
           RTRIM(ISNULL(l.lin_des, a.co_lin))             AS linea,
           RTRIM(ISNULL(c.cat_des, a.co_cat))             AS marca,
           SUM(m.uds)                                     AS uds,
           SUM(m.venta)                                   AS venta_usd,
           SUM(m.costo)                                   AS costo_usd
    FROM mov m
    JOIN dbo.art a          ON a.co_art = m.co_art
    LEFT JOIN dbo.vendedor v ON v.co_ven = m.co_ven
    LEFT JOIN dbo.lin_art  l ON l.co_lin = a.co_lin
    LEFT JOIN dbo.cat_art  c ON c.co_cat = a.co_cat
    GROUP BY m.fecha, m.co_ven, v.ven_des, m.co_art, l.lin_des, a.co_lin, c.cat_des, a.co_cat
    HAVING SUM(m.venta) <> 0 OR SUM(m.uds) <> 0
)
SELECT fila FROM (
    SELECT 0 AS ord, CAST('19000101' AS date) AS k1, '' AS k2, '' AS k3,
           'fecha;co_ven;vendedor;co_art;linea;marca;uds;venta_usd;costo_usd' AS fila
    UNION ALL
    SELECT 1, fecha, co_ven, co_art, CONCAT(
        CONVERT(varchar(10), fecha, 23), ';', REPLACE(co_ven, ';', ','), ';', REPLACE(vendedor, ';', ','), ';',
        REPLACE(co_art, ';', ','), ';', REPLACE(linea, ';', ','), ';', REPLACE(marca, ';', ','), ';',
        CAST(uds AS decimal(20,2)), ';', CAST(venta_usd AS decimal(20,2)), ';', CAST(costo_usd AS decimal(20,2)))
    FROM dia
) x
ORDER BY ord, k1, k2, k3;

/* =====================================================================
   INV_VERIFICAR.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Chequeos en $ (ult_cos_om y reng_neto / tasa). Ejecutar (F5) y
   mandar captura de la pestaña Resultados.
   ===================================================================== */
USE HD_A01;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- 1) Valor del inventario en $ con ult_cos_om, y costos inválidos
SELECT SUM(s.stock_act * a.ult_cos_om)                        AS valor_inv_usd,
       SUM(CASE WHEN a.ult_cos_om < 0  THEN 1 ELSE 0 END)     AS art_costo_negativo,
       SUM(CASE WHEN a.ult_cos_om = 0  THEN 1 ELSE 0 END)     AS art_costo_cero,
       SUM(CASE WHEN s.stock_act < 0   THEN 1 ELSE 0 END)     AS art_stock_negativo
FROM (SELECT co_art, SUM(stock_act) AS stock_act FROM dbo.st_almac GROUP BY co_art) s
JOIN dbo.art a ON a.co_art = s.co_art
WHERE s.stock_act <> 0 AND a.anulado = 0;

-- 2) Venta, costo y margen en $ de los últimos 90 días (facturas - devoluciones)
SELECT SUM(v) AS venta_usd_90d, SUM(c) AS costo_usd_90d,
       SUM(v) - SUM(c) AS margen_usd_90d,
       CAST((SUM(v) - SUM(c)) / NULLIF(SUM(v),0) * 100 AS decimal(10,1)) AS margen_pct
FROM (
    SELECT rf.reng_neto / NULLIF(f.tasa,0) AS v, rf.total_art * rf.ult_cos_om AS c
    FROM dbo.reng_fac rf JOIN dbo.factura f ON f.fact_num = rf.fact_num
    WHERE f.anulada = 0 AND f.fec_emis >= DATEADD(day,-90,CAST(GETDATE() AS date))
    UNION ALL
    SELECT -rd.reng_neto / NULLIF(d.tasa,0), -rd.total_art * rd.ult_cos_om
    FROM dbo.reng_dvc rd JOIN dbo.dev_cli d ON d.fact_num = rd.fact_num
    WHERE d.anulada = 0 AND d.fec_emis >= DATEADD(day,-90,CAST(GETDATE() AS date))
) x;

-- 3) Líneas facturadas sin tasa (no se pueden pasar a $)
SELECT COUNT(*) AS lineas_sin_tasa_90d
FROM dbo.reng_fac rf JOIN dbo.factura f ON f.fact_num = rf.fact_num
WHERE f.anulada = 0 AND ISNULL(f.tasa,0) = 0
  AND f.fec_emis >= DATEADD(day,-90,CAST(GETDATE() AS date));

-- 4) Los 15 artículos con mayor valor de inventario en $ (revisar que tengan sentido)
SELECT TOP 15 RTRIM(a.co_art) AS co_art, RTRIM(a.art_des) AS descripcion,
       s.stock_act, a.ult_cos_om, s.stock_act * a.ult_cos_om AS valor_usd
FROM (SELECT co_art, SUM(stock_act) AS stock_act FROM dbo.st_almac GROUP BY co_art) s
JOIN dbo.art a ON a.co_art = s.co_art
WHERE s.stock_act > 0 AND a.anulado = 0
ORDER BY ABS(s.stock_act * a.ult_cos_om) DESC;

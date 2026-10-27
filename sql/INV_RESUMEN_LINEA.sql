/* =====================================================================
   INV_RESUMEN_LINEA.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Resumen por línea, TODO EN $: valor del inventario, venta, costo y
   margen 90 días, rotación, capital sin movimiento / baja rotación.
   ===================================================================== */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- solo lectura, no bloquea a caja/facturación

-- TODO EN $:  costo = ult_cos_om   |   venta = reng_neto / tasa (neto de descuento)
DECLARE @dias  int  = 90;                              -- ventana de análisis
DECLARE @hasta date = CAST(GETDATE() AS date);
DECLARE @desde date = DATEADD(day, -@dias, @hasta);
DECLARE @d decimal(10,2) = @dias;

WITH vta AS (
    SELECT rf.co_art,
           SUM(rf.total_art)                              AS uds,
           SUM(rf.reng_neto / NULLIF(f.tasa, 0))          AS venta_usd,
           SUM(rf.total_art * rf.ult_cos_om)              AS costo_usd
    FROM dbo.reng_fac rf
    JOIN dbo.factura f ON f.fact_num = rf.fact_num
    WHERE f.anulada = 0
      AND f.fec_emis >= @desde AND f.fec_emis < DATEADD(day, 1, @hasta)
    GROUP BY rf.co_art
), dev AS (
    SELECT rd.co_art,
           SUM(rd.total_art)                              AS uds,
           SUM(rd.reng_neto / NULLIF(d.tasa, 0))          AS venta_usd,
           SUM(rd.total_art * rd.ult_cos_om)              AS costo_usd
    FROM dbo.reng_dvc rd
    JOIN dbo.dev_cli d ON d.fact_num = rd.fact_num
    WHERE d.anulada = 0
      AND d.fec_emis >= @desde AND d.fec_emis < DATEADD(day, 1, @hasta)
    GROUP BY rd.co_art
), ult AS (
    SELECT rf.co_art, MAX(f.fec_emis) AS ult_venta
    FROM dbo.reng_fac rf
    JOIN dbo.factura f ON f.fact_num = rf.fact_num
    WHERE f.anulada = 0
    GROUP BY rf.co_art
), stk AS (
    SELECT co_art, SUM(stock_act) AS stock
    FROM dbo.st_almac
    GROUP BY co_art
), base AS (
    SELECT RTRIM(a.co_art)                                AS co_art,
           LEFT(RTRIM(ISNULL(a.art_des,'')), 200)         AS art_des,
           LEFT(RTRIM(ISNULL(a.modelo,'')), 60)           AS modelo,
           RTRIM(ISNULL(l.lin_des,  a.co_lin))            AS linea,
           RTRIM(ISNULL(sl.subl_des,a.co_subl))           AS sublinea,
           RTRIM(ISNULL(c.cat_des,  a.co_cat))            AS categoria,
           RTRIM(ISNULL(p.des_proc, a.procedenci))        AS procedencia,
           ISNULL(s.stock, 0)                             AS stock,
           ISNULL(a.ult_cos_om, 0)                        AS ult_cos_om,
           ISNULL(v.uds,0)       - ISNULL(d.uds,0)        AS uds,
           ISNULL(v.venta_usd,0) - ISNULL(d.venta_usd,0)  AS venta_usd,
           ISNULL(v.costo_usd,0) - ISNULL(d.costo_usd,0)  AS costo_usd,
           CAST(u.ult_venta  AS date)                     AS ult_venta,
           CAST(a.fec_ult_co AS date)                     AS ult_compra
    FROM dbo.art a
    LEFT JOIN stk s ON s.co_art = a.co_art
    LEFT JOIN vta v ON v.co_art = a.co_art
    LEFT JOIN dev d ON d.co_art = a.co_art
    LEFT JOIN ult u ON u.co_art = a.co_art
    LEFT JOIN dbo.lin_art  l  ON l.co_lin   = a.co_lin
    LEFT JOIN dbo.sub_lin  sl ON sl.co_subl = a.co_subl AND sl.co_lin = a.co_lin
    LEFT JOIN dbo.cat_art  c  ON c.co_cat   = a.co_cat
    LEFT JOIN dbo.proceden p  ON p.cod_proc = a.procedenci
    WHERE a.anulado = 0
), calc AS (
    SELECT b.*,
           b.stock * b.ult_cos_om                                   AS valor_usd,
           b.venta_usd - b.costo_usd                                AS margen_usd,
           CASE WHEN b.venta_usd > 0 THEN (b.venta_usd - b.costo_usd) / b.venta_usd * 100 END AS margen_pct,
           CASE WHEN b.uds > 0 THEN b.stock / (b.uds / @d) END      AS cobertura,
           CASE WHEN b.stock > 0 THEN b.uds / b.stock END           AS rotacion,  -- aprox.: stock actual como inventario promedio
           -- % acumulado de la venta en $ ANTES de este artículo (para ABC)
           CASE WHEN b.venta_usd > 0 THEN
               ISNULL(SUM(CASE WHEN b.venta_usd > 0 THEN b.venta_usd ELSE 0 END)
                      OVER (ORDER BY b.venta_usd DESC, b.co_art
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
               / NULLIF(SUM(CASE WHEN b.venta_usd > 0 THEN b.venta_usd ELSE 0 END) OVER (), 0)
           END AS acum_prev
    FROM base b
    WHERE b.stock <> 0 OR b.uds <> 0
), fin AS (
    SELECT c.*,
           CASE WHEN c.acum_prev IS NULL THEN '-'
                WHEN c.acum_prev < 0.80  THEN 'A'
                WHEN c.acum_prev < 0.95  THEN 'B'
                ELSE 'C' END AS clase_abc,
           CASE WHEN c.uds > 0 AND c.stock <= 0 THEN 'AGOTADO'
                WHEN c.uds <= 0                 THEN 'SIN MOVIMIENTO'
                WHEN c.cobertura <= 30          THEN 'ALTA'
                WHEN c.cobertura <= 90          THEN 'MEDIA'
                ELSE 'BAJA' END AS estado
    FROM calc c
)
, res AS (
    SELECT linea,
           COUNT(*)                                                       AS articulos,
           SUM(CASE WHEN stock > 0 THEN 1 ELSE 0 END)                     AS art_con_stock,
           SUM(CASE WHEN stock > 0 THEN valor_usd ELSE 0 END)             AS valor_inv_usd,
           SUM(venta_usd)                                                 AS venta_usd,
           SUM(costo_usd)                                                 AS costo_usd,
           SUM(costo_usd) / NULLIF(SUM(CASE WHEN stock > 0 THEN valor_usd ELSE 0 END), 0) AS rotacion,
           SUM(CASE WHEN estado = 'SIN MOVIMIENTO' THEN valor_usd ELSE 0 END) AS valor_sin_mov_usd,
           SUM(CASE WHEN estado = 'BAJA'           THEN valor_usd ELSE 0 END) AS valor_baja_rot_usd,
           SUM(CASE WHEN estado = 'AGOTADO'        THEN 1 ELSE 0 END)         AS agotados
    FROM fin
    GROUP BY linea
)
SELECT fila FROM (
    SELECT 0 AS ord, CAST(0 AS decimal(20,2)) AS k,
           'fecha_corte;linea;articulos;art_con_stock;valor_inv_usd;venta_usd_90d;costo_venta_usd_90d;margen_usd_90d;margen_pct;rotacion_90d;valor_sin_mov_usd;valor_baja_rot_usd;agotados' AS fila
    UNION ALL
    SELECT 1, -valor_inv_usd, CONCAT(
        CONVERT(varchar(10), @hasta, 23), ';', REPLACE(linea,';',','), ';',
        articulos, ';', art_con_stock, ';',
        CAST(valor_inv_usd AS decimal(20,2)), ';', CAST(venta_usd AS decimal(20,2)), ';', CAST(costo_usd AS decimal(20,2)), ';',
        CAST(venta_usd - costo_usd AS decimal(20,2)), ';',
        CAST(CASE WHEN venta_usd > 0 THEN (venta_usd - costo_usd) / venta_usd * 100 END AS decimal(20,1)), ';',
        CAST(rotacion AS decimal(20,2)), ';', CAST(valor_sin_mov_usd AS decimal(20,2)), ';', CAST(valor_baja_rot_usd AS decimal(20,2)), ';', agotados)
    FROM res
) x
ORDER BY ord, k;

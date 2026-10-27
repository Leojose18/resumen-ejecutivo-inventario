/* =====================================================================
   INV_RESUMEN_LINEA.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Resumen por línea: valor del inventario, rotación, capital sin
   movimiento y en baja rotación, agotados.  Base: HD_A01.
   ===================================================================== */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- solo lectura, no bloquea a caja/facturación

DECLARE @dias  int  = 90;                              -- ventana de análisis
DECLARE @hasta date = CAST(GETDATE() AS date);
DECLARE @desde date = DATEADD(day, -@dias, @hasta);
DECLARE @d decimal(10,2) = @dias;

WITH vta AS (
    SELECT rf.co_art,
           SUM(rf.total_art)                 AS uds,
           SUM(rf.total_art * rf.cos_pro_un) AS cv_bs,
           SUM(rf.total_art * rf.cos_pro_om) AS cv_om
    FROM dbo.reng_fac rf
    JOIN dbo.factura f ON f.fact_num = rf.fact_num
    WHERE f.anulada = 0
      AND f.fec_emis >= @desde AND f.fec_emis < DATEADD(day, 1, @hasta)
    GROUP BY rf.co_art
), dev AS (
    SELECT rd.co_art,
           SUM(rd.total_art)                 AS uds,
           SUM(rd.total_art * rd.cos_pro_un) AS cv_bs,
           SUM(rd.total_art * rd.cos_pro_om) AS cv_om
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
    SELECT RTRIM(a.co_art)                                   AS co_art,
           LEFT(RTRIM(ISNULL(a.art_des,'')), 200)            AS art_des,
           LEFT(RTRIM(ISNULL(a.modelo,'')), 60)              AS modelo,
           RTRIM(ISNULL(l.lin_des,  a.co_lin))               AS linea,
           RTRIM(ISNULL(sl.subl_des,a.co_subl))              AS sublinea,
           RTRIM(ISNULL(c.cat_des,  a.co_cat))               AS categoria,
           RTRIM(ISNULL(p.des_proc, a.procedenci))           AS procedencia,
           ISNULL(s.stock, 0)                                AS stock,
           ISNULL(a.cos_pro_un, 0)                           AS cos_pro_un,
           ISNULL(a.cos_pro_om, 0)                           AS cos_pro_om,
           ISNULL(v.uds,0)   - ISNULL(d.uds,0)               AS uds,
           ISNULL(v.cv_bs,0) - ISNULL(d.cv_bs,0)             AS cv_bs,
           ISNULL(v.cv_om,0) - ISNULL(d.cv_om,0)             AS cv_om,
           CAST(u.ult_venta  AS date)                        AS ult_venta,
           CAST(a.fec_ult_co AS date)                        AS ult_compra
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
           CASE WHEN b.uds > 0 THEN b.stock / (b.uds / @d) END AS cobertura,
           CASE WHEN b.stock > 0 THEN b.uds / b.stock END      AS rotacion,  -- aprox.: stock actual como inventario promedio
           CASE WHEN b.cv_om > 0 THEN
               ISNULL(SUM(CASE WHEN b.cv_om > 0 THEN b.cv_om ELSE 0 END)
                      OVER (ORDER BY b.cv_om DESC, b.co_art
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
               / NULLIF(SUM(CASE WHEN b.cv_om > 0 THEN b.cv_om ELSE 0 END) OVER (), 0)
           END AS acum_prev
    FROM base b
    WHERE b.stock <> 0 OR b.uds <> 0
), fin AS (
    SELECT c.*,
           c.stock * c.cos_pro_un AS valor_bs,
           c.stock * c.cos_pro_om AS valor_om,
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
           COUNT(*)                                                     AS articulos,
           SUM(CASE WHEN stock > 0 THEN 1 ELSE 0 END)                   AS art_con_stock,
           SUM(valor_bs)                                                AS valor_bs,
           SUM(valor_om)                                                AS valor_om,
           SUM(cv_om)                                                   AS costo_venta_om,
           SUM(cv_om) / NULLIF(SUM(CASE WHEN stock > 0 THEN valor_om ELSE 0 END), 0) AS rotacion,
           SUM(CASE WHEN estado = 'SIN MOVIMIENTO' THEN valor_om ELSE 0 END) AS valor_sin_mov_om,
           SUM(CASE WHEN estado = 'BAJA'           THEN valor_om ELSE 0 END) AS valor_baja_rot_om,
           SUM(CASE WHEN estado = 'AGOTADO'        THEN 1 ELSE 0 END)        AS agotados
    FROM fin
    GROUP BY linea
)
SELECT fila FROM (
    SELECT 0 AS ord, CAST(0 AS decimal(20,2)) AS k,
           'fecha_corte;linea;articulos;art_con_stock;valor_bs;valor_om;costo_venta_om_90d;rotacion;valor_sin_mov_om;valor_baja_rot_om;agotados' AS fila
    UNION ALL
    SELECT 1, -valor_om, CONCAT(
        CONVERT(varchar(10), @hasta, 23), ';', REPLACE(linea,';',','), ';',
        articulos, ';', art_con_stock, ';',
        CAST(valor_bs AS decimal(20,2)), ';', CAST(valor_om AS decimal(20,2)), ';',
        CAST(costo_venta_om AS decimal(20,2)), ';', CAST(rotacion AS decimal(18,2)), ';',
        CAST(valor_sin_mov_om AS decimal(20,2)), ';', CAST(valor_baja_rot_om AS decimal(20,2)), ';', agotados)
    FROM res
) x
ORDER BY ord, k;

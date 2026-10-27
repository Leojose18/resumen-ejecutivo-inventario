/* =====================================================================
   INV_VERIFICAR.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Abrir en SSMS sobre HD_A01, ejecutar (F5) y mandar capturas.
   ===================================================================== */
USE HD_A01;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- 1) ¿El costo en $ (cos_pro_om) está cargado en los artículos con stock?
SELECT COUNT(*) AS art_con_stock,
       SUM(CASE WHEN cos_pro_om > 0 THEN 1 ELSE 0 END) AS con_cos_om,
       SUM(CASE WHEN cos_pro_un > 0 THEN 1 ELSE 0 END) AS con_cos_bs
FROM dbo.art WHERE stock_act > 0 AND anulado = 0;

-- 2) Facturas de los últimos 90 días (base de la rotación)
SELECT COUNT(*) AS facturas_90d
FROM dbo.factura WHERE anulada = 0 AND fec_emis >= DATEADD(day,-90,GETDATE());

-- 3) ¿Existen notas de entrega? (si dan error, no se usan; ignorar)
SELECT COUNT(*) AS notas_entrega_90d
FROM dbo.nota_ent WHERE anulada = 0 AND fec_emis >= DATEADD(day,-90,GETDATE());

-- 4) Cuadre: stock en art vs suma de almacenes
SELECT COUNT(*) AS articulos_descuadrados
FROM dbo.art a
JOIN (SELECT co_art, SUM(stock_act) s FROM dbo.st_almac GROUP BY co_art) x ON x.co_art = a.co_art
WHERE ABS(a.stock_act - x.s) > 0.001;

-- 5) Valor total del inventario hoy
SELECT SUM(s.stock_act * a.cos_pro_un) AS valor_bs,
       SUM(s.stock_act * a.cos_pro_om) AS valor_om
FROM dbo.st_almac s JOIN dbo.art a ON a.co_art = s.co_art
WHERE s.stock_act > 0;

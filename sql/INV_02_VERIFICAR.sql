/* =====================================================================
   INV_02_VERIFICAR.sql  -  Correr después de INV_01_INSTALAR.sql
   Ejecuta el informe una vez y muestra 5 chequeos. Mándame las capturas.
   ===================================================================== */
USE KD_REPORTES;
EXEC dbo.SP_INV_SNAPSHOT;
EXEC dbo.SP_INV_INFORME 90;

-- 1) ¿El costo en otra moneda ($) está cargado? Si con_cos_om es muy bajo,
--    hay que valorar en Bs o con tasa.
SELECT COUNT(*) AS art_con_stock,
       SUM(CASE WHEN cos_pro_om > 0 THEN 1 ELSE 0 END) AS con_cos_om,
       SUM(CASE WHEN cos_pro_un > 0 THEN 1 ELSE 0 END) AS con_cos_bs
FROM HD_A01.dbo.art WHERE stock_act > 0 AND anulado = 0;

-- 2) ¿Venden con Notas de Entrega sin facturar? Si hay muchas, hay que sumarlas
--    a la rotación (hoy solo cuenta facturas).
SELECT 'notas_entrega_90d' AS doc, COUNT(*) AS cantidad
FROM HD_A01.dbo.nota_ent WHERE anulada = 0 AND fec_emis >= DATEADD(day,-90,GETDATE())
UNION ALL
SELECT 'facturas_90d', COUNT(*)
FROM HD_A01.dbo.factura  WHERE anulada = 0 AND fec_emis >= DATEADD(day,-90,GETDATE());
-- (si nota_ent no existe, ignora el error de este bloque y avísame)

-- 3) Cuadre: stock de art vs suma de almacenes (debería dar ~0 diferencias)
SELECT COUNT(*) AS articulos_descuadrados
FROM HD_A01.dbo.art a
JOIN (SELECT co_art, SUM(stock_act) s FROM HD_A01.dbo.st_almac GROUP BY co_art) x
  ON x.co_art = a.co_art
WHERE ABS(a.stock_act - x.s) > 0.001;

-- 4) Resumen por estado
SELECT estado, COUNT(*) AS articulos, SUM(valor_om) AS valor_om, SUM(valor_bs) AS valor_bs
FROM dbo.INV_ROTACION_KD GROUP BY estado ORDER BY valor_om DESC;

-- 5) Top 10 de mayor y de menor rotación (para revisar que tenga sentido)
SELECT TOP 10 co_art, art_des, linea, stock, uds_vendidas, cobertura_dias, estado
FROM dbo.INV_ROTACION_KD WHERE uds_vendidas > 0 ORDER BY uds_vendidas DESC;

SELECT TOP 10 co_art, art_des, linea, stock, valor_om, dias_sin_venta, ult_compra
FROM dbo.INV_ROTACION_KD WHERE estado = 'SIN MOVIMIENTO' ORDER BY valor_om DESC;

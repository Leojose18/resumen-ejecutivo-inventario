/* =====================================================================
   INV_FOTO.sql  -  SOLO CONSULTA (no modifica la base de datos)
   Foto del inventario por almacén valorado en $ con ult_cos_om
   (costeo a la fecha). El job la guarda en salidas\historico\
   ===================================================================== */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @hoy date = CAST(GETDATE() AS date);

SELECT fila FROM (
    SELECT 0 AS ord, '' AS k1, '' AS k2,
           'fecha;co_alma;almacen;co_art;descripcion;linea;stock;ult_cos_usd;valor_usd' AS fila
    UNION ALL
    SELECT 1, RTRIM(s.co_alma), RTRIM(s.co_art), CONCAT(
        CONVERT(varchar(10), @hoy, 23), ';', RTRIM(s.co_alma), ';', REPLACE(RTRIM(ISNULL(al.alma_des,'')),';',','), ';',
        RTRIM(s.co_art), ';', REPLACE(RTRIM(ISNULL(a.art_des,'')),';',','), ';',
        REPLACE(RTRIM(ISNULL(l.lin_des, a.co_lin)),';',','), ';',
        CAST(s.stock_act AS decimal(18,2)), ';',
        CAST(ISNULL(a.ult_cos_om,0) AS decimal(18,2)), ';',
        CAST(s.stock_act * ISNULL(a.ult_cos_om,0) AS decimal(20,2)))
    FROM dbo.st_almac s
    JOIN dbo.art a ON a.co_art = s.co_art
    LEFT JOIN dbo.almacen al ON al.co_alma = s.co_alma
    LEFT JOIN dbo.lin_art l  ON l.co_lin   = a.co_lin
    WHERE s.stock_act <> 0
) x
ORDER BY ord, k1, k2;

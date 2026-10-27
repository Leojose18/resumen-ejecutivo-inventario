/* =====================================================================
   INV_01_INSTALAR.sql  -  Informe semanal de inventario Krash Depot
   Correr UNA sola vez en SSMS (servidor WIN-KRASHDEPOT).
   Crea una base aparte (KD_REPORTES) para no tocar las tablas de Profit.
   Compatible con SQL Server 2014.
   ===================================================================== */

IF DB_ID('KD_REPORTES') IS NULL CREATE DATABASE KD_REPORTES;
GO
USE KD_REPORTES;
GO

/* ---------- 1. Foto semanal del inventario (costeo a fecha) ---------- */
IF OBJECT_ID('dbo.INV_SNAPSHOT_KD','U') IS NULL
CREATE TABLE dbo.INV_SNAPSHOT_KD (
    fecha       date           NOT NULL,
    co_alma     varchar(10)    NOT NULL,
    co_art      varchar(30)    NOT NULL,
    stock       decimal(18,4)  NOT NULL,
    cos_pro_un  decimal(18,4)  NULL,   -- costo promedio Bs
    cos_pro_om  decimal(18,4)  NULL,   -- costo promedio otra moneda ($)
    valor_bs    decimal(20,2)  NULL,
    valor_om    decimal(20,2)  NULL,
    CONSTRAINT PK_INV_SNAPSHOT_KD PRIMARY KEY (fecha, co_alma, co_art)
);
GO

/* ---------- 2. Resultado del informe (se recalcula cada semana) ---------- */
IF OBJECT_ID('dbo.INV_ROTACION_KD','U') IS NULL
CREATE TABLE dbo.INV_ROTACION_KD (
    fecha_corte     date,
    dias_periodo    int,
    co_art          varchar(30),
    art_des         varchar(200),
    modelo          varchar(60),
    linea           varchar(80),
    sublinea        varchar(80),
    categoria       varchar(80),
    procedencia     varchar(60),
    stock           decimal(18,2),
    cos_pro_un      decimal(18,4),
    cos_pro_om      decimal(18,4),
    valor_bs        decimal(20,2),
    valor_om        decimal(20,2),
    uds_vendidas    decimal(18,2),   -- netas de devoluciones
    costo_venta_bs  decimal(20,2),
    costo_venta_om  decimal(20,2),
    venta_diaria    decimal(18,4),
    cobertura_dias  decimal(18,1),   -- stock / venta diaria
    inv_prom_uds    decimal(18,2),
    rotacion        decimal(18,2),   -- uds vendidas / inventario promedio
    ult_venta       date,
    dias_sin_venta  int,
    ult_compra      date,
    clase_abc       char(1),
    estado          varchar(20)      -- ALTA / MEDIA / BAJA / SIN MOVIMIENTO / AGOTADO
);
GO

/* ---------- 3. Proc: tomar la foto (solo con la fecha de hoy) ---------- */
IF OBJECT_ID('dbo.SP_INV_SNAPSHOT','P') IS NOT NULL DROP PROCEDURE dbo.SP_INV_SNAPSHOT;
GO
CREATE PROCEDURE dbo.SP_INV_SNAPSHOT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy date = CAST(GETDATE() AS date);

    DELETE dbo.INV_SNAPSHOT_KD WHERE fecha = @hoy;   -- permite re-ejecutar el mismo día

    INSERT dbo.INV_SNAPSHOT_KD (fecha, co_alma, co_art, stock, cos_pro_un, cos_pro_om, valor_bs, valor_om)
    SELECT @hoy, RTRIM(s.co_alma), RTRIM(s.co_art), s.stock_act,
           a.cos_pro_un, a.cos_pro_om,
           s.stock_act * a.cos_pro_un,
           s.stock_act * a.cos_pro_om
    FROM HD_A01.dbo.st_almac s
    JOIN HD_A01.dbo.art a ON a.co_art = s.co_art
    WHERE s.stock_act <> 0;
END
GO

/* ---------- 4. Proc: calcular rotación, cobertura, ABC y estado ---------- */
IF OBJECT_ID('dbo.SP_INV_INFORME','P') IS NOT NULL DROP PROCEDURE dbo.SP_INV_INFORME;
GO
CREATE PROCEDURE dbo.SP_INV_INFORME
    @dias int = 90          -- ventana de análisis de ventas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hasta date = CAST(GETDATE() AS date);
    DECLARE @desde date = DATEADD(day, -@dias, @hasta);
    DECLARE @d decimal(10,2) = @dias;
    -- Si ya hay 2+ fotos en la ventana, el inventario promedio sale de ellas;
    -- si no, se usa el stock actual como aproximación.
    DECLARE @nsnap int = (SELECT COUNT(DISTINCT fecha) FROM dbo.INV_SNAPSHOT_KD
                          WHERE fecha > @desde AND fecha <= @hasta);

    TRUNCATE TABLE dbo.INV_ROTACION_KD;

    ;WITH vta AS (
        SELECT rf.co_art,
               SUM(rf.total_art)                 AS uds,
               SUM(rf.total_art * rf.cos_pro_un) AS cv_bs,
               SUM(rf.total_art * rf.cos_pro_om) AS cv_om
        FROM HD_A01.dbo.reng_fac rf
        JOIN HD_A01.dbo.factura f ON f.fact_num = rf.fact_num
        WHERE f.anulada = 0
          AND f.fec_emis >= @desde AND f.fec_emis < DATEADD(day, 1, @hasta)
        GROUP BY rf.co_art
    ), dev AS (
        SELECT rd.co_art,
               SUM(rd.total_art)                 AS uds,
               SUM(rd.total_art * rd.cos_pro_un) AS cv_bs,
               SUM(rd.total_art * rd.cos_pro_om) AS cv_om
        FROM HD_A01.dbo.reng_dvc rd
        JOIN HD_A01.dbo.dev_cli d ON d.fact_num = rd.fact_num
        WHERE d.anulada = 0
          AND d.fec_emis >= @desde AND d.fec_emis < DATEADD(day, 1, @hasta)
        GROUP BY rd.co_art
    ), ult AS (
        SELECT rf.co_art, MAX(f.fec_emis) AS ult_venta
        FROM HD_A01.dbo.reng_fac rf
        JOIN HD_A01.dbo.factura f ON f.fact_num = rf.fact_num
        WHERE f.anulada = 0
        GROUP BY rf.co_art
    ), stk AS (
        SELECT co_art, SUM(stock_act) AS stock
        FROM HD_A01.dbo.st_almac
        GROUP BY co_art
    ), snp AS (
        SELECT co_art, SUM(stock) AS sum_stock
        FROM dbo.INV_SNAPSHOT_KD
        WHERE fecha > @desde AND fecha <= @hasta
        GROUP BY co_art
    ), base AS (
        SELECT RTRIM(a.co_art)                                  AS co_art,
               LEFT(RTRIM(ISNULL(a.art_des,'')), 200)           AS art_des,
               LEFT(RTRIM(ISNULL(a.modelo,'')), 60)             AS modelo,
               LEFT(RTRIM(ISNULL(l.lin_des,  a.co_lin)), 80)    AS linea,
               LEFT(RTRIM(ISNULL(sl.subl_des,a.co_subl)), 80)   AS sublinea,
               LEFT(RTRIM(ISNULL(c.cat_des,  a.co_cat)), 80)    AS categoria,
               LEFT(RTRIM(ISNULL(p.des_proc, a.procedenci)), 60) AS procedencia,
               ISNULL(s.stock, 0)                               AS stock,
               a.cos_pro_un, a.cos_pro_om,
               ISNULL(v.uds,0)   - ISNULL(d.uds,0)              AS uds,
               ISNULL(v.cv_bs,0) - ISNULL(d.cv_bs,0)            AS cv_bs,
               ISNULL(v.cv_om,0) - ISNULL(d.cv_om,0)            AS cv_om,
               CASE WHEN @nsnap >= 2 THEN ISNULL(sn.sum_stock,0) / @nsnap
                    ELSE ISNULL(s.stock,0) END                  AS inv_prom,
               CAST(u.ult_venta  AS date)                       AS ult_venta,
               CAST(a.fec_ult_co AS date)                       AS ult_compra
        FROM HD_A01.dbo.art a
        LEFT JOIN stk s  ON s.co_art = a.co_art
        LEFT JOIN vta v  ON v.co_art = a.co_art
        LEFT JOIN dev d  ON d.co_art = a.co_art
        LEFT JOIN ult u  ON u.co_art = a.co_art
        LEFT JOIN snp sn ON sn.co_art = RTRIM(a.co_art) COLLATE DATABASE_DEFAULT
        LEFT JOIN HD_A01.dbo.lin_art  l  ON l.co_lin   = a.co_lin
        LEFT JOIN HD_A01.dbo.sub_lin  sl ON sl.co_subl = a.co_subl AND sl.co_lin = a.co_lin
        LEFT JOIN HD_A01.dbo.cat_art  c  ON c.co_cat   = a.co_cat
        LEFT JOIN HD_A01.dbo.proceden p  ON p.cod_proc = a.procedenci
        WHERE a.anulado = 0
    ), calc AS (
        SELECT b.*,
               -- % acumulado del costo de venta ANTES de este artículo (para ABC)
               CASE WHEN b.cv_om > 0 THEN
                   ISNULL(SUM(CASE WHEN b.cv_om > 0 THEN b.cv_om ELSE 0 END)
                          OVER (ORDER BY b.cv_om DESC, b.co_art
                                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
                   / NULLIF(SUM(CASE WHEN b.cv_om > 0 THEN b.cv_om ELSE 0 END) OVER (), 0)
               END AS acum_prev
        FROM base b
        WHERE b.stock <> 0 OR b.uds <> 0
    )
    INSERT dbo.INV_ROTACION_KD
    SELECT @hasta, @dias, co_art, art_des, modelo, linea, sublinea, categoria, procedencia,
           stock, cos_pro_un, cos_pro_om,
           stock * cos_pro_un, stock * cos_pro_om,
           uds, cv_bs, cv_om,
           uds / @d,
           CASE WHEN uds > 0 THEN stock / (uds / @d) END,
           inv_prom,
           CASE WHEN inv_prom > 0 THEN uds / inv_prom END,
           ult_venta,
           DATEDIFF(day, ult_venta, @hasta),
           ult_compra,
           CASE WHEN acum_prev IS NULL THEN '-'
                WHEN acum_prev < 0.80  THEN 'A'
                WHEN acum_prev < 0.95  THEN 'B'
                ELSE 'C' END,
           CASE WHEN uds > 0 AND stock <= 0           THEN 'AGOTADO'
                WHEN uds <= 0                         THEN 'SIN MOVIMIENTO'
                WHEN stock / (uds / @d) <= 30         THEN 'ALTA'
                WHEN stock / (uds / @d) <= 90         THEN 'MEDIA'
                ELSE 'BAJA' END
    FROM calc;
END
GO

/* ---------- 5. Resumen por línea ---------- */
IF OBJECT_ID('dbo.V_INV_RESUMEN_LINEA','V') IS NOT NULL DROP VIEW dbo.V_INV_RESUMEN_LINEA;
GO
CREATE VIEW dbo.V_INV_RESUMEN_LINEA AS
SELECT fecha_corte, linea,
       COUNT(*)                                                    AS articulos,
       SUM(CASE WHEN stock > 0 THEN 1 ELSE 0 END)                  AS art_con_stock,
       SUM(valor_bs)                                               AS valor_bs,
       SUM(valor_om)                                               AS valor_om,
       SUM(costo_venta_om)                                         AS costo_venta_om,
       SUM(costo_venta_om) / NULLIF(SUM(inv_prom_uds * cos_pro_om), 0) AS rotacion,
       SUM(CASE WHEN estado = 'SIN MOVIMIENTO' THEN valor_om ELSE 0 END) AS valor_sin_mov_om,
       SUM(CASE WHEN estado = 'BAJA'           THEN valor_om ELSE 0 END) AS valor_baja_rot_om,
       SUM(CASE WHEN estado = 'AGOTADO'        THEN 1 ELSE 0 END)        AS agotados
FROM dbo.INV_ROTACION_KD
GROUP BY fecha_corte, linea;
GO

/* ---------- 6. Vistas de salida para bcp (con encabezado, separador ;) ---------- */
IF OBJECT_ID('dbo.V_CSV_ROTACION','V') IS NOT NULL DROP VIEW dbo.V_CSV_ROTACION;
GO
CREATE VIEW dbo.V_CSV_ROTACION AS
SELECT 0 AS ord, CAST('fecha_corte;co_art;descripcion;modelo;linea;sublinea;categoria;procedencia;stock;cos_pro_un;cos_pro_om;valor_bs;valor_om;uds_vendidas;costo_venta_bs;costo_venta_om;venta_diaria;cobertura_dias;inv_prom_uds;rotacion;ult_venta;dias_sin_venta;ult_compra;clase_abc;estado' AS varchar(2000)) AS fila
UNION ALL
SELECT 1, CAST(CONCAT(
    CONVERT(varchar(10), fecha_corte, 23), ';', co_art, ';',
    REPLACE(art_des,';',','), ';', REPLACE(modelo,';',','), ';',
    REPLACE(linea,';',','), ';', REPLACE(sublinea,';',','), ';',
    REPLACE(categoria,';',','), ';', procedencia, ';',
    stock, ';', cos_pro_un, ';', cos_pro_om, ';', valor_bs, ';', valor_om, ';',
    uds_vendidas, ';', costo_venta_bs, ';', costo_venta_om, ';', venta_diaria, ';',
    cobertura_dias, ';', inv_prom_uds, ';', rotacion, ';',
    CONVERT(varchar(10), ult_venta, 23), ';', dias_sin_venta, ';',
    CONVERT(varchar(10), ult_compra, 23), ';', clase_abc, ';', estado) AS varchar(2000))
FROM dbo.INV_ROTACION_KD;
GO

IF OBJECT_ID('dbo.V_CSV_RESUMEN_LINEA','V') IS NOT NULL DROP VIEW dbo.V_CSV_RESUMEN_LINEA;
GO
CREATE VIEW dbo.V_CSV_RESUMEN_LINEA AS
SELECT 0 AS ord, CAST('fecha_corte;linea;articulos;art_con_stock;valor_bs;valor_om;costo_venta_om;rotacion;valor_sin_mov_om;valor_baja_rot_om;agotados' AS varchar(1000)) AS fila
UNION ALL
SELECT 1, CAST(CONCAT(
    CONVERT(varchar(10), fecha_corte, 23), ';', REPLACE(linea,';',','), ';',
    articulos, ';', art_con_stock, ';', valor_bs, ';', valor_om, ';',
    costo_venta_om, ';', CAST(rotacion AS decimal(18,2)), ';',
    valor_sin_mov_om, ';', valor_baja_rot_om, ';', agotados) AS varchar(1000))
FROM dbo.V_INV_RESUMEN_LINEA;
GO

PRINT 'Instalación terminada. Ahora corre INV_02_VERIFICAR.sql';

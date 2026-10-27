@echo off
REM ==================================================================
REM  JOB_INVENTARIO_KD.cmd  -  Paso CmdExec del job semanal (SQL Agent)
REM  SOLO CONSULTA: ejecuta SELECT sobre HD_A01 y guarda archivos CSV.
REM  No crea, modifica ni borra nada en la base de datos.
REM  Comando del paso:
REM    cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"
REM ==================================================================
setlocal
set "BASE=D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%\job\EXPORTAR_CSV.ps1""

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "HOY=%%i"

REM 1) Detalle por articulo (se sobreescribe)
%PS% "%BASE%\sql\INV_ROTACION.sql" "%BASE%\salidas\INV_ROTACION_KD.csv" || exit /b 1

REM 2) Resumen por linea (se sobreescribe)
%PS% "%BASE%\sql\INV_RESUMEN_LINEA.sql" "%BASE%\salidas\INV_RESUMEN_LINEA_KD.csv" || exit /b 1

REM 3) Venta diaria por linea desde hace dos anos (analisis por semana, mes y ano)
%PS% "%BASE%\sql\INV_VENTAS_DIARIAS.sql" "%BASE%\salidas\INV_VENTAS_DIARIAS_KD.csv" || exit /b 1

REM 4) Foto del inventario a la fecha (archivo nuevo cada semana = costeo historico)
%PS% "%BASE%\sql\INV_FOTO.sql" "%BASE%\salidas\historico\INV_FOTO_%HOY%.csv" || exit /b 1

exit /b 0

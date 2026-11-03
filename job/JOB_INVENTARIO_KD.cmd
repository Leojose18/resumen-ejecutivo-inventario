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

REM 3b) Venta diaria por vendedor y articulo desde el 1 de enero del ano pasado (seccion de vendedores)
%PS% "%BASE%\sql\INV_VENTAS_VENDEDOR.sql" "%BASE%\salidas\INV_VENTAS_VENDEDOR_KD.csv" || echo AVISO: no se pudo exportar ventas por vendedor; el informe sale sin esa seccion

REM 4) Foto del inventario a la fecha (archivo nuevo cada semana = costeo historico)
%PS% "%BASE%\sql\INV_FOTO.sql" "%BASE%\salidas\historico\INV_FOTO_%HOY%.csv" || exit /b 1

REM 5) Correo HTML del resumen ejecutivo (lee los CSV de arriba; no toca la base de datos)
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%\job\GENERAR_EMAIL.ps1" "%BASE%" || exit /b 1

REM 6) Informe interactivo HTML con graficas + PDF (Chrome/Edge invisible; no toca la base de datos)
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%\job\GENERAR_DASHBOARD.ps1" "%BASE%" || exit /b 1

exit /b 0

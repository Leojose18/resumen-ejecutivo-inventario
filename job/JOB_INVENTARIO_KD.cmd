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
set "SQLOPT=-S WIN-KRASHDEPOT -E -d HD_A01 -b -W -h -1"

if not exist "%BASE%\salidas\historico" mkdir "%BASE%\salidas\historico"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "HOY=%%i"

REM 1) Detalle por articulo (se sobreescribe: mismo File ID en Drive)
sqlcmd %SQLOPT% -i "%BASE%\sql\INV_ROTACION.sql" -o "%BASE%\salidas\INV_ROTACION_KD.csv"
if errorlevel 1 exit /b 1

REM 2) Resumen por linea (se sobreescribe)
sqlcmd %SQLOPT% -i "%BASE%\sql\INV_RESUMEN_LINEA.sql" -o "%BASE%\salidas\INV_RESUMEN_LINEA_KD.csv"
if errorlevel 1 exit /b 1

REM 3) Foto del inventario a la fecha (archivo nuevo cada semana = costeo historico)
sqlcmd %SQLOPT% -i "%BASE%\sql\INV_FOTO.sql" -o "%BASE%\salidas\historico\INV_FOTO_%HOY%.csv"
if errorlevel 1 exit /b 1

exit /b 0

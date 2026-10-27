@echo off
REM ==================================================================
REM  JOB_INVENTARIO_KD.cmd  -  Paso CmdExec del job semanal (SQL Agent)
REM  Comando del paso:  cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"
REM  1) Toma la foto del inventario  2) Calcula el informe
REM  3) Exporta 2 CSV (separador ;) que se sobreescriben en el mismo lugar
REM     (sin borrar antes, para que Drive conserve el mismo File ID)
REM ==================================================================

if not exist "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\salidas" mkdir "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\salidas"

sqlcmd -S WIN-KRASHDEPOT -E -d KD_REPORTES -b -Q "EXEC dbo.SP_INV_SNAPSHOT; EXEC dbo.SP_INV_INFORME 90"
if errorlevel 1 exit /b 1

bcp "SELECT fila FROM KD_REPORTES.dbo.V_CSV_ROTACION ORDER BY ord, fila" queryout "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\salidas\INV_ROTACION_KD.csv" -c -C ACP -T -S WIN-KRASHDEPOT
if errorlevel 1 exit /b 1

bcp "SELECT fila FROM KD_REPORTES.dbo.V_CSV_RESUMEN_LINEA ORDER BY ord, fila" queryout "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\salidas\INV_RESUMEN_LINEA_KD.csv" -c -C ACP -T -S WIN-KRASHDEPOT
if errorlevel 1 exit /b 1

exit /b 0

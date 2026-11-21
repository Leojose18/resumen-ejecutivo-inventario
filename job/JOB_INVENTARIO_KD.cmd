@echo off
REM ==================================================================
REM  JOB_INVENTARIO_KD.cmd  -  Paso CmdExec del job semanal (SQL Agent)
REM  SOLO CONSULTA: ejecuta SELECT sobre HD_A01 y guarda archivos CSV.
REM  No crea, modifica ni borra nada en la base de datos.
REM  Comando del paso:
REM    cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"
REM  Cada ejecucion deja su bitacora en salidas\JOB_LOG.txt (se sincroniza con Drive)
REM ==================================================================
setlocal
set "BASE=D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%\job\EXPORTAR_CSV.ps1""
set "LOG=%BASE%\salidas\JOB_LOG.txt"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "HOY=%%i"
echo ===== Inicio %date% %time% (usuario %USERNAME%) ===== > "%LOG%"

echo [1] INV_ROTACION %time% >> "%LOG%"
%PS% "%BASE%\sql\INV_ROTACION.sql" "%BASE%\salidas\INV_ROTACION_KD.csv" >> "%LOG%" 2>&1 || (echo ERROR en paso 1 >> "%LOG%" & exit /b 1)

echo [2] INV_RESUMEN_LINEA %time% >> "%LOG%"
%PS% "%BASE%\sql\INV_RESUMEN_LINEA.sql" "%BASE%\salidas\INV_RESUMEN_LINEA_KD.csv" >> "%LOG%" 2>&1 || (echo ERROR en paso 2 >> "%LOG%" & exit /b 1)

echo [3] INV_VENTAS_DIARIAS %time% >> "%LOG%"
%PS% "%BASE%\sql\INV_VENTAS_DIARIAS.sql" "%BASE%\salidas\INV_VENTAS_DIARIAS_KD.csv" >> "%LOG%" 2>&1 || (echo ERROR en paso 3 >> "%LOG%" & exit /b 1)

echo [3b] INV_VENTAS_VENDEDOR %time% >> "%LOG%"
%PS% "%BASE%\sql\INV_VENTAS_VENDEDOR.sql" "%BASE%\salidas\INV_VENTAS_VENDEDOR_KD.csv" >> "%LOG%" 2>&1 || echo AVISO: no se pudo exportar ventas por vendedor; el informe sale sin esa seccion >> "%LOG%"

echo [4] INV_FOTO %time% >> "%LOG%"
%PS% "%BASE%\sql\INV_FOTO.sql" "%BASE%\salidas\historico\INV_FOTO_%HOY%.csv" >> "%LOG%" 2>&1 || (echo ERROR en paso 4 >> "%LOG%" & exit /b 1)

echo [5] GENERAR_EMAIL %time% >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%\job\GENERAR_EMAIL.ps1" "%BASE%" >> "%LOG%" 2>&1 || (echo ERROR en paso 5 >> "%LOG%" & exit /b 1)

echo [6] GENERAR_DASHBOARD %time% >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%\job\GENERAR_DASHBOARD.ps1" "%BASE%" >> "%LOG%" 2>&1 || (echo ERROR en paso 6 >> "%LOG%" & exit /b 1)

echo ===== Fin OK %date% %time% ===== >> "%LOG%"
exit /b 0

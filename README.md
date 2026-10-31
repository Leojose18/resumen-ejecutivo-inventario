# Resumen Ejecutivo de Inventario - Krash Depot

Informe semanal de inventario desde Profit Plus Administrativo 2K8 (SQL Server 2014, base HD_A01).

**Regla del proyecto: todo es SOLO CONSULTA.** Ningún script ni job crea, modifica ni borra
objetos o datos en SQL Server. Solo se ejecutan SELECT y el resultado se guarda en archivos CSV.

## Qué calcula
- TODO EN $: inventario valorado con `ult_cos_om`; ventas = `reng_neto / tasa` (neto de descuento); costo de venta = `ult_cos_om` de cada línea
- Ventas, costo y margen en $ de 90 días (facturas menos devoluciones), venta diaria y cobertura en días
- Rotación (aprox. con stock actual) y clasificación ABC por venta en $
- Estado: ALTA (≤30 días de cobertura) / MEDIA (≤90) / BAJA (>90) / NUEVO INGRESO (sin ventas, comprado hace ≤30 días) / SIN MOVIMIENTO / AGOTADO
- Foto semanal fechada del inventario por almacén = costeo a una fecha

## Estructura
| Archivo | Uso |
|---|---|
| `sql/INV_ROTACION.sql` | Detalle por artículo |
| `sql/INV_RESUMEN_LINEA.sql` | Resumen por línea |
| `sql/INV_VENTAS_DIARIAS.sql` | Venta, costo y unidades por día y línea desde el 1 de enero de hace dos años |
| `sql/INV_FOTO.sql` | Foto del inventario por almacén con costo |
| `sql/INV_VERIFICAR.sql` | Chequeos de calidad de datos (correr a mano en SSMS) |
| `job/JOB_INVENTARIO_KD.cmd` | Paso CmdExec del job semanal |
| `job/GENERAR_EMAIL.ps1` | Arma el correo HTML del resumen ejecutivo a partir de los CSV (no toca la base de datos) |
| `job/EXPORTAR_CSV.ps1` | Ejecuta cada consulta en conexión de solo lectura y escribe el CSV; rechaza cualquier archivo .sql con sentencias de escritura |

## Salidas (`salidas\`)
- `INV_ROTACION_KD.csv` y `INV_RESUMEN_LINEA_KD.csv`: se sobreescriben cada semana (File ID estable en Drive)
- `INV_VENTAS_DIARIAS_KD.csv`: venta diaria por línea, base del análisis por semana, mes y año (se sobreescribe)
- `INV_EMAIL_KD.html`: correo del resumen ejecutivo; Make lo envía por Gmail cuando se actualiza
- `historico\INV_FOTO_AAAAMMDD.csv`: un archivo por semana para el costeo a fecha

## Instalación
1. Abrir `sql/INV_VERIFICAR.sql` en SSMS y ejecutar (F5)
2. Crear job semanal (domingo en la noche) con un paso CmdExec:
   `cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"`
3. Opcional, recomendado: que el job corra con un usuario que solo tenga `db_datareader` en HD_A01

## Tablas de Profit consultadas
`art`, `st_almac`, `almacen`, `lin_art`, `sub_lin`, `cat_art`, `proceden`, `factura`, `reng_fac`, `dev_cli`, `reng_dvc`

## Informe interactivo (HTML + PDF)

El paso 6 del job ejecuta `job/GENERAR_DASHBOARD.ps1`, que no toca la base de datos:

- Lee `INV_ROTACION_KD.csv` e `INV_VENTAS_DIARIAS_KD.csv` y los inserta en `job/DASHBOARD_TEMPLATE.html`.
- Escribe `salidas/INV_DASHBOARD_KD.html`: KPIs, lectura automática, ventas por semana/mes/año contra el año anterior, temporada, estados de rotación, desempeño por línea y listas de artículos. Filtro por línea y botón **Descargar PDF**.
- Imprime el mismo HTML a `salidas/INV_DASHBOARD_KD.pdf` con Chrome o Edge en modo invisible (perfil temporal en `%TEMP%\kd_dashboard`, fuera de la carpeta de Drive).
- Make adjunta el PDF y el HTML al correo diario junto con el CSV de líneas.

Requisito en el servidor: Google Chrome o Microsoft Edge instalado.

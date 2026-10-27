# Resumen Ejecutivo de Inventario - Krash Depot

Informe semanal de inventario desde Profit Plus Administrativo 2K8 (SQL Server 2014, base HD_A01).

**Regla del proyecto: todo es SOLO CONSULTA.** Ningún script ni job crea, modifica ni borra
objetos o datos en SQL Server. Solo se ejecutan SELECT y el resultado se guarda en archivos CSV.

## Qué calcula
- Valor del inventario (Bs y $) por artículo, línea, categoría y procedencia
- Ventas netas de 90 días (facturas menos devoluciones), venta diaria y cobertura en días
- Rotación (aprox. con stock actual) y clasificación ABC por costo de venta
- Estado: ALTA (≤30 días de cobertura) / MEDIA (≤90) / BAJA (>90) / SIN MOVIMIENTO / AGOTADO
- Foto semanal fechada del inventario por almacén = costeo a una fecha

## Estructura
| Archivo | Uso |
|---|---|
| `sql/INV_ROTACION.sql` | Detalle por artículo |
| `sql/INV_RESUMEN_LINEA.sql` | Resumen por línea |
| `sql/INV_FOTO.sql` | Foto del inventario por almacén con costo |
| `sql/INV_VERIFICAR.sql` | Chequeos de calidad de datos (correr a mano en SSMS) |
| `job/JOB_INVENTARIO_KD.cmd` | Paso CmdExec del job semanal |
| `job/EXPORTAR_CSV.ps1` | Ejecuta cada consulta en conexión de solo lectura y escribe el CSV; rechaza cualquier archivo .sql con sentencias de escritura |

## Salidas (`salidas\`)
- `INV_ROTACION_KD.csv` y `INV_RESUMEN_LINEA_KD.csv`: se sobreescriben cada semana (File ID estable en Drive)
- `historico\INV_FOTO_AAAAMMDD.csv`: un archivo por semana para el costeo a fecha

## Instalación
1. Abrir `sql/INV_VERIFICAR.sql` en SSMS y ejecutar (F5)
2. Crear job semanal (domingo en la noche) con un paso CmdExec:
   `cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"`
3. Opcional, recomendado: que el job corra con un usuario que solo tenga `db_datareader` en HD_A01

## Tablas de Profit consultadas
`art`, `st_almac`, `almacen`, `lin_art`, `sub_lin`, `cat_art`, `proceden`, `factura`, `reng_fac`, `dev_cli`, `reng_dvc`

# Resumen Ejecutivo de Inventario - Krash Depot

Informe semanal de inventario generado desde Profit Plus Administrativo 2K8 (SQL Server 2014, base HD_A01).

## Qué calcula
- Valor del inventario (Bs y $) por artículo, línea, categoría y procedencia
- Rotación, cobertura en días y venta diaria (ventana de 90 días, facturas menos devoluciones)
- Clasificación ABC por costo de venta
- Estado: ALTA / MEDIA / BAJA / SIN MOVIMIENTO / AGOTADO
- Foto semanal del inventario (`INV_SNAPSHOT_KD`) para costeo a fecha

## Estructura
| Archivo | Uso |
|---|---|
| `sql/INV_01_INSTALAR.sql` | Crea la base `KD_REPORTES`, tablas, procedimientos y vistas. Correr una vez. |
| `sql/INV_02_VERIFICAR.sql` | Ejecuta el informe y muestra chequeos de calidad de datos. |
| `job/JOB_INVENTARIO_KD.cmd` | Paso CmdExec del job semanal de SQL Agent. Exporta los CSV. |

## Instalación
1. Copiar la carpeta a `D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\`
2. Ejecutar `sql/INV_01_INSTALAR.sql` en SSMS
3. Ejecutar `sql/INV_02_VERIFICAR.sql` y revisar resultados
4. Crear job semanal (domingo en la noche) con paso CmdExec:
   `cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"`

## Salidas (se sobreescriben, sin borrar, para conservar el File ID en Drive)
- `INV_ROTACION_KD.csv` - detalle por artículo
- `INV_RESUMEN_LINEA_KD.csv` - resumen por línea

## Tablas de Profit usadas
`art`, `st_almac`, `lin_art`, `sub_lin`, `cat_art`, `proceden`, `factura`, `reng_fac`, `dev_cli`, `reng_dvc`

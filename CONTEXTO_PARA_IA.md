# Contexto del proyecto para otro asistente (Gemini u otro)

Pega este archivo completo al iniciar la conversación, junto con los archivos del proyecto. Es todo lo que el asistente necesita para entender qué está construido, cómo funciona y qué reglas no puede romper.

---

## Quién y para qué
- **Usuario:** Leonardo, de Krash Depot (House Depot PF, S.A.), una tienda de electrodomésticos y hogar en Punto Fijo, Venezuela, con las marcas Sankey y Krash. Escribe en español y trabaja casi siempre desde el teléfono por escritorio remoto (RDP).
- **Objetivo:** un **resumen ejecutivo de inventario y ventas** automático. Cubre el comportamiento del inventario, la rotación alta y baja, el costeo a una fecha y el desempeño de ventas y de vendedores. Llega por correo con un dashboard interactivo y un PDF.

## Reglas que NO se pueden romper
1. **SOLO CONSULTA sobre la base de datos.** Ningún script ni job puede crear, modificar ni borrar nada en SQL Server: solo SELECT. `EXPORTAR_CSV.ps1` abre la conexión con `ApplicationIntent=ReadOnly` y rechaza cualquier .sql que contenga insert, update, delete, truncate, drop, create, alter, merge, exec, execute, grant o into.
2. **Todo en dólares:**
   - Costo = `ult_cos_om`.
   - Venta = `reng_neto / tasa` (neto de descuento).
   - No se usa `cos_pro_om`: da valores negativos en esta base.
3. **Los archivos de salida se sobrescriben en el mismo lugar**, nunca se borran y se vuelven a crear. Así Google Drive conserva el File ID que usa Make.
4. **Archivos .ps1 en ASCII**, con los acentos como entidades HTML en el correo. **.cmd con CRLF.** Los .sql en UTF-8 con BOM.
5. En PowerShell **no se puede nombrar una función `H`**: choca con el alias `h` de Get-History. Ya pasó una vez y por eso la función se llama `HtmlTxt`. Tampoco se puede usar `$args` como variable propia.

## Infraestructura
| Pieza | Detalle |
|---|---|
| ERP | Profit Plus Administrativo 2K8 |
| Base de datos | SQL Server 2014, servidor `WIN-KRASHDEPOT`, base `HD_A01` |
| Carpeta del proyecto | `D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO` (sincronizada con Google Drive) |
| Drive: carpeta raíz | `1SvpPnSzQRFKjgEH6txiQ5ees3GrZIWdM` |
| Drive: sql / job / salidas / historico | `1zLsgrq763Pxhy-RRSwg90mAO8FdyP3eV` / `1cQjR2Cf9zuu4d_Hh7WcWMr2nA61yFOv3` / `1JB37k-P5Y-F77xg6PIsKDHzS7Rp3jDsq` / `1Zb_7tijnJlxQcKgbL71-CjhHbJ5DDmD9` |
| Job de SQL Agent | `INFORME_INVENTARIO_KD`, domingos 23:00, un paso CmdExec: `cmd /c "D:\RESPALDO_PROFIT\RESUMEN EJECUTIVO INVENTARIO\job\JOB_INVENTARIO_KD.cmd"` |
| Make (zona us2) | Escenario **6804251** "Resumen Ejecutivo Inventario - Krash Depot", diario a las 07:00. Conexión de Drive 9395563, conexión de Gmail 9333438. La copia está en `make/escenario_6804251_blueprint.json` |
| Correo | Se envía a leojose18@gmail.com solo si `INV_EMAIL_KD.html` cambió en las últimas 24 h. Adjunta el PDF, el dashboard HTML e `INV_RESUMEN_LINEA_KD.csv` |
| GitHub | `Leojose18/resumen-ejecutivo-inventario` |
| PDF | Se genera con Chrome o Edge en modo headless, que debe estar instalado en el servidor |

**Archivos de Drive que lee Make** (no cambiar sus ID):
- `INV_EMAIL_KD.html`: `1xIMVEGKNsXw4PO3jNH6xUxg5ZsC_kfep`
- `INV_RESUMEN_LINEA_KD.csv`: `11eYpO9fJVSoV0UCskjwwuI7GIsZ9VkTU`
- `INV_DASHBOARD_KD.html`: `15uXEuCHITQLJnV7vYOQ8fxpmqjXwNxXt`
- `INV_DASHBOARD_KD.pdf`: `1EpM2JktMAL9Aq82ULNjdcBFnibTg8-4B`

## Flujo
```
SQL Agent (domingo 23:00)
 └ JOB_INVENTARIO_KD.cmd
    1  INV_ROTACION.sql        → salidas\INV_ROTACION_KD.csv        (por artículo)
    2  INV_RESUMEN_LINEA.sql   → salidas\INV_RESUMEN_LINEA_KD.csv   (por línea)
    3  INV_VENTAS_DIARIAS.sql  → salidas\INV_VENTAS_DIARIAS_KD.csv  (día × línea, desde 1-ene de hace 2 años)
    3b INV_VENTAS_VENDEDOR.sql → salidas\INV_VENTAS_VENDEDOR_KD.csv (día × vendedor × artículo, desde 1-ene del año pasado; si falla, el job sigue)
    4  INV_FOTO.sql            → salidas\historico\INV_FOTO_AAAAMMDD.csv (foto semanal por almacén)
    5  GENERAR_EMAIL.ps1       → salidas\INV_EMAIL_KD.html
    6  GENERAR_DASHBOARD.ps1   → salidas\INV_DASHBOARD_KD.html + .pdf (plantilla job\DASHBOARD_TEMPLATE.html)
Drive sincroniza → Make (diario 07:00) → Gmail con 3 adjuntos
```
Los pasos 1 a 4 se ejecutan con `EXPORTAR_CSV.ps1 <archivo.sql> <salida.csv>`. Cada consulta devuelve una sola columna `fila` ya armada con separador `;` y encabezado en la primera fila. Así se evita que sqlcmd corte el texto a 256 caracteres.

## Tablas de Profit que se usan
- `art`: co_art, art_des, modelo, co_lin, co_subl, co_cat, procedenci, ult_cos_om, fec_ult_co, anulado, prec_om
- `st_almac`: stock por almacén
- `almacen`, `lin_art` (lin_des), `sub_lin` (subl_des), `cat_art` (cat_des = **marca**), `proceden` (des_proc)
- `factura`: fact_num, fec_emis, tasa, anulada, co_ven
- `reng_fac`: total_art, reng_neto, ult_cos_om
- `dev_cli` y `reng_dvc`: lo mismo para devoluciones
- `vendedor`: co_ven, ven_des

## Reglas de cálculo
- **Venta en $** = Σ `reng_neto / tasa` de facturas, menos la misma suma de devoluciones, sin anuladas.
- **Costo de venta en $** = Σ `total_art × reng_fac.ult_cos_om`, el costo guardado en el renglón al facturar.
- **Inventario en $** = stock (Σ st_almac) × `art.ult_cos_om`, el costo actual.
- **Margen** = (venta − costo) / venta.
- **Obsequios** = renglones con `reng_neto <= 0`. Su costo **no** entra en el costo de venta ni en el margen por artículo y por línea; se reportan aparte con las columnas `uds_obsequio_90d` y `costo_obsequio_usd_90d`. Sus unidades **sí** cuentan como salida para la rotación y la cobertura. En ventas diarias y por vendedor el costo sí incluye los obsequios.
- **Ventana de análisis:** 90 días.
- **Cobertura** = stock / (unidades 90 d / 90). **Rotación** = costo de venta 90 d / inventario.
- **Estado** (en este orden):
  1. AGOTADO: unidades > 0 y stock ≤ 0.
  2. NUEVO INGRESO: sin ventas y última compra hace 30 días o menos.
  3. SIN MOVIMIENTO: sin ventas.
  4. ALTA: cobertura de 30 días o menos.
  5. MEDIA: cobertura de 90 días o menos.
  6. BAJA: el resto.
- **Capital quieto** = valor en BAJA + SIN MOVIMIENTO.
- **ABC** por venta en $ acumulada: A hasta 80%, B hasta 95%, C el resto.
- **Vendedores:**
  - Vendedor = `co_ven` del documento. Marca = categoría del artículo.
  - **VENTAS MAYORES no compite en el ranking**: siempre sale con posición 0, pero su venta suma en el total del equipo. La lista está en `FIJOS` dentro de la plantilla.
  - **No se muestra detalle individual por vendedor**, solo información general del equipo, y **ningún vendedor se resalta** visualmente.

## Contenido del dashboard (`DASHBOARD_TEMPLATE.html`)
- Usa JavaScript puro, sin librerías. Las gráficas son SVG.
- Los datos se insertan en `<script id="kd-data" type="application/json">__KD_DATA__</script>`. Estructura:
  - `{corte, gen, lineas[], estados[], arts[[co,desc,lineaIdx,stock,valorInv,uds90,venta90,costo90,margenPct,cobertura,diasSinVenta,estadoIdx,abc,udsObsequio,costoObsequio]], dias[[fecha,lineaIdx,venta,costo,uds]], v0, vend[[co,nombre]], marcas[], vart[], vs[[diaOffset,venIdx,artIdx,lineaIdx,marcaIdx,uds,venta,costo]]}`
- **Controles:** filtro global por línea y botón "Descargar PDF" (`window.print`, con CSS de impresión A4).
- **Secciones:**
  1. Seis indicadores clave.
  2. "Qué atender", la lectura automática.
  3. Ventas por período (Semana, Mes o Año) contra el año anterior.
  4. Temporada.
  5. Inventario por estado de rotación.
  6. Desempeño por línea.
  7. **Desempeño de vendedores:**
     - Período elegible: Semana, Mes, 90 días o Año.
     - Ranking con posición y cambio de puesto.
     - Histórico de 12 meses con la venta y el puesto de cada mes.
     - Mezcla por línea o marca de los últimos 12 meses.
     - Bloque "Equipo de ventas · últimos 12 meses".
  8. **Artículos a revisar**, con 7 listas: agotados, sobrestock, mayor rotación, sin movimiento, margen negativo, nuevo ingreso y obsequios.
- **Marca de Krash Depot:** rojo #ED0023, azul #086788, celeste #06AED5, amarillo #F9B32F, crema #FFF1D0, fuente Poppins.

## Cómo probar un cambio
1. Editar los archivos en la carpeta de D: o en Drive. Si se edita en Drive, se reemplaza el archivo completo en `sql` o `job`.
2. En SSMS: clic derecho sobre el job → Iniciar trabajo en el paso…
3. Revisar en Drive que `salidas\INV_DASHBOARD_KD.pdf` tenga hora nueva.
4. Ejecutar el escenario 6804251 en Make ("Run once") para recibir el correo.
5. Para diagnosticar datos, usar las consultas de `sql/INV_VERIFICAR.sql` en SSMS.

## Historial de decisiones importantes
- La primera versión creaba tablas y procedimientos en una base KD_REPORTES. **Se descartó** por la regla de solo consulta.
- Se cambió `cos_pro_om` por `ult_cos_om` porque el primero daba inventario negativo.
- Se agregó el estado NUEVO INGRESO porque las compras recientes salían como SIN MOVIMIENTO.
- Se exporta con PowerShell en lugar de sqlcmd porque sqlcmd cortaba las columnas a 256 caracteres.
- El dueño del job se cambió por un error 15404, cuando el dueño era una cuenta local.
- Los obsequios se separaron del margen: de 470 renglones bajo costo en 90 días, 207 eran a $0. El costo del renglón coincidía con el de la ficha en 395 de ellos, así que el costo no era el problema.

## Pendientes o ideas no implementadas
- Si el HTML del dashboard crece demasiado (5 MB o más), agrupar las ventas antiguas por mes en lugar de por día.
- Opcional: excluir los obsequios también del margen por período y por vendedor.

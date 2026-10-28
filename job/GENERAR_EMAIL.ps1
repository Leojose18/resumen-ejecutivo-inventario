# ==================================================================
#  GENERAR_EMAIL.ps1  -  NO toca la base de datos
#  Lee los CSV que acaba de generar el job y arma el correo HTML del
#  resumen ejecutivo en salidas\INV_EMAIL_KD.html (se sobreescribe en el
#  mismo archivo para que Google Drive conserve el File ID que usa Make).
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File GENERAR_EMAIL.ps1 "<carpeta base>"
#  Archivo en ASCII a proposito: los acentos van como entidades HTML.
# ==================================================================
param([Parameter(Mandatory=$true)][string]$Base)
$ErrorActionPreference = 'Stop'

$inv = [Globalization.CultureInfo]::InvariantCulture
$sal = Join-Path $Base 'salidas'
$dashboard = 'https://claude.ai/artifact/Lc2AmYWubfHFsGDEJTUky6'

# ---------- utilidades ----------
function N($s) {
    if ($s -eq $null) { return $null }
    $t = ([string]$s).Trim()
    if ($t -eq '') { return $null }
    $v = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, $inv, [ref]$v)) { return $v }
    return $null
}
function Z($s) { $v = N $s; if ($v -eq $null) { return 0.0 } else { return $v } }
function H($s) { return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function USD($v) { if ($v -eq $null) { return '&mdash;' } return '$' + ([double]$v).ToString('N0', $inv) }
function USDC($v) {
    if ($v -eq $null) { return '&mdash;' }
    $a = [math]::Abs([double]$v)
    if ($a -ge 1000000) { return '$' + ([double]$v / 1000000).ToString('N2', $inv) + 'M' }
    if ($a -ge 10000)   { return '$' + ([double]$v / 1000).ToString('N1', $inv) + 'K' }
    return USD $v
}
function PCT($v) { if ($v -eq $null) { return '&mdash;' } return ([double]$v * 100).ToString('N1', $inv) + '%' }
function P100($v) { if ($v -eq $null) { return '&mdash;' } return ([double]$v).ToString('N1', $inv) + '%' }
function INT($v) { if ($v -eq $null) { return '&mdash;' } return ([double]$v).ToString('N0', $inv) }
function SUMF($rows, [string]$field) {
    $t = 0.0
    foreach ($r in $rows) { $t += (Z $r.$field) }
    return $t
}
function VAR($actual, $anterior) {
    # variacion con color: verde si sube, rojo si baja
    if ($anterior -eq $null) { return '<span style="color:#9ca3af">&mdash;</span>' }
    if ([double]$anterior -eq 0) { return '<span style="color:#6b7280">sin base</span>' }
    $p = ([double]$actual - [double]$anterior) / [math]::Abs([double]$anterior)
    $col = '#15803d'; $sig = '+'
    if ($p -lt 0) { $col = '#b42318'; $sig = '' }
    return '<span style="color:' + $col + ';font-weight:600">' + $sig + ($p * 100).ToString('N1', $inv) + '%</span>'
}
$MESES = @('ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic')
function FECHA([datetime]$d) { return $d.Day.ToString() + ' ' + $MESES[$d.Month - 1] + ' ' + $d.Year }

# ---------- datos ----------
$arts   = @(Import-Csv (Join-Path $sal 'INV_ROTACION_KD.csv') -Delimiter ';' -Encoding UTF8)
$lineas = @(Import-Csv (Join-Path $sal 'INV_RESUMEN_LINEA_KD.csv') -Delimiter ';' -Encoding UTF8)
if ($arts.Count -eq 0) { throw 'INV_ROTACION_KD.csv viene vacio.' }

$corte = [datetime]::ParseExact(([string]$arts[0].fecha_corte).Substring(0, 10), 'yyyy-MM-dd', $inv)

$conStock = @($arts | Where-Object { (Z $_.stock) -gt 0 })
$valor  = SUMF $conStock 'valor_inv_usd'
$venta  = SUMF $arts 'venta_usd_90d'
$costo  = SUMF $arts 'costo_venta_usd_90d'
$margen = $null; if ($venta -gt 0) { $margen = ($venta - $costo) / $venta }
$diasInv = $null; if ($costo -gt 0) { $diasInv = $valor / ($costo / 90) }

$baja    = @($arts | Where-Object { $_.estado -eq 'BAJA' })
$sinMov  = @($arts | Where-Object { $_.estado -eq 'SIN MOVIMIENTO' })
$nuevo   = @($arts | Where-Object { $_.estado -eq 'NUEVO INGRESO' })
$agot    = @($arts | Where-Object { $_.estado -eq 'AGOTADO' })
$vBaja   = SUMF $baja 'valor_inv_usd'
$vSinMov = SUMF $sinMov 'valor_inv_usd'
$vNuevo  = SUMF $nuevo 'valor_inv_usd'
$quieto  = $vBaja + $vSinMov
$quietoPct = $null; if ($valor -gt 0) { $quietoPct = $quieto / $valor }
$negativos = @($arts | Where-Object { (Z $_.venta_usd_90d) -gt 0 -and (N $_.margen_pct) -ne $null -and (Z $_.margen_pct) -lt 0 })

$topAgot  = @($agot | Sort-Object { Z $_.venta_usd_90d } -Descending | Select-Object -First 8)
$topSobre = @($baja | Sort-Object { Z $_.valor_inv_usd } -Descending | Select-Object -First 8)
$topRot   = @($arts | Where-Object { (Z $_.venta_usd_90d) -gt 0 } | Sort-Object { Z $_.venta_usd_90d } -Descending | Select-Object -First 8)
$topLin   = @($lineas | Sort-Object { Z $_.valor_inv_usd } -Descending | Select-Object -First 10)

# ---------- ventas por periodo (si existe el archivo diario) ----------
$periodosHtml = ''
$fileDia = Join-Path $sal 'INV_VENTAS_DIARIAS_KD.csv'
if (Test-Path $fileDia) {
    $dias = @{}
    foreach ($r in (Import-Csv $fileDia -Delimiter ';' -Encoding UTF8)) {
        $k = ([string]$r.fecha).Substring(0, 10)
        if (-not $dias.ContainsKey($k)) { $dias[$k] = @(0.0, 0.0) }
        $dias[$k][0] += (Z $r.venta_usd)
        $dias[$k][1] += (Z $r.costo_usd)
    }
    function RANGO([datetime]$desde, [datetime]$hasta) {
        $v = 0.0; $c = 0.0
        $d = $desde.Date
        while ($d -le $hasta.Date) {
            $k = $d.ToString('yyyy-MM-dd')
            if ($dias.ContainsKey($k)) { $v += $dias[$k][0]; $c += $dias[$k][1] }
            $d = $d.AddDays(1)
        }
        return @($v, $c)
    }
    function FILA([string]$nombre, $act, $ant, $antLY) {
        $m = '&mdash;'; if ($act[0] -gt 0) { $m = PCT (($act[0] - $act[1]) / $act[0]) }
        return '<tr><td style="padding:8px 10px;border-bottom:1px solid #e5e7eb">' + $nombre + '</td>' +
               '<td style="padding:8px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + (USD $act[0]) + '</td>' +
               '<td style="padding:8px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + $m + '</td>' +
               '<td style="padding:8px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + (VAR $act[0] $ant[0]) + '</td>' +
               '<td style="padding:8px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + (VAR $act[0] $antLY[0]) + '</td></tr>'
    }
    $h = $corte.Date
    # semana: ultimos 7 dias; comparada con los 7 anteriores y con la misma semana del ano pasado (364 dias, mismo dia de la semana)
    $sem    = RANGO $h.AddDays(-6) $h
    $semAnt = RANGO $h.AddDays(-13) $h.AddDays(-7)
    $semLY  = RANGO $h.AddDays(-370) $h.AddDays(-364)
    # mes en curso a la fecha
    $ini    = New-Object DateTime $h.Year, $h.Month, 1
    $mes    = RANGO $ini $h
    $iniAnt = $ini.AddMonths(-1)
    $finAnt = $iniAnt.AddDays([math]::Min($h.Day, [DateTime]::DaysInMonth($iniAnt.Year, $iniAnt.Month)) - 1)
    $mesAnt = RANGO $iniAnt $finAnt
    $iniLY  = $ini.AddYears(-1)
    $mesLY  = RANGO $iniLY $iniLY.AddDays([math]::Min($h.Day, [DateTime]::DaysInMonth($iniLY.Year, $iniLY.Month)) - 1)
    # ano a la fecha
    $ytd    = RANGO (New-Object DateTime $h.Year, 1, 1) $h
    $ytdLY  = RANGO (New-Object DateTime ($h.Year - 1), 1, 1) $h.AddYears(-1)
    $ytdAnt = @($null, $null)
    $filas = (FILA ('&Uacute;ltimos 7 d&iacute;as') $sem $semAnt $semLY) +
             (FILA ('Mes en curso (1&ndash;' + $h.Day + ' ' + $MESES[$h.Month - 1] + ')') $mes $mesAnt $mesLY) +
             (FILA ('A&ntilde;o ' + $h.Year + ' a la fecha') $ytd $ytdAnt $ytdLY)

    # ultimos 12 meses cerrados + mes en curso
    $filasMes = ''
    for ($i = 12; $i -ge 0; $i--) {
        $m0 = $ini.AddMonths(-$i)
        $m1 = $m0.AddMonths(1).AddDays(-1); if ($m1 -gt $h) { $m1 = $h }
        $a  = RANGO $m0 $m1
        $ly = RANGO $m0.AddYears(-1) $m1.AddYears(-1)
        $mm = '&mdash;'; if ($a[0] -gt 0) { $mm = PCT (($a[0] - $a[1]) / $a[0]) }
        $etq = $MESES[$m0.Month - 1] + ' ' + $m0.Year; if ($i -eq 0) { $etq = $etq + ' (en curso)' }
        $filasMes += '<tr><td style="padding:6px 10px;border-bottom:1px solid #e5e7eb">' + $etq + '</td>' +
                     '<td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + (USD $a[0]) + '</td>' +
                     '<td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + $mm + '</td>' +
                     '<td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;text-align:right">' + (VAR $a[0] $ly[0]) + '</td></tr>'
    }
    $th = 'padding:8px 10px;border-bottom:2px solid #d1d5db;color:#6b7280;font-weight:600;font-size:12px'
    $periodosHtml = '<h2 style="font-size:17px;margin:28px 0 8px">Ventas por per&iacute;odo</h2>' +
        '<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px">' +
        '<tr><th align="left" style="' + $th + '">Per&iacute;odo</th><th align="right" style="' + $th + '">Venta neta</th><th align="right" style="' + $th + '">Margen</th><th align="right" style="' + $th + '">vs per&iacute;odo anterior</th><th align="right" style="' + $th + '">vs a&ntilde;o anterior</th></tr>' +
        $filas + '</table>' +
        '<h2 style="font-size:17px;margin:28px 0 8px">&Uacute;ltimos 12 meses</h2>' +
        '<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px">' +
        '<tr><th align="left" style="' + $th + '">Mes</th><th align="right" style="' + $th + '">Venta neta</th><th align="right" style="' + $th + '">Margen</th><th align="right" style="' + $th + '">vs mismo mes a&ntilde;o anterior</th></tr>' +
        $filasMes + '</table>'
}

# ---------- armado del HTML ----------
$td  = 'padding:7px 10px;border-bottom:1px solid #e5e7eb'
$tdr = $td + ';text-align:right;white-space:nowrap'
$th  = 'padding:8px 10px;border-bottom:2px solid #d1d5db;color:#6b7280;font-weight:600;font-size:12px'

function KPI([string]$label, [string]$valor, [string]$nota, [string]$color) {
    return '<td width="33%" valign="top" style="padding:6px"><div style="border:1px solid #e5e7eb;border-radius:8px;padding:12px 14px;background:#ffffff">' +
           '<div style="font-size:12px;color:#6b7280">' + $label + '</div>' +
           '<div style="font-family:Georgia,serif;font-size:24px;line-height:1.2;margin-top:4px;color:' + $color + '">' + $valor + '</div>' +
           '<div style="font-size:11px;color:#6b7280;margin-top:4px">' + $nota + '</div></div></td>'
}

$filasAgot = ''
foreach ($r in $topAgot) { $filasAgot += '<tr><td style="' + $td + '">' + (H $r.descripcion) + '<div style="color:#9ca3af;font-size:11px">' + (H $r.co_art) + ' &middot; ' + (H $r.linea) + '</div></td><td style="' + $tdr + '">' + (USD (Z $r.venta_usd_90d)) + '</td><td style="' + $tdr + '">' + (INT (Z $r.uds_vendidas_90d)) + '</td></tr>' }
$filasSobre = ''
foreach ($r in $topSobre) { $filasSobre += '<tr><td style="' + $td + '">' + (H $r.descripcion) + '<div style="color:#9ca3af;font-size:11px">' + (H $r.co_art) + ' &middot; ' + (H $r.linea) + '</div></td><td style="' + $tdr + '">' + (INT (Z $r.stock)) + '</td><td style="' + $tdr + '">' + (INT (N $r.cobertura_dias)) + ' d&iacute;as</td><td style="' + $tdr + '">' + (USD (Z $r.valor_inv_usd)) + '</td></tr>' }
$filasRot = ''
foreach ($r in $topRot) { $filasRot += '<tr><td style="' + $td + '">' + (H $r.descripcion) + '<div style="color:#9ca3af;font-size:11px">' + (H $r.co_art) + ' &middot; ' + (H $r.linea) + '</div></td><td style="' + $tdr + '">' + (USD (Z $r.venta_usd_90d)) + '</td><td style="' + $tdr + '">' + (P100 (N $r.margen_pct)) + '</td><td style="' + $tdr + '">' + (INT (N $r.cobertura_dias)) + ' d&iacute;as</td></tr>' }
$filasLin = ''
foreach ($r in $topLin) { $filasLin += '<tr><td style="' + $td + '">' + (H $r.linea) + '</td><td style="' + $tdr + '">' + (USD (Z $r.valor_inv_usd)) + '</td><td style="' + $tdr + '">' + (USD (Z $r.venta_usd_90d)) + '</td><td style="' + $tdr + '">' + (P100 (N $r.margen_pct)) + '</td><td style="' + $tdr + '">' + (USD (Z $r.valor_sin_mov_usd)) + '</td><td style="' + $tdr + '">' + (INT (Z $r.agotados)) + '</td></tr>' }

$alertas = ''
if ($topAgot.Count -gt 0) {
    $alertas += '<li style="margin-bottom:8px"><b style="color:#b42318">Reponer:</b> ' + (H $topAgot[0].descripcion) + ' vendi&oacute; ' + (USD (Z $topAgot[0].venta_usd_90d)) + ' en 90 d&iacute;as y hoy no tiene stock.</li>'
}
if ($topSobre.Count -gt 0) {
    $alertas += '<li style="margin-bottom:8px"><b style="color:#b45309">Sobrestock:</b> ' + (H $topSobre[0].descripcion) + ' tiene ' + (INT (Z $topSobre[0].stock)) + ' unidades y ' + (INT (N $topSobre[0].cobertura_dias)) + ' d&iacute;as de cobertura (' + (USD (Z $topSobre[0].valor_inv_usd)) + ').</li>'
}
$alertas += '<li style="margin-bottom:8px"><b style="color:#b45309">Capital inmovilizado:</b> ' + (USD $vSinMov) + ' en ' + (INT $sinMov.Count) + ' art&iacute;culos sin ventas en 90 d&iacute;as.</li>'
if ($negativos.Count -gt 0) {
    $alertas += '<li style="margin-bottom:8px"><b style="color:#b42318">Margen negativo:</b> ' + (INT $negativos.Count) + ' art&iacute;culos se vendieron por debajo del &uacute;ltimo costo. Revisar costos en Profit.</li>'
}
if ($vNuevo -gt 0) {
    $alertas += '<li style="margin-bottom:8px"><b>Nuevo ingreso:</b> ' + (USD $vNuevo) + ' comprados en los &uacute;ltimos 30 d&iacute;as a&uacute;n sin ventas.</li>'
}

$html = '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>' +
'<body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#1f2328">' +
'<table width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6"><tr><td align="center" style="padding:20px 10px">' +
'<table width="680" cellpadding="0" cellspacing="0" style="max-width:680px;width:100%;background:#ffffff;border-radius:10px;border:1px solid #e5e7eb">' +
'<tr><td style="padding:22px 24px 6px">' +
'<div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#6b7280">Krash Depot &middot; Informe semanal &middot; Corte ' + (FECHA $corte) + '</div>' +
'<h1 style="font-family:Georgia,serif;font-weight:400;font-size:26px;margin:6px 0 8px">Resumen ejecutivo de inventario</h1>' +
'<p style="margin:0;font-size:14px;line-height:1.55;color:#4b5563">El <b style="color:#1f2328">' + (PCT $quietoPct) + '</b> del inventario (' + (USDC $quieto) + ') est&aacute; en baja rotaci&oacute;n o sin movimiento, y <b style="color:#1f2328">' + (INT $agot.Count) + '</b> art&iacute;culos que se venden est&aacute;n agotados. Todo en d&oacute;lares a &uacute;ltimo costo.</p>' +
'</td></tr>' +
'<tr><td style="padding:10px 18px 0"><table width="100%" cellpadding="0" cellspacing="0"><tr>' +
(KPI 'Valor del inventario' (USDC $valor) ((INT $conStock.Count) + ' art&iacute;culos con stock') '#1f2328') +
(KPI 'Venta neta 90 d&iacute;as' (USDC $venta) 'Facturas menos devoluciones' '#1f2328') +
(KPI 'Margen bruto 90 d&iacute;as' (PCT $margen) ('Costo de venta ' + (USDC $costo)) '#1f2328') +
'</tr><tr>' +
(KPI 'D&iacute;as de inventario' ((INT $diasInv) + ' d&iacute;as') 'Inventario &divide; costo diario' '#1f2328') +
(KPI 'Capital quieto' (USDC $quieto) ((PCT $quietoPct) + ' del inventario') '#b45309') +
(KPI 'Agotados con venta' (INT $agot.Count) 'Vendieron y hoy tienen stock cero' '#b42318') +
'</tr></table></td></tr>' +
'<tr><td style="padding:8px 24px 24px">' +
'<h2 style="font-size:17px;margin:20px 0 8px">Qu&eacute; atender esta semana</h2><ul style="margin:0;padding-left:18px;font-size:14px;line-height:1.5">' + $alertas + '</ul>' +
$periodosHtml +
'<h2 style="font-size:17px;margin:28px 0 8px">Agotados que m&aacute;s venden</h2>' +
'<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px"><tr><th align="left" style="' + $th + '">Art&iacute;culo</th><th align="right" style="' + $th + '">Venta 90 d</th><th align="right" style="' + $th + '">Uds.</th></tr>' + $filasAgot + '</table>' +
'<h2 style="font-size:17px;margin:28px 0 8px">Mayor capital en baja rotaci&oacute;n</h2>' +
'<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px"><tr><th align="left" style="' + $th + '">Art&iacute;culo</th><th align="right" style="' + $th + '">Stock</th><th align="right" style="' + $th + '">Cobertura</th><th align="right" style="' + $th + '">Inventario</th></tr>' + $filasSobre + '</table>' +
'<h2 style="font-size:17px;margin:28px 0 8px">Mayor rotaci&oacute;n</h2>' +
'<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px"><tr><th align="left" style="' + $th + '">Art&iacute;culo</th><th align="right" style="' + $th + '">Venta 90 d</th><th align="right" style="' + $th + '">Margen</th><th align="right" style="' + $th + '">Cobertura</th></tr>' + $filasRot + '</table>' +
'<h2 style="font-size:17px;margin:28px 0 8px">Por l&iacute;nea</h2>' +
'<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px"><tr><th align="left" style="' + $th + '">L&iacute;nea</th><th align="right" style="' + $th + '">Inventario</th><th align="right" style="' + $th + '">Venta 90 d</th><th align="right" style="' + $th + '">Margen</th><th align="right" style="' + $th + '">Sin mov.</th><th align="right" style="' + $th + '">Agot.</th></tr>' + $filasLin + '</table>' +
'<p style="margin:26px 0 0;text-align:center"><a href="' + $dashboard + '" style="display:inline-block;background:#1f2328;color:#ffffff;text-decoration:none;padding:11px 20px;border-radius:8px;font-size:14px">Abrir el dashboard completo</a></p>' +
'<p style="margin:18px 0 0;font-size:11px;color:#9ca3af;line-height:1.5">Generado autom&aacute;ticamente por el job INFORME_INVENTARIO_KD (solo lectura sobre Profit Plus, base HD_A01). Inventario a &uacute;ltimo costo en $ (ult_cos_om); ventas = renglones de factura &divide; tasa, menos devoluciones.</p>' +
'</td></tr></table></td></tr></table></body></html>'

# Sobreescribe el mismo archivo (no lo borra) -> Drive conserva el File ID
$out = Join-Path $sal 'INV_EMAIL_KD.html'
[IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Output ($out + ': correo generado')

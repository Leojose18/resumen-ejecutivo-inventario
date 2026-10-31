# ==================================================================
#  GENERAR_DASHBOARD.ps1  -  NO toca la base de datos
#  Lee los CSV del job y genera:
#    salidas\INV_DASHBOARD_KD.html  informe interactivo con graficas
#    salidas\INV_DASHBOARD_KD.pdf   el mismo informe en PDF (Chrome o Edge
#                                   en modo invisible)
#  Ambos se sobreescriben en el mismo archivo para que Google Drive
#  conserve el File ID que usa Make para adjuntarlos al correo.
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File GENERAR_DASHBOARD.ps1 "<carpeta base>"
#  Archivo en ASCII a proposito.
# ==================================================================
param([Parameter(Mandatory=$true)][string]$Base)
$ErrorActionPreference = 'Stop'

$inv  = [Globalization.CultureInfo]::InvariantCulture
$sal  = Join-Path $Base 'salidas'
$tpl  = Join-Path $Base 'job\DASHBOARD_TEMPLATE.html'
$html = Join-Path $sal 'INV_DASHBOARD_KD.html'
$pdf  = Join-Path $sal 'INV_DASHBOARD_KD.pdf'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------- utilidades ----------
function NUM($s) {
    # numero JSON o null
    if ($s -eq $null) { return 'null' }
    $t = ([string]$s).Trim()
    if ($t -eq '') { return 'null' }
    $v = 0.0
    if (-not [double]::TryParse($t, [Globalization.NumberStyles]::Float, $inv, [ref]$v)) { return 'null' }
    return ([math]::Round($v, 2)).ToString('0.##', $inv)
}
function JS($s) {
    # cadena JSON segura para ir dentro de <script>
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in ([string]$s).ToCharArray()) {
        $c = [int]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($c -lt 32 -or $ch -eq '<' -or $ch -eq '>' -or $ch -eq '&' -or $c -eq 0x2028 -or $c -eq 0x2029) {
            [void]$sb.Append('\u' + $c.ToString('x4'))
        }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# ---------- datos ----------
$arts = @(Import-Csv (Join-Path $sal 'INV_ROTACION_KD.csv') -Delimiter ';' -Encoding UTF8)
if ($arts.Count -eq 0) { throw 'INV_ROTACION_KD.csv viene vacio.' }
$diasCsv = Join-Path $sal 'INV_VENTAS_DIARIAS_KD.csv'
$dias = @()
if (Test-Path $diasCsv) { $dias = @(Import-Csv $diasCsv -Delimiter ';' -Encoding UTF8) }

$corte = ([string]$arts[0].fecha_corte).Substring(0, 10)
$estados = @('ALTA', 'MEDIA', 'BAJA', 'SIN MOVIMIENTO', 'NUEVO INGRESO', 'AGOTADO')
$estIdx = @{}; for ($i = 0; $i -lt $estados.Count; $i++) { $estIdx[$estados[$i]] = $i }

$lineas = New-Object System.Collections.ArrayList
$linIdx = @{}
function LIDX($nombre) {
    $n = ([string]$nombre).Trim(); if ($n -eq '') { $n = 'SIN LINEA' }
    if (-not $linIdx.ContainsKey($n)) { $linIdx[$n] = $lineas.Count; [void]$lineas.Add($n) }
    return $linIdx[$n]
}

$sbA = New-Object System.Text.StringBuilder
$first = $true
foreach ($a in $arts) {
    $e = ([string]$a.estado).Trim()
    $ei = 1; if ($estIdx.ContainsKey($e)) { $ei = $estIdx[$e] }
    if (-not $first) { [void]$sbA.Append(',') }; $first = $false
    [void]$sbA.Append('[').Append((JS $a.co_art)).Append(',').Append((JS $a.descripcion)).Append(',').Append((LIDX $a.linea)).Append(',')
    [void]$sbA.Append((NUM $a.stock)).Append(',').Append((NUM $a.valor_inv_usd)).Append(',').Append((NUM $a.uds_vendidas_90d)).Append(',')
    [void]$sbA.Append((NUM $a.venta_usd_90d)).Append(',').Append((NUM $a.costo_venta_usd_90d)).Append(',').Append((NUM $a.margen_pct)).Append(',')
    [void]$sbA.Append((NUM $a.cobertura_dias)).Append(',').Append((NUM $a.dias_sin_venta)).Append(',').Append($ei).Append(',').Append((JS $a.clase_abc)).Append(']')
}

$sbD = New-Object System.Text.StringBuilder
$first = $true
foreach ($d in $dias) {
    $f = ([string]$d.fecha).Trim(); if ($f.Length -lt 10) { continue }
    if (-not $first) { [void]$sbD.Append(',') }; $first = $false
    [void]$sbD.Append('[').Append((JS $f.Substring(0, 10))).Append(',').Append((LIDX $d.linea)).Append(',')
    [void]$sbD.Append((NUM $d.venta_usd)).Append(',').Append((NUM $d.costo_usd)).Append(',').Append((NUM $d.uds)).Append(']')
}

$sbL = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $lineas.Count; $i++) { if ($i -gt 0) { [void]$sbL.Append(',') }; [void]$sbL.Append((JS $lineas[$i])) }
$sbE = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $estados.Count; $i++) { if ($i -gt 0) { [void]$sbE.Append(',') }; [void]$sbE.Append((JS $estados[$i])) }

$gen = (Get-Date).ToString('dd/MM/yyyy HH:mm', $inv)
$json = '{"corte":' + (JS $corte) + ',"gen":' + (JS $gen) + ',"lineas":[' + $sbL.ToString() + '],"estados":[' + $sbE.ToString() +
        '],"arts":[' + $sbA.ToString() + '],"dias":[' + $sbD.ToString() + ']}'

# ---------- HTML ----------
$plantilla = [IO.File]::ReadAllText($tpl, $utf8)
if ($plantilla.IndexOf('__KD_DATA__') -lt 0) { throw 'La plantilla no tiene el marcador __KD_DATA__.' }
$salida = $plantilla.Replace('__KD_DATA__', $json)
[IO.File]::WriteAllText($html, $salida, $utf8)
Write-Output ('HTML generado: ' + $html + ' (' + $arts.Count + ' articulos, ' + $dias.Count + ' filas diarias)')

# ---------- PDF con Chrome o Edge invisible ----------
$candidatos = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
)
$nav = $null
foreach ($c in $candidatos) { if ($c -and (Test-Path $c)) { $nav = $c; break } }
if (-not $nav) { throw 'No se encontro Chrome ni Edge para generar el PDF. El HTML si se genero.' }

# Carpeta temporal FUERA de la carpeta sincronizada con Drive
$tmp = Join-Path $env:TEMP 'kd_dashboard'
$perfil = Join-Path $tmp 'perfil'
New-Item -ItemType Directory -Force -Path $perfil | Out-Null
$tmpPdf = Join-Path $tmp 'INV_DASHBOARD_KD.pdf'
if (Test-Path $tmpPdf) { Remove-Item $tmpPdf -Force }

$uri = ([Uri]$html).AbsoluteUri
$argList = @(
    '--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    ('--user-data-dir="' + $perfil + '"'), '--run-all-compositor-stages-before-draw', '--virtual-time-budget=15000',
    '--window-size=1240,1754', '--no-pdf-header-footer', '--print-to-pdf-no-header',
    ('--print-to-pdf="' + $tmpPdf + '"'), ('"' + $uri + '"')
)
$p = Start-Process -FilePath $nav -ArgumentList $argList -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch {} ; throw 'El navegador tardo mas de 3 minutos generando el PDF.' }

$espera = 0
while (-not (Test-Path $tmpPdf) -and $espera -lt 30) { Start-Sleep -Seconds 1; $espera++ }
if (-not (Test-Path $tmpPdf)) { throw ('El navegador no genero el PDF (' + $nav + ').') }
Start-Sleep -Seconds 1
$bytes = [IO.File]::ReadAllBytes($tmpPdf)
if ($bytes.Length -lt 1000) { throw 'El PDF generado esta vacio.' }
# Se sobreescribe el mismo archivo (mismo File ID en Drive)
[IO.File]::WriteAllBytes($pdf, $bytes)
Write-Output ('PDF generado: ' + $pdf + ' (' + [math]::Round($bytes.Length / 1024) + ' KB) con ' + $nav)
exit 0

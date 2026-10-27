# ==================================================================
#  EXPORTAR_CSV.ps1  -  SOLO CONSULTA
#  Ejecuta un archivo .sql (solo SELECT) sobre HD_A01 y escribe el
#  resultado en un CSV. La conexion se abre con ApplicationIntent=ReadOnly.
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File EXPORTAR_CSV.ps1 <archivo.sql> <salida.csv>
# ==================================================================
param([Parameter(Mandatory=$true)][string]$SqlFile,
      [Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference = 'Stop'

$query = [IO.File]::ReadAllText($SqlFile)
# Seguridad: rechazar cualquier sentencia de escritura (sin contar comentarios)
$sinComentarios = [regex]::Replace($query, '(?s)/\*.*?\*/|--[^\r\n]*', '')
if ($sinComentarios -match '(?i)\b(insert|update|delete|truncate|drop|create|alter|merge|exec|execute|grant|into)\b') {
    throw "El archivo $SqlFile contiene una sentencia que no es de solo lectura. Abortado."
}

$cs = 'Server=WIN-KRASHDEPOT;Database=HD_A01;Integrated Security=SSPI;ApplicationIntent=ReadOnly;Application Name=INFORME_INVENTARIO_KD'
$cn = New-Object System.Data.SqlClient.SqlConnection $cs
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = $query
    $cmd.CommandTimeout = 900
    $rd = $cmd.ExecuteReader()
    $lineas = New-Object System.Collections.Generic.List[string]
    while ($rd.Read()) { $lineas.Add([string]$rd.GetValue(0)) }
    $rd.Close()
} finally { $cn.Close() }

# Sobreescribe en el mismo archivo (no lo borra) -> Drive conserva el File ID
$dir = Split-Path $OutFile -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[IO.File]::WriteAllLines($OutFile, $lineas, (New-Object System.Text.UTF8Encoding $true))
Write-Output ("{0}: {1} filas" -f $OutFile, ($lineas.Count - 1))

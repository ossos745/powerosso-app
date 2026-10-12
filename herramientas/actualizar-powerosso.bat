<# :
@echo off
rem Powerosso: sube todas las planillas de la carpeta Alumnos a la app y guarda un respaldo.
rem Doble clic para ejecutar. Las lineas de abajo son PowerShell (viene incluido en Windows).
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0'))"
echo.
pause
exit /b
#>
$ErrorActionPreference = 'Stop'
# ---- configuracion ----
$Carpeta = 'C:\Users\benja\OneDrive\Desktop\Alumnos'
$Url     = '__URL__'
$Key     = '__KEY__'
$Token   = '__TOKEN__'
$App     = '__APP__'
# -----------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Headers = @{ apikey = $Key; Authorization = "Bearer $Key" }
function Llamar($fn, $body) {
  $json  = $body | ConvertTo-Json -Compress -Depth 6
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$Url/rest/v1/rpc/$fn" -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $bytes
}
Write-Host ''
Write-Host '  TEAM POWEROSSO - actualizar planillas' -ForegroundColor Yellow
Write-Host "  Carpeta: $Carpeta"
Write-Host ''
if (-not (Test-Path -LiteralPath $Carpeta)) { Write-Host '  No encuentro la carpeta. Revisa la ruta en este archivo (linea $Carpeta).' -ForegroundColor Red; return }
$archivos = Get-ChildItem -LiteralPath $Carpeta -File | Where-Object { $_.Extension -match '^\.xls[xm]$' -and $_.Name -notlike '~$*' }
if (-not $archivos) { Write-Host '  No hay planillas .xlsx en la carpeta.'; return }
$ok = 0
foreach ($f in $archivos) {
  try {
    $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')   # funciona aunque el Excel este abierto
    try { $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $bytes = $ms.ToArray() } finally { $fs.Close() }
    $r = Llamar 'pw_upload' @{ p_token = $Token; p_name = $f.Name; p_mtime = $f.LastWriteTimeUtc.ToString('o'); p_b64 = [Convert]::ToBase64String($bytes) }
    $res = $r.Content | ConvertFrom-Json
    $extra = ''; if ($res.new) { $extra = '  (alumno nuevo: ponle nombre en la app)' }
    Write-Host ('  OK     ' + $f.Name + '  ->  ' + $res.athlete + $extra) -ForegroundColor Green
    $ok++
  } catch {
    Write-Host ('  ERROR  ' + $f.Name + ': ' + $_.Exception.Message) -ForegroundColor Red
  }
}
Write-Host ''
Write-Host "  $ok de $($archivos.Count) planillas actualizadas."
try {
  $dir = Join-Path $Carpeta 'Respaldos Powerosso'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $r = Llamar 'pw_export' @{ p_token = $Token }
  $ruta = Join-Path $dir ('powerosso-respaldo-' + (Get-Date -Format 'yyyy-MM-dd') + '.json')
  [IO.File]::WriteAllBytes($ruta, $r.RawContentStream.ToArray())
  Write-Host "  Respaldo guardado en: $ruta"
} catch {
  Write-Host ('  No se pudo guardar el respaldo: ' + $_.Exception.Message) -ForegroundColor Red
}
Write-Host ''
Write-Host "  App: $App"

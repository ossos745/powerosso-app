<# :
@echo off
rem Powerosso: anota los PR en los Excel, sube las planillas de la carpeta Alumnos a la app y guarda un respaldo.
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
# ---- PR: anota el 1RM estimado en la columna "SERIES X REPES REALIZADAS" de la fila del ejercicio ----
function Norm($t) { if ($null -eq $t) { return '' } return (([string]$t).ToUpper().Replace([string][char]0xD7, 'X') -replace '[\s\.]', '') }
$prs = @()
try {
  $d = (Llamar 'pw_load' @{ p_token = $Token }).Content | ConvertFrom-Json
  foreach ($lp in $d.logs.PSObject.Properties) {
    $L = $lp.Value; if (-not $L.sets) { continue }
    foreach ($ep in $L.sets.PSObject.Properties) { foreach ($st in @($ep.Value)) {
      if ($st -and $st.pr -and $st.pr.file -and $st.pr.sheet -and $st.pr.row) { $prs += $st.pr } } }
  }
} catch { Write-Host ('  No se pudieron leer los PR de la app: ' + $_.Exception.Message) -ForegroundColor Red }
if ($prs.Count) {
  Write-Host "  PR logrados en la app: $($prs.Count). Anotando el 1RM en los Excel..."
  $xlNuevo = $null
  $prs = @($prs | Sort-Object { [double]$_.t })   # si un dia se repitio, el ultimo PR queda escrito
  foreach ($grupo in ($prs | Group-Object { $_.file })) {
    $f = $archivos | Where-Object { $_.Name -eq $grupo.Name } | Select-Object -First 1
    if (-not $f) { Write-Host ('  PR: no encuentro ' + $grupo.Name + ' en la carpeta') -ForegroundColor Red; continue }
    $wb = $null; $propio = $false; $cambios = 0
    try {
      # si el Excel ya esta abierto, se usa ese mismo; si no, se abre en segundo plano
      try { $xl = [Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application'); foreach ($w in $xl.Workbooks) { if ($w.Name -eq $f.Name) { $wb = $w } } } catch {}
      if (-not $wb) {
        if (-not $xlNuevo) { $xlNuevo = New-Object -ComObject Excel.Application; $xlNuevo.Visible = $false; $xlNuevo.DisplayAlerts = $false }
        $wb = $xlNuevo.Workbooks.Open($f.FullName); $propio = $true
      }
      foreach ($p in $grupo.Group) {
        $ws = $wb.Worksheets.Item([string]$p.sheet); $fila = [int]$p.row
        $u = $ws.UsedRange; $c1 = $u.Column; $c2 = [Math]::Max($u.Column + $u.Columns.Count - 1, $c1 + 1); $col = 0
        # busca la cabecera hacia arriba desde la fila del ejercicio (la de su tabla del dia)
        for ($r = $fila; $r -ge [Math]::Max(1, $fila - 120) -and -not $col; $r--) {
          $vals = $ws.Range($ws.Cells.Item($r, $c1), $ws.Cells.Item($r, $c2)).Value2
          for ($c = 1; $c -le ($c2 - $c1 + 1); $c++) { if ((Norm $vals[1, $c]) -match '^SERIESXREP(E|ETICIONE)?SREALIZADAS$') { $col = $c1 + $c - 1; break } }
        }
        if (-not $col) { Write-Host ('  PR: no encuentro la columna "Series x repes realizadas" en ' + $f.Name + ' / ' + $p.sheet + ' (fila ' + $fila + ')') -ForegroundColor Red; continue }
        $celda = $ws.Cells.Item($fila, $col); $v = [double]$p.rm1
        if ($celda.Value2 -ne $v) { $celda.Value2 = $v; $cambios++ }
        Write-Host ('  PR     ' + $f.Name + ' / ' + $p.sheet + ' fila ' + $fila + ': ' + $p.ex + ' ' + $p.kg + ' x ' + $p.reps + '  ->  1RM ' + $v) -ForegroundColor Cyan
      }
      if ($cambios) { $wb.Save() }
    } catch {
      Write-Host ('  PR: no se pudo escribir en ' + $f.Name + ': ' + $_.Exception.Message + '  (si esta abierto en otro programa, cierralo y vuelve a correr)') -ForegroundColor Red
    } finally { if ($propio -and $wb) { $wb.Close($false) } }
  }
  if ($xlNuevo) { $xlNuevo.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xlNuevo) }
  Write-Host ''
}
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

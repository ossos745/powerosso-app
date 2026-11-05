<# :
@echo off
rem Powerosso: anota los PR y los pesos bajados por EVA en los Excel, sube las planillas de la carpeta Alumnos a la app y guarda un respaldo.
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
# ---- Excel: anota los PR (1RM en "SERIES X REPES REALIZADAS") y los pesos bajados por EVA (columna "PESO(kg)") ----
# Lo ya anotado queda en "Respaldos Powerosso\anotado-en-excel.txt" y no se vuelve a escribir (ni se abre el Excel si no hay nada nuevo).
function Norm($t) { if ($null -eq $t) { return '' } return (([string]$t).ToUpper().Replace([string][char]0xD7, 'X') -replace '[\s\.]', '') }
$RegDir  = Join-Path $Carpeta 'Respaldos Powerosso'
$RegFile = Join-Path $RegDir 'anotado-en-excel.txt'
$hecho = @{}
if (Test-Path -LiteralPath $RegFile) { foreach ($ln in (Get-Content -LiteralPath $RegFile -Encoding UTF8)) { if ($ln) { $hecho[$ln] = $true } } }
$items = @()
try {
  $d = (Llamar 'pw_load' @{ p_token = $Token }).Content | ConvertFrom-Json
  foreach ($lp in $d.logs.PSObject.Properties) {
    $L = $lp.Value
    if ($L.sets) { foreach ($ep in $L.sets.PSObject.Properties) { foreach ($st in @($ep.Value)) {
      $p = $null; if ($st) { $p = $st.pr }
      if ($p -and $p.file -and $p.sheet -and $p.row) {
        $items += [pscustomobject]@{ tipo = 'pr'; file = [string]$p.file; sheet = [string]$p.sheet; row = [int]$p.row; ex = [string]$p.ex; t = [double]$p.t; valor = [double]$p.rm1; kg = $p.kg; reps = $p.reps; from = $null; eva = $null }
      } } } }
    if ($L.adj) { foreach ($ap in $L.adj.PSObject.Properties) {
      $a = $ap.Value
      if ($a -and $a.kg -and $a.file -and $a.sheet -and $a.row) {
        $items += [pscustomobject]@{ tipo = 'eva'; file = [string]$a.file; sheet = [string]$a.sheet; row = [int]$a.row; ex = [string]$a.ex; t = [double]$a.t; valor = [double]$a.kg; kg = $a.kg; reps = $null; from = $a.from; eva = $a.eva }
      } } }
  }
} catch { Write-Host ('  No se pudieron leer los PR y ajustes EVA de la app: ' + $_.Exception.Message) -ForegroundColor Red }
$yaAnotados = @($items | Where-Object { $hecho.ContainsKey($_.tipo + '|' + $_.file + '|' + $_.sheet + '|' + $_.t) }).Count
$items = @($items | Where-Object { -not $hecho.ContainsKey($_.tipo + '|' + $_.file + '|' + $_.sheet + '|' + $_.t) } | Sort-Object { $_.t })
if ($yaAnotados) { Write-Host "  PR y ajustes EVA ya anotados antes: $yaAnotados (no se vuelven a escribir)." }
if ($items.Count) {
  Write-Host "  Por anotar en los Excel: $($items.Count) (PR y pesos bajados por EVA)..."
  New-Item -ItemType Directory -Force -Path $RegDir | Out-Null
  $xlNuevo = $null
  foreach ($grupo in ($items | Group-Object { $_.file })) {
    $f = $archivos | Where-Object { $_.Name -eq $grupo.Name } | Select-Object -First 1
    if (-not $f) { Write-Host ('  No encuentro ' + $grupo.Name + ' en la carpeta') -ForegroundColor Red; continue }
    $wb = $null; $propio = $false; $cambios = 0; $nuevos = @()
    try {
      # si el Excel ya esta abierto, se usa ese mismo; si no, se abre en segundo plano
      try { $xl = [Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application'); foreach ($w in $xl.Workbooks) { if ($w.Name -eq $f.Name) { $wb = $w } } } catch {}
      if (-not $wb) {
        if (-not $xlNuevo) { $xlNuevo = New-Object -ComObject Excel.Application; $xlNuevo.Visible = $false; $xlNuevo.DisplayAlerts = $false }
        $wb = $xlNuevo.Workbooks.Open($f.FullName); $propio = $true
      }
      foreach ($p in $grupo.Group) {
        $clave = $p.tipo + '|' + $p.file + '|' + $p.sheet + '|' + $p.t
        if ($p.tipo -eq 'pr') { $patron = '^SERIESXREP(E|ETICIONE)?SREALIZADAS$'; $nomCol = 'Series x repes realizadas' } else { $patron = '^PESO(\(KG\))?$'; $nomCol = 'Peso (kg)' }
        $ws = $wb.Worksheets.Item([string]$p.sheet); $fila = [int]$p.row
        $u = $ws.UsedRange; $c1 = $u.Column; $c2 = [Math]::Max($u.Column + $u.Columns.Count - 1, $c1 + 1); $col = 0; $colEj = 0
        # busca la cabecera hacia arriba desde la fila del ejercicio (la de su tabla del dia)
        for ($r = $fila; $r -ge [Math]::Max(1, $fila - 120) -and -not $col; $r--) {
          $vals = $ws.Range($ws.Cells.Item($r, $c1), $ws.Cells.Item($r, $c2)).Value2
          for ($c = 1; $c -le ($c2 - $c1 + 1); $c++) { if ((Norm $vals[1, $c]) -match $patron) { $col = $c1 + $c - 1 } }
          if ($col) { for ($c = 1; $c -le ($c2 - $c1 + 1); $c++) { if ((Norm $vals[1, $c]) -eq 'EJERCICIO') { $colEj = $c1 + $c - 1; break } } }
        }
        if (-not $col) { Write-Host ('  No encuentro la columna "' + $nomCol + '" en ' + $f.Name + ' / ' + $p.sheet + ' (fila ' + $fila + ')') -ForegroundColor Red; continue }
        # si la planilla cambio y el ejercicio ya no esta en esa fila, se busca la fila mas cercana con el mismo nombre
        if ($colEj -and $p.ex -and ((Norm $ws.Cells.Item($fila, $colEj).Value2) -ne (Norm $p.ex))) {
          $otra = 0
          for ($k = 1; $k -le 80 -and -not $otra; $k++) { foreach ($r in @(($fila + $k), ($fila - $k))) { if (-not $otra -and $r -ge 1 -and (Norm $ws.Cells.Item($r, $colEj).Value2) -eq (Norm $p.ex)) { $otra = $r } } }
          if (-not $otra) { Write-Host ('  No encuentro "' + $p.ex + '" cerca de la fila ' + $fila + ' en ' + $f.Name + ' / ' + $p.sheet + '. No se anoto.') -ForegroundColor Red; continue }
          $fila = $otra
        }
        $celda = $ws.Cells.Item($fila, $col); $v = [double]$p.valor
        if ($celda.Value2 -ne $v) { $celda.Value2 = $v; $cambios++ }
        if ($p.tipo -eq 'pr') {
          Write-Host ('  PR     ' + $f.Name + ' / ' + $p.sheet + ' fila ' + $fila + ': ' + $p.ex + ' ' + $p.kg + ' x ' + $p.reps + '  ->  1RM ' + $v) -ForegroundColor Cyan
        } else {
          $fecha = ''; try { $fecha = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$p.t).LocalDateTime.ToString('dd-MM-yyyy') } catch {}
          try { $celda.ClearComments() | Out-Null; [void]$celda.AddComment('EVA ' + $p.eva + ' (' + $fecha + '): bajado de ' + $p.from + ' a ' + $v + ' kg') } catch {}
          $dep = 0; try { $dep = $celda.Dependents.Count } catch {}
          Write-Host ('  EVA    ' + $f.Name + ' / ' + $p.sheet + ' fila ' + $fila + ': ' + $p.ex + '  ' + $p.from + ' kg  ->  ' + $v + ' kg (EVA ' + $p.eva + ')') -ForegroundColor Cyan
          if ($dep) { Write-Host ('         ojo: ' + $dep + ' celda(s) de la planilla usan este peso en una formula y tambien cambian') -ForegroundColor Yellow }
        }
        $nuevos += $clave
      }
      if ($cambios) { $wb.Save() }
      if ($nuevos.Count) { Add-Content -LiteralPath $RegFile -Value $nuevos -Encoding UTF8 }
    } catch {
      Write-Host ('  No se pudo escribir en ' + $f.Name + ': ' + $_.Exception.Message + '  (si esta abierto en otro programa, cierralo y vuelve a correr)') -ForegroundColor Red
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

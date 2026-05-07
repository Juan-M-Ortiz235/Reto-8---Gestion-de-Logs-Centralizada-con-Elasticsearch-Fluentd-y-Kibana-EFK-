# destroy.ps1
# Elimina el cluster DOKS y limpia los recursos huérfanos (LoadBalancers, Volumes)
# etiquetados con el tag del proyecto. Requiere doctl autenticado.
#
# Uso:
#   PS> .\scripts\destroy.ps1
#   PS> powershell -ExecutionPolicy Bypass -File .\scripts\destroy.ps1

$ErrorActionPreference = "Stop"

$ClusterName = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "efk-cluster" }
$Tag         = if ($env:TAG)          { $env:TAG }          else { "reto-efk" }

$Confirm = Read-Host "Vas a destruir el cluster '$ClusterName' y los recursos con tag '$Tag'. Escribe 'si' para continuar"
if ($Confirm -ne "si") {
  Write-Host "Abortado."
  exit 1
}

# 1. Eliminar Load Balancers asociados
Write-Host ""
Write-Host "=== Buscando Load Balancers con tag '$Tag' ===" -ForegroundColor Cyan
$LbLines = doctl compute load-balancer list --format ID,Tag --no-header
$LbIds = @()
foreach ($line in $LbLines) {
  $cols = ($line -split '\s+', 2)
  if ($cols.Count -ge 2 -and $cols[1] -match $Tag) {
    $LbIds += $cols[0]
  }
}
if ($LbIds.Count -gt 0) {
  Write-Host "Eliminando LBs: $($LbIds -join ', ')"
  foreach ($id in $LbIds) {
    doctl compute load-balancer delete $id --force
  }
} else {
  Write-Host "No hay LBs con ese tag."
}

# 2. Eliminar Volúmenes huérfanos
Write-Host ""
Write-Host "=== Buscando Volúmenes con tag '$Tag' ===" -ForegroundColor Cyan
$VolLines = doctl compute volume list --format ID,Tags --no-header
$VolIds = @()
foreach ($line in $VolLines) {
  $cols = ($line -split '\s+', 2)
  if ($cols.Count -ge 2 -and $cols[1] -match $Tag) {
    $VolIds += $cols[0]
  }
}
if ($VolIds.Count -gt 0) {
  Write-Host "Eliminando Volúmenes: $($VolIds -join ', ')"
  foreach ($id in $VolIds) {
    doctl compute volume delete $id --force
  }
} else {
  Write-Host "No hay volúmenes con ese tag."
}

# 3. Eliminar el cluster
Write-Host ""
Write-Host "=== Eliminando cluster $ClusterName ===" -ForegroundColor Cyan
doctl kubernetes cluster delete $ClusterName --force --dangerous

Write-Host ""
Write-Host "=== Limpieza completada ===" -ForegroundColor Green
Write-Host "Verifica en https://cloud.digitalocean.com/ que no quede nada activo."

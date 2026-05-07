# provision-cluster.ps1
# Crea el cluster DOKS para el Reto 8 (EFK) desde PowerShell en Windows.
# Requiere: doctl autenticado (`doctl auth init`).
#
# Uso:
#   PS> .\scripts\provision-cluster.ps1
#   o con variables:
#   PS> $env:CLUSTER_NAME="otro-nombre"; .\scripts\provision-cluster.ps1

# Si la política de ejecución te bloquea, puedes correrlo así sin cambiarla globalmente:
#   PS> powershell -ExecutionPolicy Bypass -File .\scripts\provision-cluster.ps1

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------
# Variables ajustables (puedes sobrescribirlas con $env:NOMBRE antes de ejecutar)
# ------------------------------------------------------------------
$ClusterName  = if ($env:CLUSTER_NAME)   { $env:CLUSTER_NAME }   else { "efk-cluster" }
$Region       = if ($env:REGION)         { $env:REGION }         else { "nyc3" }
$K8sVersion   = if ($env:K8S_VERSION)    { $env:K8S_VERSION }    else { "" }
$NodeSize     = if ($env:NODE_SIZE)      { $env:NODE_SIZE }      else { "s-2vcpu-4gb" }
$NodeCount    = if ($env:NODE_COUNT)     { $env:NODE_COUNT }     else { "2" }
$Tag          = if ($env:TAG)            { $env:TAG }            else { "reto-efk" }
$NodePoolName = if ($env:NODE_POOL_NAME) { $env:NODE_POOL_NAME } else { "default-pool" }

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
foreach ($cmd in @("doctl","kubectl")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: '$cmd' no está instalado o no está en el PATH."
    exit 1
  }
}

try {
  doctl account get | Out-Null
} catch {
  Write-Error "ERROR: doctl no está autenticado. Ejecuta primero 'doctl auth init'."
  exit 1
}

# Si no se fijó la versión de K8s, tomamos la última disponible que ofrece DO.
if ([string]::IsNullOrWhiteSpace($K8sVersion)) {
  $versionsJson = doctl kubernetes options versions -o json | ConvertFrom-Json
  $K8sVersion = $versionsJson[0].slug
  Write-Host "K8S_VERSION no fijada. Usando la última disponible: $K8sVersion"
}

# ------------------------------------------------------------------
# Crear el cluster
# ------------------------------------------------------------------
Write-Host ""
Write-Host "=== Creando cluster $ClusterName en $Region ($K8sVersion) ===" -ForegroundColor Cyan
Write-Host "    Node pool: $NodePoolName | size=$NodeSize | count=$NodeCount"
Write-Host ""

$nodePoolSpec = "name=$NodePoolName;size=$NodeSize;count=$NodeCount;tag=$Tag"

doctl kubernetes cluster create $ClusterName `
  --region $Region `
  --version $K8sVersion `
  --node-pool $nodePoolSpec `
  --tag $Tag `
  --wait

Write-Host ""
Write-Host "=== Cluster creado. Verificando kubectl ===" -ForegroundColor Cyan
kubectl config current-context
kubectl get nodes -o wide

# ------------------------------------------------------------------
# Crear namespaces base
# ------------------------------------------------------------------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ScriptDir
$NsManifest = Join-Path $RepoRoot "k8s\00-namespaces.yaml"

Write-Host ""
Write-Host "=== Aplicando namespaces (logging, apps) ===" -ForegroundColor Cyan
kubectl apply -f $NsManifest
kubectl get ns | Select-String -Pattern "logging|apps"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Cluster '$ClusterName' listo. Pasos siguientes:" -ForegroundColor Green
Write-Host "  1. Verifica los nodos: kubectl get nodes"
Write-Host "  2. Avanza a Fase 3: despliegue de Elasticsearch"
Write-Host "     kubectl apply -f k8s\01-elasticsearch.yaml"
Write-Host "================================================================" -ForegroundColor Green

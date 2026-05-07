#!/usr/bin/env bash
# provision-cluster.sh
# Crea el cluster DOKS para el Reto 8 (EFK).
# Requiere: doctl autenticado (`doctl auth init`).

set -euo pipefail

# ------------------------------------------------------------------
# Variables ajustables
# ------------------------------------------------------------------
CLUSTER_NAME="${CLUSTER_NAME:-efk-cluster}"
REGION="${REGION:-nyc3}"
K8S_VERSION="${K8S_VERSION:-}"            # vacío = ultima estable que ofrezca DO
NODE_SIZE="${NODE_SIZE:-s-2vcpu-4gb}"
NODE_COUNT="${NODE_COUNT:-2}"
TAG="${TAG:-reto-efk}"
NODE_POOL_NAME="${NODE_POOL_NAME:-default-pool}"

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
command -v doctl   >/dev/null || { echo "ERROR: doctl no está instalado. Corre scripts/install-tools.sh"; exit 1; }
command -v kubectl >/dev/null || { echo "ERROR: kubectl no está instalado."; exit 1; }
doctl account get >/dev/null || { echo "ERROR: doctl no autenticado. Corre 'doctl auth init'."; exit 1; }

# Si no se fijó K8S_VERSION, tomamos la última estable que DO ofrece.
if [[ -z "${K8S_VERSION}" ]]; then
  K8S_VERSION="$(doctl kubernetes options versions -o json | python3 -c "import json,sys; v=json.load(sys.stdin); print(v[0]['slug'])")"
  echo "K8S_VERSION no fijada. Usando la última disponible: ${K8S_VERSION}"
fi

# ------------------------------------------------------------------
# Crear el cluster
# ------------------------------------------------------------------
echo "=== Creando cluster ${CLUSTER_NAME} en ${REGION} (${K8S_VERSION}) ==="
echo "    Node pool: ${NODE_POOL_NAME} | size=${NODE_SIZE} | count=${NODE_COUNT}"
echo

doctl kubernetes cluster create "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --version "${K8S_VERSION}" \
  --node-pool "name=${NODE_POOL_NAME};size=${NODE_SIZE};count=${NODE_COUNT};tag=${TAG}" \
  --tag "${TAG}" \
  --wait

echo
echo "=== Cluster creado. Verificando kubectl ==="
kubectl config current-context
kubectl get nodes -o wide

# ------------------------------------------------------------------
# Crear namespaces base
# ------------------------------------------------------------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo
echo "=== Aplicando namespaces (logging, apps) ==="
kubectl apply -f "${SCRIPT_DIR}/../k8s/00-namespaces.yaml"
kubectl get ns | grep -E 'logging|apps'

cat <<EOF

================================================================
Cluster '${CLUSTER_NAME}' listo. Pasos siguientes:
  1. Verifica los nodos: kubectl get nodes
  2. Avanza a Fase 3: despliegue de Elasticsearch
     kubectl apply -f k8s/01-elasticsearch.yaml
================================================================
EOF

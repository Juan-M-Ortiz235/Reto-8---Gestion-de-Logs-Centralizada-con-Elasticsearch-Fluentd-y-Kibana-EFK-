#!/usr/bin/env bash
# destroy.sh
# Elimina el cluster DOKS y limpia los recursos huérfanos (LoadBalancers, Volumes)
# etiquetados con el tag del proyecto. Requiere doctl autenticado.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-efk-cluster}"
TAG="${TAG:-reto-efk}"

read -r -p "Vas a destruir el cluster '${CLUSTER_NAME}' y los recursos con tag '${TAG}'. ¿Estás seguro? (escribe 'si' para continuar): " CONFIRM
if [[ "${CONFIRM}" != "si" ]]; then
  echo "Abortado."
  exit 1
fi

# 1. Eliminar Load Balancers asociados (Kibana usa uno).
echo "=== Buscando Load Balancers con tag '${TAG}' ==="
LB_IDS="$(doctl compute load-balancer list --format ID,Tag --no-header | awk -v t="${TAG}" '$2 ~ t {print $1}')"
if [[ -n "${LB_IDS}" ]]; then
  echo "Eliminando LBs: ${LB_IDS}"
  for id in ${LB_IDS}; do
    doctl compute load-balancer delete "${id}" --force
  done
else
  echo "No hay LBs con ese tag."
fi

# 2. Eliminar Volúmenes (Block Storage) huérfanos
echo "=== Buscando Volúmenes con tag '${TAG}' ==="
VOL_IDS="$(doctl compute volume list --format ID,Tags --no-header | awk -v t="${TAG}" '$2 ~ t {print $1}')"
if [[ -n "${VOL_IDS}" ]]; then
  echo "Eliminando Volúmenes: ${VOL_IDS}"
  for id in ${VOL_IDS}; do
    doctl compute volume delete "${id}" --force
  done
else
  echo "No hay volúmenes con ese tag."
fi

# 3. Eliminar el cluster (también borra los nodos y los volúmenes "managed" por DOKS)
echo "=== Eliminando cluster ${CLUSTER_NAME} ==="
doctl kubernetes cluster delete "${CLUSTER_NAME}" --force --dangerous

echo
echo "=== Limpieza completada ==="
echo "Verifica en https://cloud.digitalocean.com/ que no quede nada activo."

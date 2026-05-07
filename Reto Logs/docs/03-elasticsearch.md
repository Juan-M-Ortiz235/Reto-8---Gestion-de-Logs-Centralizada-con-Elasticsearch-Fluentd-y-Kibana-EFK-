# Fase 3 — Despliegue de Elasticsearch

## 3.1 Objetivo

Desplegar un nodo de Elasticsearch 8.13.4 en el cluster DOKS, con almacenamiento persistente en DigitalOcean Block Storage, accesible internamente vía DNS de Kubernetes para que Kibana y Fluentd se conecten.

## 3.2 Componentes del manifiesto

El archivo `k8s/01-elasticsearch.yaml` contiene 4 recursos:

| Recurso                            | Tipo         | Función                                                                 |
|------------------------------------|--------------|-------------------------------------------------------------------------|
| `elasticsearch-config`             | ConfigMap    | Archivo `elasticsearch.yml` con la configuración del nodo.              |
| `elasticsearch-headless`           | Service (None) | Service "headless" requerido por StatefulSet para identidad DNS estable. |
| `elasticsearch`                    | Service ClusterIP | Endpoint estable para clientes (Kibana, Fluentd) en el puerto 9200. |
| `elasticsearch`                    | StatefulSet  | Pod de Elasticsearch + PVC de 10 Gi en `do-block-storage`.              |

## 3.3 Decisiones de diseño explicadas

### `discovery.type: single-node`
Hace que el nodo se auto-elija como master sin esperar a otros nodos. Imprescindible para clusters de 1 réplica. En un cluster real esto se reemplaza por `cluster.initial_master_nodes` con la lista de los primeros masters.

### Seguridad X-Pack deshabilitada
ES 8.x activa autenticación + TLS por defecto. Para una demo educativa esto introduce mucha complejidad (certificados, secrets, contraseñas) que distrae del objetivo del reto. Por eso ponemos:
```yaml
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```
> En producción esto NUNCA debe hacerse. Nivel "Intermedio" o "Avanzado" del reto incluiría reactivarlo.

### Init container con `sysctl -w vm.max_map_count=262144`
Elasticsearch usa mmap intensivamente y requiere ese valor. Los nodos de DOKS suelen venir con un valor menor. El init corre con `privileged: true` solo durante un instante para tunear el kernel del nodo donde se programa el pod, y se sale.

### Recursos solicitados (`requests`/`limits`)
- **CPU**: 500m a 1500m. ES no es muy intensivo en CPU para volúmenes de logs pequeños como los de la demo.
- **Memoria**: 1.5 Gi a 2.5 Gi. La JVM se configura con heap de 1 GB (`-Xms1g -Xmx1g`); el resto es para el filesystem cache de Lucene.

### `do-block-storage`
Es la `StorageClass` por defecto en DOKS. El `volumeClaimTemplate` del StatefulSet pide 10 Gi y DigitalOcean provisiona automáticamente un Block Storage Volume y lo monta en el pod.

### Probes
- **Readiness**: consulta `GET /_cluster/health?local=true`. Hasta que ES no responde 200, el Service no enruta tráfico al pod.
- **Liveness**: simple TCP en el 9200. Si el proceso se cuelga, K8s lo reinicia.

## 3.4 Aplicar el manifiesto

```powershell
cd "C:\Users\david\Documents\Reto Logs"
kubectl apply -f .\k8s\01-elasticsearch.yaml
```

Salida esperada:
```
configmap/elasticsearch-config created
service/elasticsearch-headless created
service/elasticsearch created
statefulset.apps/elasticsearch created
```

## 3.5 Verificar el despliegue

### Estado del pod
```powershell
kubectl get pods -n logging -w
```
Espera a ver:
```
NAME              READY   STATUS    RESTARTS   AGE
elasticsearch-0   1/1     Running   0          90s
```

> El primer arranque tarda **1-2 minutos** porque DigitalOcean tiene que provisionar el volumen de 10 Gi y la imagen de Elasticsearch (~700 MB) tiene que descargarse. Cancela el `-w` con `Ctrl+C` cuando esté `Running`.

Si se queda en `Pending` mucho tiempo:
```powershell
kubectl describe pod elasticsearch-0 -n logging
```
Revisa la sección `Events`. Causas típicas:
- PVC no se puede provisionar → revisa el storageClass.
- Recursos insuficientes en el cluster → reduce los `requests` o agrega más nodos.

### Logs del contenedor
```powershell
kubectl logs -n logging elasticsearch-0 -f
```
Busca la línea final:
```
"started",
"...","cluster.name":"efk-cluster",...
```

### PVC creado
```powershell
kubectl get pvc -n logging
```
```
NAME                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS       AGE
data-elasticsearch-0   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   10Gi       RWO            do-block-storage   2m
```

En el panel de DigitalOcean → **Volumes**, verás también el volumen de 10 Gi montado.

### Probar el API de Elasticsearch
Como el Service es ClusterIP (interno), usa `port-forward` desde tu máquina local:
```powershell
kubectl port-forward -n logging svc/elasticsearch 9200:9200
```
En otra ventana de PowerShell:
```powershell
curl http://localhost:9200
```
Deberías ver el JSON con la versión:
```json
{
  "name" : "elasticsearch-0",
  "cluster_name" : "efk-cluster",
  "version" : { "number" : "8.13.4", ... },
  "tagline" : "You Know, for Search"
}
```

Y el estado del cluster:
```powershell
curl http://localhost:9200/_cluster/health
```
Status debe ser `green` (single-node, no hay réplicas pendientes).

Cierra el port-forward con `Ctrl+C` cuando termines.

## 3.6 Troubleshooting común

| Síntoma                                          | Causa probable                          | Solución                                                                 |
|--------------------------------------------------|-----------------------------------------|--------------------------------------------------------------------------|
| Pod en `Pending` con "no nodes available"        | Recursos del nodo insuficientes         | Reducir `requests` (ej. `memory: 1Gi`) o escalar el node pool.           |
| Pod en `CrashLoopBackOff` con "max virtual memory" | Init `sysctl` no se aplicó              | Confirmar `securityContext.privileged: true` en el init container.       |
| `Readiness probe failed`                         | Cluster aún arrancando (90s normales)   | Esperar. Si pasa de 5 min, ver `kubectl logs`.                            |
| PVC en `Pending`                                 | StorageClass mal nombrada               | `kubectl get sc` debe mostrar `do-block-storage` (default).               |

## 3.7 Capturas para el informe

1. `kubectl get all -n logging` mostrando el StatefulSet, Service y Pod.
2. `kubectl get pvc -n logging` mostrando el PVC `Bound`.
3. Vista del Volume en el panel de DigitalOcean.
4. Salida del `curl http://localhost:9200/_cluster/health` con `status: green`.

## 3.8 Entregables de esta fase

- `k8s/01-elasticsearch.yaml` aplicado y `elasticsearch-0` en estado `Running`.
- PVC de 10 Gi `Bound` en DO Block Storage.
- API de ES respondiendo en `http://elasticsearch.logging.svc.cluster.local:9200` (interno) y vía port-forward en `localhost:9200`.

---

**Siguiente fase:** Fase 4 — Despliegue de Kibana.

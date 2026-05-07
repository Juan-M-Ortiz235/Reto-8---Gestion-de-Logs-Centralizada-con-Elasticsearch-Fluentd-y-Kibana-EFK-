# Fase 5 — Despliegue de Fluentd como DaemonSet

## 5.1 Objetivo

Desplegar Fluentd como un DaemonSet en el cluster. Su tarea: leer todos los logs de contenedores en cada nodo, enriquecerlos con metadata de Kubernetes y enviarlos a Elasticsearch.

En esta fase la configuración es **básica** (todos los logs van a un único índice `logs-k8s-*`). En la **Fase 7** refinaremos con parsers específicos para Nginx (regex) y para la app JSON.

## 5.2 Por qué un DaemonSet

Un DaemonSet garantiza que se cree **un pod en cada nodo** del cluster. Esto es fundamental porque los logs de los contenedores en Kubernetes se almacenan a nivel de **nodo** (no del cluster) en `/var/log/containers/*.log`. Cada Fluentd lee solo los logs del nodo donde corre.

Si tu cluster tiene 2 nodos → 2 pods de Fluentd. Si escalas a 5 → 5 pods. Sin que tengas que tocar nada.

## 5.3 Componentes del manifiesto

Esta fase usa 3 archivos:

| Archivo                                   | Recursos creados                                            |
|-------------------------------------------|-------------------------------------------------------------|
| `k8s/03-fluentd-rbac.yaml`                | ServiceAccount + ClusterRole + ClusterRoleBinding           |
| `k8s/04-fluentd-configmap.yaml`           | ConfigMap con `fluent.conf` (config principal)             |
| `k8s/05-fluentd-daemonset.yaml`           | DaemonSet                                                   |

## 5.4 Decisiones de diseño explicadas

### RBAC (acceso a metadata de K8s)
El plugin `kubernetes_metadata_filter` necesita listar pods y namespaces para enriquecer los logs con `kubernetes.pod_name`, `kubernetes.namespace_name`, `kubernetes.labels.*`, etc. Por eso definimos un `ClusterRole` con verbos `get/list/watch` sobre `pods` y `namespaces`.

### Imagen `fluent/fluentd-kubernetes-daemonset:v1.16-debian-elasticsearch8-1`
La imagen oficial mantenida por la comunidad de Fluentd que ya viene con:
- Plugin `out_elasticsearch` configurado para ES 8.x
- Plugin `kubernetes_metadata_filter`
- Parser `cri` (formato containerd) — DOKS usa containerd como runtime, no Docker
- Variables de entorno estándar como `FLUENT_ELASTICSEARCH_HOST`

### Source `tail` con parser `cri` anidado
DOKS usa **containerd** como runtime, que escribe los logs en formato CRI:
```
2024-05-01T12:00:00.000000000Z stdout F {"level":"info","msg":"hello"}
```
El parser `cri` divide eso en tres partes: timestamp, stream (stdout/stderr) y el contenido. Y aplicamos un segundo parser `json` para intentar parsear el contenido si es JSON.

### Filter `kubernetes_metadata`
Lee la metadata del pod desde el API de K8s y la agrega al evento. Después del filtro, cada log tiene campos como:
```json
{
  "kubernetes": {
    "pod_name": "nginx-demo-xxxx",
    "namespace_name": "apps",
    "container_name": "nginx",
    "labels": { "app": "nginx-demo" },
    "host": "default-pool-xxxxx"
  }
}
```

### Match con prefix `logs-k8s`
Por ahora todos los logs van al índice `logs-k8s-YYYY.MM.DD`. La rotación diaria la hace Fluentd con `logstash_format true` + `logstash_dateformat %Y.%m.%d`. En Fase 7 separaremos por fuente.

### Buffer en archivo
Si Elasticsearch se cae temporalmente, Fluentd guarda los eventos en disco (`/var/log/fluentd-buffers/`) hasta que ES vuelve. Evita pérdida de logs.

### Tolerations
Permiten que Fluentd corra en nodos con taints (control-plane). En DOKS el control plane es gestionado y no es schedulable, pero esto se vuelve útil si en algún momento agregas nodos especiales con taints.

## 5.5 Aplicar el manifiesto

> **Aplica los 3 archivos en orden**: RBAC primero (porque el DaemonSet usa el ServiceAccount), luego ConfigMap, luego DaemonSet.

```powershell
cd "C:\Users\david\Documents\Reto Logs"
kubectl apply -f .\k8s\03-fluentd-rbac.yaml
kubectl apply -f .\k8s\04-fluentd-configmap.yaml
kubectl apply -f .\k8s\05-fluentd-daemonset.yaml
```

Salida esperada:
```
serviceaccount/fluentd created
clusterrole.rbac.authorization.k8s.io/fluentd created
clusterrolebinding.rbac.authorization.k8s.io/fluentd created
configmap/fluentd-config created
daemonset.apps/fluentd created
```

> Atajo: si quieres aplicar todo el directorio de una vez:
> ```powershell
> kubectl apply -f .\k8s\
> ```
> Eso aplica los manifiestos en orden alfabético, que coincide con el orden numerado de los archivos.

## 5.6 Verificar el despliegue

### Pods del DaemonSet
```powershell
kubectl get pods -n logging -l app=fluentd
```

Debe mostrar **1 pod por nodo** (en nuestro cluster de 2 nodos = 2 pods):
```
NAME            READY   STATUS    RESTARTS   AGE
fluentd-abc12   1/1     Running   0          45s
fluentd-xyz89   1/1     Running   0          45s
```

### Logs del propio Fluentd
```powershell
kubectl logs -n logging -l app=fluentd --tail=50
```
Busca líneas como:
```
[info]: starting fluentd-1.16.x
[info]: gem 'fluent-plugin-elasticsearch' version '5.x.x'
[info]: adding source type="tail"
[info]: adding match pattern="**" type="elasticsearch"
[info]: fluentd worker is now running worker=0
```

> Si ves `[error]: ... Connection refused`, probablemente Elasticsearch no esté `Running` o no resuelva el DNS. Verifica con `kubectl get pods -n logging`.

### Verifica que se está creando el índice en Elasticsearch

Abre el túnel a Kibana (si no lo tienes ya):
```powershell
kubectl port-forward -n logging svc/kibana 5601:5601
```

En Kibana → **Dev Tools** ejecuta:
```
GET /_cat/indices?v
```

A los pocos segundos deberías ver el índice diario:
```
health status index               uuid    pri rep docs.count store.size
yellow open   logs-k8s-2026.05.01 xxx     1   1   1234       2.5mb
```

> El status `yellow` es normal en single-node ES (las réplicas quedan unassigned porque solo hay 1 nodo). En producción multi-nodo aparecería `green`.

### Crear un Data View en Kibana para explorar los logs

1. Menú ≡ → **Stack Management → Data Views → Create data view**.
2. **Name**: `logs-k8s`
3. **Index pattern**: `logs-k8s-*`
4. **Timestamp field**: `@timestamp`
5. **Save data view to Kibana**.

Ahora menú ≡ → **Discover**:
- En el selector de Data View elige `logs-k8s`.
- Cambia el rango de tiempo arriba a la derecha a "Last 15 minutes".
- Deberías ver eventos llegando: logs del propio sistema (kube-proxy, coredns, etc.) y de los pods que ya tenemos (Elasticsearch, Kibana).

¡Felicitaciones! Ya tienes logs centralizados. ✅

## 5.7 Troubleshooting

| Síntoma                                                       | Causa probable                                       | Solución                                                                              |
|---------------------------------------------------------------|------------------------------------------------------|---------------------------------------------------------------------------------------|
| `CrashLoopBackOff` en pods de Fluentd                          | Error en `fluent.conf` (sintaxis o plugin faltante)  | `kubectl logs <pod> -n logging`. Suele ser un typo en el ConfigMap.                  |
| `Connection refused` en logs de Fluentd                        | ES aún no Ready o DNS mal                            | `kubectl get pods -n logging`, esperar.                                              |
| No aparecen índices `logs-k8s-*` en `GET /_cat/indices`        | Pods recién arrancados                               | Esperar 30-60 s. Forzar logs: hacer cualquier acción en el cluster.                   |
| Discover muestra "No results"                                  | Rango de tiempo incorrecto                           | Cambiar a "Last 15 minutes".                                                          |
| Discover muestra los logs pero el campo `log` viene como string | Aún no aplicamos parser JSON (eso es Fase 7)         | OK por ahora. En Fase 7 lo arreglamos.                                               |

## 5.8 Capturas para el informe

1. `kubectl get pods -n logging -l app=fluentd -o wide` mostrando un pod por nodo.
2. `kubectl logs -n logging -l app=fluentd --tail=20` con la línea "fluentd worker is now running".
3. `GET /_cat/indices?v` en Dev Tools mostrando el índice `logs-k8s-YYYY.MM.DD`.
4. Vista de **Discover** con eventos en tiempo real.

## 5.9 Entregables de esta fase

- DaemonSet `fluentd` con 1 pod por nodo, todos `Running`.
- Índice `logs-k8s-YYYY.MM.DD` creándose en Elasticsearch.
- Data View `logs-k8s` configurado en Kibana.
- Logs visibles en Discover.

---

**Siguiente fase:** Fase 6 — Apps de prueba (Nginx + JSON app) que generen logs interesantes para parsear y analizar.

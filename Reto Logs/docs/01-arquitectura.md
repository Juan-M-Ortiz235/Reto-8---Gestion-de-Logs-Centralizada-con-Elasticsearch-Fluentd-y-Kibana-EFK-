# Fase 1 — Diseño de arquitectura EFK en DigitalOcean Kubernetes (DOKS)

## 1.1 Objetivo de la fase

Definir la arquitectura técnica de la solución de gestión de logs centralizada antes de aprovisionar recursos en DigitalOcean. Esta fase es 100% de planificación: no se crea infraestructura todavía.

## 1.2 Diagrama lógico de la solución

```
                       ┌────────────────────────────────────────────────────────────┐
                       │              DigitalOcean Kubernetes (DOKS)                │
                       │                  Cluster: efk-cluster                      │
                       │                                                            │
                       │  Namespace: apps                Namespace: logging         │
                       │  ┌───────────────────┐          ┌──────────────────────┐   │
                       │  │  nginx-demo       │          │  elasticsearch       │   │
   Usuario / Browser   │  │  (Deployment)     │          │  (StatefulSet, 1 pod)│   │
   ┌──────────────┐    │  │  + Service        │          │  + PVC (DO Block)    │   │
   │ navegador    │────┼─▶│  + LB (opcional)  │          │  + ClusterIP svc     │   │
   └──────────────┘    │  └─────────┬─────────┘          └──────────┬───────────┘   │
          │            │            │                               │               │
          │            │  ┌─────────┴─────────┐                     │               │
          │            │  │  json-app         │                     │               │
          │            │  │  (Deployment)     │                     │               │
          │            │  │  emite logs JSON  │                     │               │
          │            │  └───────────────────┘                     │               │
          │            │                                            ▼               │
          │            │                              ┌──────────────────────────┐  │
          │            │                              │  fluentd (DaemonSet)     │  │
          │            │                              │  - lee /var/log/contain. │  │
          │            │                              │  - parsea Nginx + JSON   │  │
          │            │                              │  - envía a Elasticsearch │  │
          │            │                              └──────────────────────────┘  │
          │            │                                            │               │
          │            │                                            ▼               │
          │            │                              ┌──────────────────────────┐  │
          │            │                              │  kibana (Deployment)     │  │
          │            │                              │  + Service LoadBalancer  │  │
          └────────────┼─────────────────────────────▶│  (puerto 5601)           │  │
                       │                              └──────────────────────────┘  │
                       └────────────────────────────────────────────────────────────┘
```

## 1.3 Componentes y responsabilidades

| Componente      | Tipo en K8s         | Función principal                                                                 |
|-----------------|---------------------|-----------------------------------------------------------------------------------|
| Elasticsearch   | StatefulSet (1 réplica) | Almacenamiento, indexación y búsqueda full-text de logs.                       |
| Kibana          | Deployment + Service LB | UI web para explorar índices, crear data views y dashboards.                   |
| Fluentd         | DaemonSet               | Agente en cada nodo que lee `/var/log/containers/*.log`, parsea y reenvía.     |
| Nginx demo      | Deployment + Service    | Servidor web que genera logs de acceso y error (formato common/combined).      |
| JSON app demo   | Deployment              | App Node.js que emite logs estructurados en JSON con campos `level`, `msg`, etc.|

## 1.4 Decisiones de diseño

### Por qué DaemonSet para Fluentd
En Kubernetes, todos los contenedores escriben sus stdout/stderr a `/var/log/containers/*.log` en el nodo. Un DaemonSet garantiza que haya **exactamente un Fluentd por nodo**, montando ese directorio como hostPath. Esto evita configurar Fluentd dentro de cada pod y captura logs de cualquier app sin modificar su imagen.

### Por qué StatefulSet para Elasticsearch
Elasticsearch necesita identidad de red estable y volumen persistente por pod. StatefulSet provee:
- Nombres DNS estables (`elasticsearch-0.elasticsearch.logging.svc.cluster.local`)
- PVC dedicado por pod (no se borra al reiniciar el pod)
- Orden garantizado de despliegue (importante en clusters multi-nodo de ES)

Para esta demo educativa usamos **1 réplica** (modo single-node) para minimizar costos. En producción se recomiendan ≥3 nodos master + nodos data dedicados.

### Por qué namespaces separados
- `logging`: aísla el stack EFK del resto del cluster.
- `apps`: contiene las apps que generan logs. Permite aplicar NetworkPolicies y RBAC granulares en el futuro.

### Índices en Elasticsearch
Se utilizarán **data streams** (recomendado desde ES 7.9+) con la convención:
- `logs-nginx-*` para logs del servidor web
- `logs-jsonapp-*` para logs de la app JSON
- `logs-k8s-*` para el resto (logs de sistema/contenedores genéricos)

Cada uno con su **index template** y **ILM policy** básica (rollover diario, retención 7 días en demo).

## 1.5 Sizing y costos estimados (DigitalOcean)

| Recurso                    | Tamaño                  | Costo aprox./mes USD |
|----------------------------|-------------------------|----------------------|
| DOKS control plane         | Gestionado (gratis)     | $0                   |
| Node pool (2 × s-2vcpu-4gb)| 4 vCPU / 8 GB total     | $48                  |
| DO Block Storage           | 10 Gi para ES           | ~$1                  |
| Load Balancer (Kibana)     | 1 LB                    | $12                  |
| **Total estimado**         |                         | **~$61/mes**         |

> Para la demo del reto se recomienda destruir el cluster al finalizar la entrega para no incurrir en costos. DigitalOcean cobra por hora prorrateada.

### Alternativa low-cost
Si el presupuesto es ajustado, se puede usar:
- 2 × s-2vcpu-2gb (~$24/mes) — pero Elasticsearch puede tener problemas de memoria.
- Sin LoadBalancer: usar `kubectl port-forward` para Kibana (gratis pero solo accesible localmente).

## 1.6 Requisitos de capacidad

- **CPU mínimo**: 2 vCPU disponibles para Elasticsearch (heap JVM 512 MB - 1 GB).
- **RAM mínima**: 2 GB para ES, 1 GB para Kibana, 256 MB por Fluentd, ~1 GB para apps demo. Total ≈ 4-5 GB.
- **Almacenamiento**: 10 Gi para ES (suficiente para semanas de logs en demo).

## 1.7 Modelo de seguridad (nivel básico)

- Cluster privado con kubeconfig descargado a la máquina del estudiante.
- Acceso a Kibana protegido por su LoadBalancer expuesto en internet pero **sin autenticación X-Pack** en esta etapa (es una demo educativa). Recomendado configurar autenticación si se mantiene online.
- Secrets de Kubernetes para credenciales de cualquier servicio que las requiera.
- Firewall nativo de DOKS (Cloud Firewall) limitando el acceso al LB de Kibana a la IP del estudiante.
- HTTPS no habilitado en demo (se usa HTTP); en producción se recomienda Let's Encrypt + cert-manager.

## 1.8 Flujo end-to-end de un log

1. La app (Nginx o json-app) escribe a stdout dentro del contenedor.
2. El runtime de Kubernetes (containerd) escribe ese stdout en `/var/log/containers/<pod>_<ns>_<container>-<id>.log` en el nodo.
3. Fluentd (DaemonSet) tail-ea ese archivo, agrega metadata de Kubernetes (pod name, namespace, labels), aplica el parser correspondiente.
4. Fluentd reenvía el evento al Service de Elasticsearch (`elasticsearch.logging.svc.cluster.local:9200`).
5. Elasticsearch indexa el documento en el data stream correspondiente.
6. Kibana consulta Elasticsearch para mostrarlo en un Discover o dashboard.

## 1.9 Prerequisitos antes de pasar a Fase 2

| Item                                                   | Estado |
|--------------------------------------------------------|--------|
| Cuenta de DigitalOcean activa con método de pago       | ☐      |
| `kubectl` instalado localmente                         | ☐      |
| `helm` instalado localmente (v3+)                      | ☐      |
| `doctl` instalado y autenticado (CLI de DigitalOcean)  | ☐      |
| Editor de texto (VS Code recomendado)                  | ☐      |

## 1.10 Entregables de esta fase

- Este documento (`01-arquitectura.md`).
- Estructura de carpetas del proyecto creada.
- Lista de prerequisitos a cumplir antes de pasar a Fase 2.

---

**Siguiente fase:** Fase 2 — Provisioning del cluster DOKS.

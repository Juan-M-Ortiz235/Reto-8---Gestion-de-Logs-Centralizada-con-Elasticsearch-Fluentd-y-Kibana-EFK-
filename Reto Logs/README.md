# Reto 8 — Gestión de logs centralizada con EFK en DigitalOcean Kubernetes (DOKS)

Solución de gestión de logs centralizada usando **Elasticsearch + Fluentd + Kibana** desplegada en un cluster Kubernetes administrado de DigitalOcean. Recolecta logs de un servidor web Nginx y de una aplicación que emite logs estructurados en JSON.

> Este README se actualiza fase por fase. La versión actual cubre hasta la Fase 1.

## Estado del proyecto

- [x] Fase 1 — Diseño de arquitectura
- [x] Fase 2 — Provisioning del cluster DOKS
- [ ] Fase 3 — Despliegue de Elasticsearch
- [ ] Fase 4 — Despliegue de Kibana
- [ ] Fase 5 — Despliegue de Fluentd (DaemonSet)
- [ ] Fase 6 — Apps de prueba (Nginx + JSON app)
- [ ] Fase 7 — Parsers y mappings
- [ ] Fase 8 — Dashboards en Kibana
- [ ] Fase 9 — Documentación final

## Estructura del repositorio

```
.
├── README.md                  ← este archivo
├── docs/                      ← documentación por fase + informe técnico
│   └── 01-arquitectura.md
├── k8s/                       ← manifiestos Kubernetes
├── apps/                      ← código de las apps demo (Nginx, JSON app)
├── kibana/                    ← exportes de data views, dashboards
└── scripts/                   ← scripts de despliegue/limpieza
```

## Stack tecnológico

| Componente     | Versión usada       | Rol                                           |
|----------------|---------------------|-----------------------------------------------|
| Elasticsearch  | 8.13.x              | Almacenamiento e indexación de logs           |
| Kibana         | 8.13.x              | UI web para búsqueda y dashboards             |
| Fluentd        | v1.16 (image fluent/fluentd-kubernetes-daemonset) | Recolección y parsing |
| Kubernetes     | DOKS 1.29           | Orquestación                                  |
| Nginx          | 1.25-alpine         | Servidor web demo (genera logs de acceso)     |
| Node.js app    | Node 20             | App demo que emite logs JSON                  |

## Cómo leer la documentación

1. Empieza por `docs/01-arquitectura.md` para entender la solución global.
2. Cada fase agrega su propio documento numerado en `docs/`.
3. Al final del proyecto se entrega un **informe técnico en Word** y una **presentación PowerPoint** consolidados en `docs/`.

## Costos estimados

~$61/mes mientras el cluster esté activo. Recomendado destruir el cluster con `scripts/destroy.sh` al terminar la práctica para no acumular costos.

## Autor

David — Universidad Industrial de Santander (UIS)
Reto 8 — Gestión de Logs Centralizada (EFK)

# Fase 4 — Despliegue de Kibana

## 4.1 Objetivo

Desplegar Kibana 8.13.4 conectado al Elasticsearch desplegado en la Fase 3, y acceder a su UI web desde tu navegador local para empezar a explorar el cluster.

## 4.2 Componentes del manifiesto

`k8s/02-kibana.yaml` crea 3 recursos:

| Recurso        | Tipo               | Función                                                   |
|----------------|--------------------|-----------------------------------------------------------|
| `kibana-config`| ConfigMap          | `kibana.yml` con apuntador a Elasticsearch.              |
| `kibana`       | Service ClusterIP  | Endpoint interno en el puerto 5601.                       |
| `kibana`       | Deployment (1 pod) | Pod de Kibana 8.13.4.                                     |

## 4.3 Decisiones de diseño explicadas

### Conexión a Elasticsearch
Kibana se conecta vía DNS interno de Kubernetes:
```
http://elasticsearch.logging.svc.cluster.local:9200
```
Como ambos viven en el mismo namespace `logging`, también funciona la forma corta `http://elasticsearch:9200`.

### Strategy `Recreate` en lugar de `RollingUpdate`
Kibana es state-less pero su versión debe coincidir con Elasticsearch. Mantener 2 pods de versiones distintas durante un rolling update puede causar errores. `Recreate` asegura que el viejo se mata antes de crear el nuevo.

### Encryption keys
Kibana 8 exige tres claves de cifrado de 32+ caracteres para guardar objetos cifrados (alertas, etc.) de forma persistente. Las definimos como variables de entorno fijas. **En producción** se guardarían en un `Secret` de Kubernetes y se montarían como `valueFrom: secretKeyRef`. Para esta demo (seguridad básica) están en texto plano.

### Recursos
Kibana 8 corre Node.js + un servidor de plugins. Necesita ~1 GB de RAM mínimo para cargar todos los plugins por defecto. Pedimos 1 Gi de request, 1.5 Gi de límite.

### Probes
- **Readiness** sobre `GET /api/status`: hasta que Kibana no termina de cargar plugins y conectar a ES, el Service no enruta tráfico al pod.
  - `failureThreshold: 30` y `periodSeconds: 10` → tolera hasta 5 minutos de arranque.
- **Liveness** TCP en 5601: si el proceso muere se reinicia.

### Service ClusterIP por defecto
Para esta demo educativa exponemos Kibana **solo internamente** y accedemos desde tu PC con `kubectl port-forward`. Esto:
- **No cuesta nada** (sin LoadBalancer).
- Es totalmente seguro (no hay puerto público abierto).
- Suficiente para hacer la demo y tomar capturas.

Si en algún momento necesitas acceso público (sección 4.6) puedes patchear el Service a `LoadBalancer` con un solo comando.

## 4.4 Aplicar el manifiesto

```powershell
cd "C:\Users\david\Documents\Reto Logs"
kubectl apply -f .\k8s\02-kibana.yaml
```

Salida esperada:
```
configmap/kibana-config created
service/kibana created
deployment.apps/kibana created
```

## 4.5 Verificar el despliegue

### Estado del pod
```powershell
kubectl get pods -n logging
```

Espera que Kibana esté `1/1 Running`. **Tarda 1-2 minutos** la primera vez (descarga la imagen ~700 MB y arranca Node.js + plugins). Si quieres ver la evolución en vivo, usa `-w` y luego `Ctrl+C`.

### Logs del pod (si tarda en estar Ready)
```powershell
kubectl logs -n logging deploy/kibana -f
```
Busca la línea final:
```
{"...,"message":"Kibana is now available (was degraded)"}
```

Si ves errores tipo "Unable to connect to Elasticsearch", revisa que ES esté `Running`:
```powershell
kubectl get pods -n logging
```

### Acceder a la UI

Abre el túnel desde tu PC:
```powershell
kubectl port-forward -n logging svc/kibana 5601:5601
```

Y en tu navegador entra a:
```
http://localhost:5601
```

Deberías ver la pantalla de bienvenida de Kibana.

> **Primera vez**: Kibana puede preguntarte si "explorar por tu cuenta" o "agregar integraciones". Para esta demo selecciona **"Explore on my own"**.

### Verificar la conexión Kibana ↔ Elasticsearch desde la UI

En la UI de Kibana:
1. Click en el menú hamburguesa (≡) arriba a la izquierda.
2. Baja hasta **Management → Stack Management → Index Management**.
3. Deberías ver la lista vacía de índices (aún no recolectamos logs). Esto confirma que Kibana está hablando con Elasticsearch.

Otra prueba: en el menú **Dev Tools** (icono `>_`), ejecuta:
```
GET /
```
Debe responder con la información del cluster (igual que el `curl` de la Fase 3).

## 4.6 Opcional — Exponer Kibana públicamente con LoadBalancer

> Solo si necesitas acceso desde un navegador en otra máquina sin `kubectl`. **Cuesta ~$12/mes** en DigitalOcean.

```powershell
kubectl patch svc kibana -n logging -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'
```

Espera ~2-3 minutos a que DO provisione el LB:
```powershell
kubectl get svc -n logging kibana -w
```

Cuando salga la `EXTERNAL-IP`, ya puedes entrar a `http://<EXTERNAL-IP>:5601` desde cualquier navegador.

**Importante**: como Kibana corre sin autenticación X-Pack en esta demo, **cualquiera con esa IP puede ver tus logs**. Mitigación rápida: en DigitalOcean → Networking → Firewalls, crea una regla que limite el tráfico al puerto 5601 a tu IP pública.

Para volver a `ClusterIP` y ahorrar el costo:
```powershell
kubectl patch svc kibana -n logging -p '{\"spec\":{\"type\":\"ClusterIP\"}}'
```

## 4.7 Troubleshooting

| Síntoma                                                  | Causa probable                              | Solución                                                                                  |
|----------------------------------------------------------|---------------------------------------------|-------------------------------------------------------------------------------------------|
| Pod queda en `Running` pero `0/1` Ready durante 5+ min   | Plugins de Kibana cargando lento            | Esperar. `kubectl logs deploy/kibana -n logging`.                                         |
| Logs muestran `connect ECONNREFUSED 10.x.x.x:9200`       | ES no está `Running` o se está reiniciando  | `kubectl get pods -n logging`, espera a que ES esté `1/1 Running`.                         |
| Browser muestra "Kibana server is not ready yet"         | Kibana aún arrancando                       | Esperar y refrescar en 1 min.                                                             |
| `Error: Unable to retrieve version information`          | URL de ES incorrecta en `kibana.yml`/env    | Verificar `ELASTICSEARCH_HOSTS=http://elasticsearch.logging.svc.cluster.local:9200`.       |

## 4.8 Capturas para el informe

1. `kubectl get all -n logging` mostrando los 2 deployments (ES + Kibana).
2. `kubectl logs deploy/kibana -n logging` con la línea "Kibana is now available".
3. La pantalla de bienvenida de Kibana en el navegador (`http://localhost:5601`).
4. **Dev Tools → GET /** mostrando la respuesta de Elasticsearch.
5. **Stack Management → Index Management** (con la tabla vacía — confirma conexión).

## 4.9 Entregables de esta fase

- Pod `kibana` corriendo y conectado a Elasticsearch.
- UI accesible en `http://localhost:5601` vía port-forward.
- Verificación de la conexión ES↔Kibana en la UI.

---

**Siguiente fase:** Fase 5 — Despliegue de Fluentd como DaemonSet.

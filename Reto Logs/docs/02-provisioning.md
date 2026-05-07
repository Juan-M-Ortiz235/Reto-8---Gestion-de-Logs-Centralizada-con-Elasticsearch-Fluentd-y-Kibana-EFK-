# Fase 2 — Provisioning del cluster DOKS y herramientas locales

En esta fase aprovisionamos el cluster Kubernetes en DigitalOcean y dejamos lista la máquina del estudiante para gestionarlo. Se documentan **dos formas** de hacerlo:

- **Vía A: Interfaz web** de DigitalOcean (recomendada para el informe — permite capturas de pantalla).
- **Vía B: CLI con `doctl`** (recomendada para reproducibilidad — script automatizable).

> Puedes hacerlas las dos: crear el cluster por la web la primera vez (para entender la UI y capturar evidencias) y luego destruirlo y recrearlo por CLI (para demostrar la versión automatizada en el informe).

---

## 2.1 Prerequisitos

1. **Cuenta DigitalOcean** activa. Si recién la creas, valida tu correo y agrega un método de pago.
2. **Token de API personal**:
   - Login en https://cloud.digitalocean.com/
   - Menú izquierdo → **API** → **Tokens**.
   - Click en **Generate New Token** → Nombre: `efk-reto`, Scope: **Full Access** (read + write), Expiration: 30 días.
   - Copia el token y guárdalo en un gestor de contraseñas. **No lo subas a Git.**
3. **Sistema operativo del estudiante**: Linux, macOS o Windows con WSL2.

---

## 2.2 Instalación de herramientas locales

Necesitas tres binarios locales: `doctl`, `kubectl` y `helm`.

### Linux / macOS

```bash
# 1. doctl (CLI de DigitalOcean)
# Linux:
cd /tmp
wget https://github.com/digitalocean/doctl/releases/download/v1.104.0/doctl-1.104.0-linux-amd64.tar.gz
tar xf doctl-1.104.0-linux-amd64.tar.gz
sudo mv doctl /usr/local/bin/

# macOS (Homebrew):
brew install doctl

# Verifica:
doctl version

# 2. kubectl (CLI de Kubernetes)
# Linux:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# macOS:
brew install kubectl

# Verifica:
kubectl version --client

# 3. helm (gestor de paquetes para Kubernetes)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verifica:
helm version
```

### Windows (PowerShell, sin WSL)

```powershell
# Usando winget:
winget install DigitalOcean.Doctl
winget install Kubernetes.kubectl
winget install Helm.Helm

# O usando Chocolatey:
choco install doctl kubernetes-cli kubernetes-helm
```

### Autenticación de doctl

```bash
doctl auth init
# Pega el token generado en el paso 2.1.2 cuando lo solicite.

# Verifica que la conexión funcione:
doctl account get
# Debe mostrar tu email, status: active.
```

---

## 2.3 Vía A — Crear el cluster por la interfaz web (recomendado para capturas)

1. Login en https://cloud.digitalocean.com/.
2. Menú izquierdo → **Kubernetes** → botón verde **Create Kubernetes Cluster**.
3. **Choose a Kubernetes version**: deja la versión recomendada (ej. `1.29.x-do.0`).
4. **Choose a datacenter region**: elige la más cercana al estudiante. Para Colombia, **NYC3** (New York) o **SFO3** (San Francisco) son las que mejor latencia ofrecen.
5. **VPC Network**: deja la default (`default-nyc3` o equivalente).
6. **Choose cluster capacity**:
   - Node pool name: `default-pool`
   - Machine type: **Basic nodes — Regular Intel — 4 GB / 2 vCPU** (precio aprox. $24/mes por nodo).
   - Node count: **2** (mínimo recomendado).
   - Auto-scale: deja desactivado por ahora.
7. **Choose a name**: `efk-cluster`.
8. **Project**: deja `default` o crea uno llamado `Reto-EFK`.
9. **Add tags** (opcional pero útil para limpieza): agrega tag `reto-efk`.
10. Click en **Create Cluster**. La creación tarda **3-5 minutos**.

### Configurar kubectl (vía web)

Cuando el cluster esté listo:

1. Entra al cluster desde la UI.
2. Botón **Actions** → **Download Config File** (descarga `efk-cluster-kubeconfig.yaml`).
3. Configurar la variable de entorno:

```bash
# Linux/macOS
export KUBECONFIG=$HOME/Downloads/efk-cluster-kubeconfig.yaml
# o copiarlo a la ubicación estándar:
mkdir -p ~/.kube
cp $HOME/Downloads/efk-cluster-kubeconfig.yaml ~/.kube/config
chmod 600 ~/.kube/config

# Verifica:
kubectl get nodes
# Debe listar los 2 nodos en estado "Ready"
```

> **Capturas de pantalla recomendadas para el informe:**
> 1. Pantalla de creación del cluster (formulario completo).
> 2. Cluster en estado "Provisioning".
> 3. Cluster en estado "Healthy" con los 2 nodos.
> 4. Salida de `kubectl get nodes` con los nodos `Ready`.

---

## 2.4 Vía B — Crear el cluster por CLI (reproducible)

```bash
# 1. Listar regiones disponibles:
doctl kubernetes options regions

# 2. Listar versiones disponibles:
doctl kubernetes options versions

# 3. Listar tamaños de nodo disponibles:
doctl kubernetes options sizes
# Para esta demo: s-2vcpu-4gb

# 4. Crear el cluster (reemplaza la región y versión por las actuales):
doctl kubernetes cluster create efk-cluster \
  --region nyc3 \
  --version 1.29.1-do.0 \
  --node-pool "name=default-pool;size=s-2vcpu-4gb;count=2;tag=reto-efk" \
  --tag reto-efk \
  --wait

# Tarda ~4-5 minutos. Al terminar, doctl configura automáticamente
# kubectl con el contexto del cluster.

# 5. Verifica:
kubectl config current-context
# do-nyc3-efk-cluster

kubectl get nodes
# NAME                STATUS   ROLES    AGE   VERSION
# default-pool-xxxxx  Ready    <none>   2m    v1.29.1
# default-pool-yyyyy  Ready    <none>   2m    v1.29.1
```

### Equivalente automatizado

Hay un script en `scripts/provision-cluster.sh` que ejecuta lo anterior con variables ajustables. Puedes correrlo así:

```bash
chmod +x scripts/provision-cluster.sh
./scripts/provision-cluster.sh
```

---

## 2.5 Crear los namespaces

Independientemente de la vía elegida, una vez tengas `kubectl` apuntando al cluster:

```bash
kubectl apply -f k8s/00-namespaces.yaml

# Verifica:
kubectl get ns
# logging  Active   ...
# apps     Active   ...
```

---

## 2.6 Verificación final de Fase 2

Estos comandos deben funcionar antes de pasar a Fase 3:

```bash
kubectl get nodes               # 2 nodos Ready
kubectl get ns                  # incluye 'logging' y 'apps'
kubectl cluster-info            # muestra el endpoint del API
helm version                    # v3.x
doctl kubernetes cluster list   # muestra efk-cluster
```

---

## 2.7 Cómo destruir el cluster (al terminar la práctica)

> **Importante**: DigitalOcean cobra por hora. No olvides destruir el cluster cuando termines.

### Vía web
Kubernetes → `efk-cluster` → **Destroy** → escribir el nombre del cluster para confirmar.
También elimina manualmente cualquier **Volume** (Block Storage) o **Load Balancer** que haya quedado huérfano (Networking → Load Balancers, Volumes).

### Vía CLI (más limpio)

```bash
./scripts/destroy.sh
```

El script destruye el cluster, los Load Balancers asociados y los volúmenes Block Storage etiquetados con `reto-efk`.

---

## 2.8 Entregables de esta fase

- Cluster DOKS `efk-cluster` operativo con 2 nodos Ready.
- `kubectl` configurado localmente apuntando al cluster.
- Namespaces `logging` y `apps` creados.
- Script `provision-cluster.sh` y `destroy.sh` listos.

---

**Siguiente fase:** Fase 3 — Despliegue de Elasticsearch.

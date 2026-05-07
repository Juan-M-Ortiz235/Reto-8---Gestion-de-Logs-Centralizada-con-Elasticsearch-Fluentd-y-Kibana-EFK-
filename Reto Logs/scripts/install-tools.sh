#!/usr/bin/env bash
# install-tools.sh
# Instala doctl, kubectl y helm en Linux x86_64.
# En macOS es preferible usar Homebrew (ver docs/02-provisioning.md).

set -euo pipefail

DOCTL_VERSION="1.104.0"

echo "=== Instalando doctl v${DOCTL_VERSION} ==="
cd /tmp
wget -q "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz"
tar xf "doctl-${DOCTL_VERSION}-linux-amd64.tar.gz"
sudo mv doctl /usr/local/bin/
rm -f "doctl-${DOCTL_VERSION}-linux-amd64.tar.gz"
doctl version

echo
echo "=== Instalando kubectl (latest stable) ==="
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl
kubectl version --client

echo
echo "=== Instalando helm v3 ==="
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

echo
echo "=== Listo ==="
echo "Próximo paso: 'doctl auth init' y pegar tu token de DigitalOcean."

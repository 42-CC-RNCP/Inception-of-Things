#!/usr/bin/env bash
set -euo pipefail
IP=${1:?provide server IP}

GWA_VER="v1.3.0"
TRAEFIK_NS="application"

echo "▶️ 1. Install k3s without built-in Traefik"
curl -sfL https://get.k3s.io | \
    INSTALL_K3S_CHANNEL=stable \
    INSTALL_K3S_EXEC="server \
   --disable=traefik --tls-san ${IP} --write-kubeconfig-mode 644" sh -

echo "▶️ 2. Wait for k3s API"
until kubectl get --raw=/healthz &>/dev/null; do sleep 2; done
echo "k3s version: $(k3s --version | awk '{print $3}')"

echo "▶️ 3. Install Gateway-API CRDs (${GWA_VER})"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWA_VER}/standard-install.yaml

echo "▶️ 4. Install Traefik Gateway-API RBAC"
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.5/docs/content/reference/dynamic-configuration/kubernetes-gateway-rbac.yml



echo "▶️ 5. Deploy Traefik v3 with Gateway provider"

echo "  Installing Helm 3 CLI"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm uninstall traefik -n kube-system || true
helm version --short
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace "${TRAEFIK_NS}" --create-namespace --wait \
  --set providers.kubernetesGateway.enabled=true \
  --set providers.kubernetesIngress.enabled=true \
  --set ingressClass.enabled=true \
  --set ports.web.port=80 \
  --set ports.web.targetPort=80 \
  --set ports.websecure.port=443 \
  --set ports.websecure.targetPort=443 \
  --set gateway.listeners.web.port=80 \
  --set gateway.enabled=false

echo "▶️ 6. Wait for Traefik to be Ready"
kubectl rollout status deploy/traefik -n ${TRAEFIK_NS} --timeout=180s

echo "▶️ 7. Apply GatewayClass/Gateway and routes"
kubectl apply -k /vagrant/manifests     # your app + HTTPRoutes

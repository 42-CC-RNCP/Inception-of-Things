#!/bin/bash
set -euo pipefail

IP=$1
GWA_VER="v1.3.0"

echo "Setting up Traefik Gateway configuration"
sudo mkdir -p /var/lib/rancher/k3s/server/manifests
sudo cp /vagrant/manifests/traefik-gateway-config.yaml /var/lib/rancher/k3s/server/manifests/traefik-gateway-config.yaml 

echo "Installing k3s on $(hostname) node with IP: ${IP}"

# Install k3s
curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="server \
    --tls-san ${IP} \
    --write-kubeconfig-mode 644" sh -

echo "k3s installed successfully on $(hostname)"

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
while ! kubectl get nodes; do
    sleep 5
done

echo "k3s is ready on $(hostname)"

# Wait for Traefik deployment to show up
echo "Waiting for Traefik deployment to appear..."
while ! kubectl get deployment traefik -n kube-system &>/dev/null; do
    sleep 2
done

echo "Waiting for Traefik to be available..."
kubectl wait --for=condition=Available deployment/traefik -n kube-system --timeout=180s

echo "Install Gateway API version ${GWA_VER} on k3s server"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWA_VER}/standard-install.yaml

echo "Gateway API installed successfully on k3s server"


echo "Applying Traefik Gateway configuration"
kubectl create namespace application --dry-run=client -o yaml | kubectl apply -f -


echo "Applying customized configurations"

kubectl apply -k /vagrant/manifests

echo "Custom configurations applied successfully"


kubectl get nodes -o wide

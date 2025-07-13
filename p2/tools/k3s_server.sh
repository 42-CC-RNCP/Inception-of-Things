#!/bin/bash
set -euo pipefail

IP=$1
GWA_VER="v1.3.0"

echo "Installing k3s on $(hostname) node with IP: ${IP}"

# Install k3s
curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="server \
    --tls-san ${IP} \
    --write-kubeconfig-mode 644" sh -

echo "k3s installed successfully on $(hostname)"

echo "Install Gateway API version ${GWA_VER} on k3s server"

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWA_VER}/standard-install.yaml

echo "Gateway API installed successfully on k3s server"

echo "Applying customized configurations"

kubectl apply -k /vagrant/manifests

echo "Custom configurations applied successfully"

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
while ! kubectl get nodes; do
    sleep 5
done

echo "k3s is ready on $(hostname)"

kubectl get nodes -o wide

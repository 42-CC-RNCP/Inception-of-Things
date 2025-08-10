#!/bin/bash
set -e

SERVER_IP=$1

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --tls-san ${SERVER_IP} --write-kubeconfig-mode 644" sh -

kubectl apply -k /vagrant/manifests/overlays/ingress

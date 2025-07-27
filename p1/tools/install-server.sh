#!/bin/bash

SERVER_IP=$1

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --tls-san ${SERVER_IP} --write-kubeconfig-mode 644"  sh -

install -m 600 /var/lib/rancher/k3s/server/node-token /vagrant_data/secrets
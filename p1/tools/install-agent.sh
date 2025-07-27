#!/bin/bash

SERVER_IP=$1

export K3S_TOKEN=$(cat /vagrant_data/secrets)
export K3S_URL="https://${SERVER_IP}:6443"

curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="agent" K3S_URL=${K3S_URL} K3S_TOKEN=${K3S_TOKEN} sh -
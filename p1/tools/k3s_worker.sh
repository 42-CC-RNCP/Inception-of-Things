#!/bin/bash
set -e

MASTER_IP=$1

# Get the token from the master node
TOKEN=$(cat /vagrant/k3s_master_token)

# Install k3s worker and join the master node
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=$TOKEN sh -

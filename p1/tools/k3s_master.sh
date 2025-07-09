#!/bin/bash
set -e

# Install k3s
curl -sfL https://get.k3s.io | sh -

# Make sure kubectl is set up for the vagrant user
sudo mkdir -p /home/vagrant/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sudo chown -R vagrant:vagrant /home/vagrant/.kube/config

# Get the token for the worker nodes
TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

# Store the token in a file for later use
echo $TOKEN > /vagrant/k3s_master_token

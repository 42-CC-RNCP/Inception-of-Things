#!/bin/bash

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san 192.168.56.110 --write-kubeconfig-mode 644"  sh -

install -m 600 /var/lib/rancher/k3s/server/node-token /vagrant_data/secrets
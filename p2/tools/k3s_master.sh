#!/bin/bash
set -e

SERVER_IP=$1

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --tls-san ${SERVER_IP} --write-kubeconfig-mode 644" sh -

kubectl apply -f /vagrant/k8s/app1.yaml
kubectl apply -f /vagrant/k8s/app1-service.yaml
kubectl apply -f /vagrant/k8s/app2.yaml
kubectl apply -f /vagrant/k8s/app2-service.yaml
kubectl apply -f /vagrant/k8s/app3.yaml
kubectl apply -f /vagrant/k8s/app3-service.yaml

kubectl create configmap app1-html --from-file=/vagrant/tools/app1.html
kubectl create configmap app2-html --from-file=/vagrant/tools/app2.html
kubectl create configmap app3-html --from-file=/vagrant/tools/app3.html
kubectl apply -f /vagrant/k8s/ingress.yaml

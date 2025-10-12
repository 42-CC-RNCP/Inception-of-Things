SHELL := /bin/bash

CLUSTER_NAME        ?= mycluster
ARGOCD_HOST_PORT    ?= 8080
APP_HOST_PORT       ?= 8888
BOOTSTRAP_SCRIPT    ?= tools/bootstrap_argocd.sh

KUBECTL             ?= kubectl
K3D                 ?= k3d

.PHONY: all clean fclean re

all:
	@echo "==> Running bootstrap with CLUSTER_NAME=$(CLUSTER_NAME) ARGOCD_HOST_PORT=$(ARGOCD_HOST_PORT) APP_HOST_PORT=$(APP_HOST_PORT)"
	@CLUSTER_NAME="$(CLUSTER_NAME)" ARGOCD_HOST_PORT="$(ARGOCD_HOST_PORT)" APP_HOST_PORT="$(APP_HOST_PORT)" "$(BOOTSTRAP_SCRIPT)"

## Remove app + Argo CD namespaces (cluster remains)
clean:
	@echo "==> Deleting Argo CD Application (if any) and namespaces (argocd, dev)"
	-@$(KUBECTL) -n argocd delete application p3-dev 2>/dev/null || true
	-@$(KUBECTL) delete ns dev argocd 2>/dev/null || true
	@echo "==> Clean done (cluster '$(CLUSTER_NAME)' still present)"

## Full clean: clean + delete k3d cluster
fclean: clean
	@echo "==> Deleting k3d cluster '$(CLUSTER_NAME)'"
	-@$(K3D) cluster delete "$(CLUSTER_NAME)" 2>/dev/null || true
	@echo "==> Full clean done"

## Rebuild from scratch
re: fclean all

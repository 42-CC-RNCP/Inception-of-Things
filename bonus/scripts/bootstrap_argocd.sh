#!/usr/bin/env bash
# scripts/bootstrap_argocd.sh
set -euo pipefail

# =========================
# Helpers
# =========================
log()  { echo -e "👉 \e[1m$*\e[0m"; }
ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*"; }
die()  { echo -e "❌ $*" >&2; exit 1; }

# =========================
# Config
# =========================
CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
ARGOCD_INSTALL_URL=${ARGOCD_INSTALL_URL:-"https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"}
ARGOCD_HOST_PORT="${ARGOCD_HOST_PORT:-8080}"   # maps to cluster LB :8443
APP_HOST_PORT="${APP_HOST_PORT:-8888}"         # maps to cluster LB :8888
ARGOCD_MANIFESTS_DIR="${ARGOCD_MANIFESTS_DIR:-manifests/argocd}"

# =========================
# Pre-flight
# =========================
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

ensure_docker_ready() {
  need docker
  if ! systemctl is-active --quiet docker; then
    log "Starting Docker service..."
    sudo systemctl enable --now docker
  fi
  if ! id -nG "$USER" | grep -qw docker; then
    die "Current user is not in the 'docker' group. Run: sudo usermod -aG docker $USER && re-login (or run 'newgrp docker')."
  fi
  docker ps >/dev/null 2>&1 || die "Cannot connect to Docker daemon. Check /var/run/docker.sock permissions."
}

ensure_k3d_cluster_with_ports() {
  need k3d
  if k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "${CLUSTER_NAME}"; then
    warn "Detected existing k3d cluster: ${CLUSTER_NAME}"
    local lb_name="k3d-${CLUSTER_NAME}-serverlb"
    local lb_id; lb_id=$(docker ps -q -f "name=^/${lb_name}$" || true)
    if [[ -z "${lb_id}" ]]; then
      warn "Server LB container '${lb_name}' not found; possibly old k3d or custom setup."
    else
      local ports; ports=$(docker port "${lb_id}" || true)
      echo "${ports}"
      if ! grep -q "${ARGOCD_HOST_PORT}.*->" <<<"${ports}" || ! grep -q "${APP_HOST_PORT}.*->" <<<"${ports}"; then
        warn "Existing cluster lacks required host port mappings:"
        warn "  Need host ${ARGOCD_HOST_PORT} → LB:8443 and host ${APP_HOST_PORT} → LB:8888"
        warn "Consider recreating the cluster:"
        warn "  k3d cluster delete ${CLUSTER_NAME} && \\"
        warn "  k3d cluster create ${CLUSTER_NAME} --wait \\"
        warn "    --port \"${ARGOCD_HOST_PORT}:8443@loadbalancer\" \\"
        warn "    --port \"${APP_HOST_PORT}:8888@loadbalancer\""
      else
        ok "Existing cluster has required host port mappings."
      fi
    fi
    return
  fi

  log "Creating k3d cluster '${CLUSTER_NAME}' with host port mappings..."
  k3d cluster create "${CLUSTER_NAME}" --wait \
    --port "${ARGOCD_HOST_PORT}:8443@loadbalancer" \
    --port "${APP_HOST_PORT}:8888@loadbalancer"
  ok "k3d cluster created."
}

# =========================
# Waiters (ServiceLB: svclb-*)
# =========================
wait_svclb_ready() {
  local ns="$1"; local svc="$2"; local timeout="${3:-300}"
  log "Waiting for ServiceLB helper pod 'svclb-${svc}-*' in namespace '${ns}' (timeout ${timeout}s)..."
  local end=$((SECONDS+timeout))
  while (( SECONDS <= end )); do
    local lines
    lines="$(kubectl -n "${ns}" get pods --no-headers 2>/dev/null | awk '/^svclb-'"${svc}"'-/ {print $1, $2, $3}')"
    if [[ -n "${lines}" ]]; then
      local notready
      notready="$(awk '$2!="1/1" || $3!="Running" {print $0}' <<<"${lines}" || true)"
      if [[ -z "${notready}" ]]; then
        ok "ServiceLB helper for '${svc}' is Running."
        return 0
      fi
    fi
    sleep 3
  done
  die "ServiceLB helper for '${svc}' not ready within ${timeout}s"
}

# =========================
# Argo CD
# =========================
bootstrap_argocd() {
  log "Creating namespaces (argocd, dev)..."
  kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns dev     --dry-run=client -o yaml | kubectl apply -f -
  ok "Namespaces ready."

  log "Installing Argo CD (in-cluster)..."
  kubectl apply -n argocd -f "${ARGOCD_INSTALL_URL}"

  log "Waiting for argocd-server to be ready (up to 5 minutes)..."
  kubectl rollout status deploy/argocd-server -n argocd --timeout=300s || true

  # Make argocd-server Service type=LoadBalancer and add port 8443
  log "Exposing argocd-server as LoadBalancer and adding 8443 port..."
  kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"}}' >/dev/null
  kubectl -n argocd patch svc argocd-server --type merge -p '{
    "spec": {
      "type": "LoadBalancer",
      "ports": [
        {"name":"https-alt","port":8443,"targetPort":8080}
      ]
    }
  }' >/dev/null
  

  # wait svclb_ready or it will get connection refused
  wait_svclb_ready kube-system argocd-server 300

  log "Retrieving Argo CD initial admin password..."
  ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  ok "Argo CD UI: https://localhost:${ARGOCD_HOST_PORT}   (user: admin, password: ${ARGOCD_ADMIN_PASSWORD})"

  # apply Application
  log "Applying Argo CD Application (dev/playground)..."
  kubectl apply -f "${ARGOCD_MANIFESTS_DIR}/application-dev.yaml"
  ok "Application applied."

  if kubectl -n dev get deploy playground >/dev/null 2>&1; then
    log "Waiting for Deployment 'playground' Available..."
    kubectl -n dev wait --for=condition=available deploy/playground --timeout=300s || true
  else
    warn "Deployment 'playground' not found yet; will continue and rely on Argo CD sync."
  fi

  # wait svclb_ready or it will get connection refused
  wait_svclb_ready kube-system playground-svc 300

  ok "Playground app: http://localhost:${APP_HOST_PORT}"
}

# =========================
# Main
# =========================
need kubectl
ensure_docker_ready
ensure_k3d_cluster_with_ports
bootstrap_argocd
ok "All done 🎉  Open: https://localhost:${ARGOCD_HOST_PORT} and http://localhost:${APP_HOST_PORT}"

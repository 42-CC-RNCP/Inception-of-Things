#!/usr/bin/env bash
set -euo pipefail

# =========================
# Helpers
# =========================
log()  { echo -e "👉 \e[1m$*\e[0m"; }
ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*"; }
die()  { echo -e "❌ $*" >&2; exit 1; }


ARGOCD_INSTALL_URL=${ARGOCD_INSTALL_URL:-"https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"}

# =========================
# Argo CD
# =========================
bootstrap_argocd() {
  log "Creating namespaces (argocd, dev)..."
  kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns dev     --dry-run=client -o yaml | kubectl apply -f -
  ok "Namespaces created."

  log "Installing Argo CD (inside cluster)..."
  kubectl apply -n argocd -f "${ARGOCD_INSTALL_URL}"
  log "Waiting for argocd-server Ready (up to 5 minutes)..."
  kubectl rollout status deploy/argocd-server -n argocd --timeout=300s || true

  ok "Argo CD installed."

  log "Retrieving initial admin password..."
  ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  ok "Initial admin password: ${ARGOCD_ADMIN_PASSWORD}"
  log "port-forwarding argocd-server to http://localhost:8080 ..."
  kubectl port-forward -n argocd svc/argocd-server 8080:443 >/dev/null 2>&1 &
  sleep 3
  ok "Argo CD UI: https://localhost:8080 (username: admin, password: ${ARGOCD_ADMIN_PASSWORD})"

  log "Applying Argo CD Application (dev/playground)..."
  kubectl apply -f p3/manifests/argocd/application-dev.yaml
  ok "Argo CD Application(dev/playground) applied."

}

# =========================
# Main
# =========================
bootstrap_argocd
ok "Bootstrap completed."

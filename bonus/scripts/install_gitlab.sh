#!/usr/bin/env bash
# scripts/install_gitlab.sh
# Always install GitLab with low-memory values unless an explicit values file is passed
set -euo pipefail

NS="${NS:-gitlab}"
REL="${REL:-gitlab}"
DEFAULT_VALUES="${DEFAULT_VALUES:-confs/gitlab.constrained.yaml}"
VALUES_FILE="${1:-$DEFAULT_VALUES}"

log() { echo -e "👉 $*"; }
ok()  { echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
die() { echo -e "❌ $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

wait_rollout() {
  local kind="$1" name="$2" timeout="${3:-900s}"
  log "Waiting for $kind/$name to be Ready (timeout $timeout)..."
  if ! kubectl -n "$NS" rollout status "$kind/$name" --timeout="$timeout"; then
    warn "$kind/$name not Ready in time."
  else
    ok "$kind/$name Ready."
  fi
}

wait_selector_ready() {
  local selector="$1" timeout="${2:-600}" interval=5
  log "Waiting pods with selector [$selector] Ready (<= ${timeout}s)..."
  SECONDS=0
  while (( SECONDS < timeout )); do
    local total ready
    total=$(kubectl -n "$NS" get pods -l "$selector" --no-headers 2>/dev/null | wc -l || echo 0)
    ready=$(kubectl -n "$NS" get pods -l "$selector" --no-headers 2>/dev/null \
      | awk '$2 ~ /([0-9]+)\/\1/ && $3=="Running" {c++} END{print c+0}')
    if [[ "$total" -gt 0 && "$ready" -ge 1 ]]; then
      ok "[$selector] has Ready pods."
      return 0
    fi
    sleep "$interval"
  done
  warn "[$selector] not Ready in time."
  return 1
}

run_migration() {
  local cmd="$1" tries=6 sleepsec=12
  for i in $(seq 1 "$tries"); do
    log "Running migration: '$cmd' (attempt $i/$tries)"
    if kubectl -n "$NS" exec deploy/${REL}-toolbox -c toolbox -- $cmd; then
      ok "Succeeded: $cmd"
      return 0
    fi
    warn "Failed (attempt $i). Sleep ${sleepsec}s…"
    sleep "$sleepsec"
  done
  die "Migration failed repeatedly: $cmd"
}

scale_one() {
  log "Scaling webservice/sidekiq to 1 replica (best-effort)"
  kubectl -n "$NS" scale deploy/${REL}-webservice-default --replicas=1 >/dev/null 2>&1 || true
  kubectl -n "$NS" scale deploy/${REL}-sidekiq-all-in-1-v2 --replicas=1 >/dev/null 2>&1 || true
}

patch_readiness_probe() {
  log "Relaxing webservice readinessProbe.initialDelaySeconds to 120 (best-effort)"
  kubectl -n "$NS" patch deploy ${REL}-webservice-default --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":120}]' \
    >/dev/null 2>&1 || true
}

need kubectl
need helm

log "Using values: ${VALUES_FILE}"

log "Ensuring namespace"
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -

log "Adding/Updating Helm repo"
helm repo add gitlab https://charts.gitlab.io/ >/dev/null
helm repo update >/dev/null

log "Installing/Upgrading GitLab (low-memory mode)"
helm upgrade --install "$REL" gitlab/gitlab -n "$NS" \
  -f "$VALUES_FILE" \
  --set certmanager-issuer.enabled=false \
  --set gitlab.kas.enabled=false \
  --set gitlab.gitlab-exporter.enabled=false \
  --set registry.enabled=false \
  --set prometheus.install=false \
  --set grafana.enabled=false \
  --timeout 1800s

# Wait core deps, then run migrations
kubectl -n gitlab rollout status statefulset/gitlab-postgresql --timeout=900s
kubectl -n gitlab rollout status statefulset/gitlab-redis-master --timeout=900s
kubectl -n gitlab rollout status statefulset/gitlab-gitaly --timeout=900s
wait_rollout "deployment" "${REL}-toolbox" "900s" || true

run_migration "gitlab-rake db:prepare"
run_migration "gitlab-rake db:migrate"

# Stabilize
# scale_one
# patch_readiness_probe

log "Restarting webservice and sidekiq"
kubectl -n "$NS" rollout restart deploy/${REL}-webservice-default || true
kubectl -n "$NS" rollout restart deploy/${REL}-sidekiq-all-in-1-v2 || true

echo ">>> Initial root password:"
kubectl -n "$NS" get secret ${REL}-gitlab-initial-root-password \
  -o jsonpath='{.data.password}' | base64 -d; echo

ok "No-UI mode. Use port-forward when needed:"
echo "  API: kubectl -n $NS port-forward svc/${REL}-webservice-default 8081:8181"
echo "  SSH: kubectl -n $NS port-forward svc/${REL}-gitlab-shell 2222:22"

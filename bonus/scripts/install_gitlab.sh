#!/usr/bin/env bash
# scripts/install_gitlab.sh
# Always install GitLab with low-memory values unless an explicit values file is passed
set -euo pipefail

NS="${NS:-gitlab}"
REL="${REL:-gitlab}"
DEFAULT_VALUES="${DEFAULT_VALUES:-confs/gitlab.constrained.yaml}"
VALUES_FILE="${1:-$DEFAULT_VALUES}"
ENV_FILE=".gitlab.env"

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

wait_toolbox_ready() {
  log "Waiting toolbox API (gitlab-rails runner) to be available..."
  local tries=60 sleepsec=5
  for i in $(seq 1 "$tries"); do
    if kubectl -n "$NS" exec deploy/${REL}-toolbox -c toolbox -- \
         gitlab-rails runner "puts 'pong'" >/dev/null 2>&1; then
      ok "toolbox rails runner OK."
      return 0
    fi
    sleep "$sleepsec"
  done
  die "toolbox rails runner not responding"
}

ensure_http_git_enabled() {
  log "Ensuring HTTP Git + PAT auth are enabled (idempotent)..."
  kubectl -n "$NS" exec deploy/${REL}-toolbox -c toolbox -- \
    gitlab-rails runner \
"s=ApplicationSetting.current; s.update!(enabled_git_access_protocol: 'all', password_authentication_enabled_for_git: true);
puts \"enabled_git_access_protocol=#{s.enabled_git_access_protocol}, password_authentication_enabled_for_git=#{s.password_authentication_enabled_for_git}\"" \
    || warn "Failed to update ApplicationSetting (will continue)."
}

ensure_initial_root_password_secret() {
  log "Ensuring initial root password secret (${REL}-gitlab-initial-root-password) ..."
  if kubectl -n "$NS" get secret "${REL}-gitlab-initial-root-password" >/dev/null 2>&1; then
    ok "Secret exists. (skip)"
    return 0
  fi

  local PASS="${GITLAB_ROOT_PASSWORD:-${GITLAB_ROOT_PASSWORD_FILE:-}}"
  if [[ -z "$PASS" ]]; then
    PASS='ChangeMe_+VeryStrong#2025'
  fi

  kubectl -n "$NS" create secret generic "${REL}-gitlab-initial-root-password" \
    --from-literal=password="$PASS"

  printf "export GITLAB_ROOT_PASSWORD=%q\n" "$PASS" > "$ENV_FILE"
  ok "Created secret and saved GITLAB_ROOT_PASSWORD to $ENV_FILE"
}

ensure_root_user() {
  log "Ensuring 'root' user exists (will seed if missing)..."
  local tries=60 sleepsec=5 seeded_once=false
  for i in $(seq 1 "$tries"); do
    local out
    out=$(kubectl -n "$NS" exec deploy/${REL}-toolbox -c toolbox -- \
      gitlab-rails runner "u=User.find_by(username: 'root'); puts(u ? 'present' : 'missing')" 2>/dev/null || true)

    if [[ "$out" == "present" ]]; then
      ok "root user present."
      return 0
    fi
    if [[ "$seeded_once" == false ]]; then
      warn "root missing; running db:seed_fu once..."
      kubectl -n "$NS" exec deploy/${REL}-toolbox -c toolbox -- gitlab-rake db:seed_fu || true
      seeded_once=true
    fi

    sleep "$sleepsec"
  done
  die "root user was not created after waiting"
}

wait_initial_root_password_secret() {
  log "Waiting for initial root password secret..."
  local tries=120 sleepsec=2 PASS=""
  for i in $(seq 1 "$tries"); do
    PASS="$(kubectl -n "$NS" get secret ${REL}-gitlab-initial-root-password \
      -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
    if [[ -n "$PASS" ]]; then
      ok "Initial root password secret available."
      echo "root initial password: $PASS"
      export GITLAB_ROOT_PASSWORD="$PASS"
      printf "export GITLAB_ROOT_PASSWORD=%q\n" "$PASS" > "$ENV_FILE"
      return 0
    fi
    sleep "$sleepsec"
  done
  warn "Initial root password secret not found in time (continuing)."
}

need kubectl
need helm

log "Using values: ${VALUES_FILE}"

log "Ensuring namespace"
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -

ensure_initial_root_password_secret

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

wait_toolbox_ready
# ensure_http_git_enabled
ensure_root_user
wait_initial_root_password_secret

log "Restarting webservice and sidekiq"
kubectl -n "$NS" rollout restart deploy/${REL}-webservice-default || true
kubectl -n "$NS" rollout restart deploy/${REL}-sidekiq-all-in-1-v2 || true


log ">>> Capturing initial root password…"
PASS="$(
  kubectl -n "$NS" get secret "${REL}-gitlab-initial-root-password" \
    -o jsonpath='{.data.password}' \
  | base64 --decode | tr -d '\n'
)"
log "root initial password: $PASS"
export GITLAB_ROOT_PASSWORD="$PASS"
printf "export GITLAB_ROOT_PASSWORD=%q\n" "$PASS" > "$ENV_FILE"

ok "Saved export line to $ENV_FILE"
echo "👉 Load it into your current shell with: source $ENV_FILE"

ok "No-UI mode. Use port-forward when needed:"
echo "  API: kubectl -n $NS port-forward svc/${REL}-webservice-default 8081:8181"
echo "  SSH: kubectl -n $NS port-forward svc/${REL}-gitlab-shell 2222:22"

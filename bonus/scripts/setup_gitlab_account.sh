#!/usr/bin/env bash
# setup_gitlab_account.sh
# Create a GitLab user (no-UI) using REST API and upload a local SSH public key.
# - Uses local $USER as username by default
# - Generates an ed25519 key (~/.ssh/gitlab_k3d) if missing
# - Requires a ROOT admin PAT with at least 'api' scope (env: GITLAB_PAT / REPO_PAT / PAT)

set -euo pipefail

# ========== Config (override via env) ==========
BASE="${BASE:-http://localhost:8081}"        # Workhorse endpoint (after port-forward)
ACCOUNT_USERNAME="${ACCOUNT_USERNAME:-$USER}" # Username in GitLab (default to local $USER)
ACCOUNT_NAME="${ACCOUNT_NAME:-$(getent passwd "$ACCOUNT_USERNAME" 2>/dev/null | cut -d: -f5 | cut -d, -f1 || echo "$ACCOUNT_USERNAME")}"
ACCOUNT_EMAIL="${ACCOUNT_EMAIL:-${ACCOUNT_USERNAME}@localhost}"   # Non-routable default
PASSWORD="${PASSWORD:-$(openssl rand -base64 24 | tr -d '\n')}"           # Random initial password

PRIVKEY_PATH="${PRIVKEY_PATH:-$HOME/.ssh/gitlab_k3d}"
PUBKEY_PATH="${PUBKEY_PATH:-${PRIVKEY_PATH}.pub}"
KEY_TITLE="${KEY_TITLE:-$(hostname)-k3d}"

# Admin PAT (root). Accept several common env names for convenience.
GITLAB_PAT="${GITLAB_PAT:-${REPO_PAT:-${PAT:-}}}"

# ========== Helpers ==========
log()  { echo -e "👉 $*"; }
ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*"; }
die()  { echo -e "❌ $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

api_get() { curl -sS --fail -H "PRIVATE-TOKEN: $GITLAB_PAT" "$@"; }
api_post() { curl -sS --fail -H "PRIVATE-TOKEN: $GITLAB_PAT" -X POST "$@"; }
api_put() { curl -sS --fail -H "PRIVATE-TOKEN: $GITLAB_PAT" -X PUT "$@"; }

# ========== Pre-flight ==========
need curl
need jq
need ssh-keygen
need openssl

[[ -n "${GITLAB_PAT}" ]] || die "GITLAB_PAT (or REPO_PAT/PAT) is empty. Export a root admin token with 'api' scope."

log "Checking GitLab availability at $BASE ..."
if ! curl -sS -I "$BASE/users/sign_in" >/dev/null; then
  warn "Cannot reach $BASE. Did you run: kubectl -n gitlab port-forward svc/gitlab-webservice-default 8081:8181 ?"
fi

# ========== Ensure SSH key exists ==========
if [[ ! -f "$PRIVKEY_PATH" || ! -f "$PUBKEY_PATH" ]]; then
  log "Generating SSH key: $PRIVKEY_PATH (ed25519, empty passphrase)"
  mkdir -p "$(dirname "$PRIVKEY_PATH")"
  ssh-keygen -t ed25519 -f "$PRIVKEY_PATH" -N "" -C "$ACCOUNT_USERNAME@$(hostname)"
else
  ok "SSH key exists: $PUBKEY_PATH"
fi

# ========== Get or create user ==========
log "Checking if user '$ACCOUNT_USERNAME' exists..."
USER_JSON="$(api_get "$BASE/api/v4/users?username=$(printf %s "$ACCOUNT_USERNAME")" || true)"
USER_ID="$(jq -r '.[0].id // empty' <<<"$USER_JSON")"

if [[ -z "$USER_ID" ]]; then
  log "Creating user '$ACCOUNT_USERNAME' ..."
  CREATE_JSON="$(api_post "$BASE/api/v4/users" \
      --data-urlencode "name=${ACCOUNT_NAME}" \
      --data-urlencode "username=${ACCOUNT_USERNAME}" \
      --data-urlencode "email=${ACCOUNT_EMAIL}" \
      --data-urlencode "password=${PASSWORD}" \
      --data-urlencode "skip_confirmation=true"
    )"
  USER_ID="$(jq -r '.id' <<<"$CREATE_JSON")"
  [[ -n "$USER_ID" && "$USER_ID" != "null" ]] || die "Failed to create user. Response: $CREATE_JSON"
  ok "Created user '$ACCOUNT_USERNAME' (id=$USER_ID, email=$ACCOUNT_EMAIL)"
else
  ok "User exists '$ACCOUNT_USERNAME' (id=$USER_ID)"
fi

# ========== Upload SSH public key ==========
PUBKEY_CONTENT="$(cat "$PUBKEY_PATH")"
log "Uploading SSH key to user '$ACCOUNT_USERNAME' ..."
KEY_JSON="$(api_post "$BASE/api/v4/users/$USER_ID/keys" \
  --data-urlencode "title=${KEY_TITLE}" \
  --data-urlencode "key=${PUBKEY_CONTENT}" || true)"

# If key already exists, GitLab returns 400. Check if key list already contains it.
if jq -e '.id' <<<"$KEY_JSON" >/dev/null 2>&1; then
  ok "SSH key added: $(jq -r '.title' <<<"$KEY_JSON")"
else
  warn "Could not add SSH key (maybe it already exists). Checking existing keys..."
  KEYS_LIST="$(api_get "$BASE/api/v4/users/$USER_ID/keys")"
  if grep -qF "$(cut -d' ' -f1-2 <<<"$PUBKEY_CONTENT")" <<<"$KEYS_LIST"; then
    ok "SSH key is already present for '$ACCOUNT_USERNAME'."
  else
    die "Failed to add SSH key. Response: $KEY_JSON"
  fi
fi

# ========== Output summary ==========
echo
ok "Done!"
cat <<EOF
User:      $ACCOUNT_USERNAME (id=$USER_ID)
Email:     $ACCOUNT_EMAIL
Web UI:    $BASE (login as $ACCOUNT_USERNAME)
SSH Key:   $PUBKEY_PATH

Next steps:
  1) Port-forward SSH if needed:
       kubectl -n gitlab port-forward svc/gitlab-gitlab-shell 2222:22
  2) Test SSH (should print a welcome message, not a shell):
       ssh -i "$PRIVKEY_PATH" -p 2222 -o StrictHostKeyChecking=no git@localhost
  3) Use SSH remote in your repo, e.g.:
       git remote set-url origin "ssh://git@localhost:2222/$ACCOUNT_USERNAME/your-repo.git"
EOF

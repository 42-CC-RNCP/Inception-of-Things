# Simple GitLab lifecycle for a Helm-based install on Kubernetes
# Usage:
#   make status              # Show what's running in the GitLab namespace
#   make gitlab-up           # Install/upgrade with LOW-MEM values (default)
#   make migrate             # Run db:prepare + db:migrate in toolbox (with retries)
#   make restart             # Restart webservice + sidekiq and wait for rollout
#   make logs                # Tail webservice + sidekiq logs
#   make pf                  # Port-forward API(8181) and SSH(2222)
#   make clean               # Uninstall Helm release (keeps namespace + PVCs/data)
#   make purge               # Full wipe: uninstall + delete PVCs + delete namespace (DATA LOSS)
#   make help                # Print this help

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

# ---- Config -------------------------------------------------------------------
NS       ?= gitlab
REL      ?= gitlab
HELM     ?= helm
KUBECTL  ?= kubectl
REPO_PATH ?= $(USER)/Inception-of-Things
BASE_HOST ?= localhost:8081

# Always use the low-memory values by default
VALUES   ?= confs/gitlab.constrained.yaml
ENV_FILE := .gitlab.env

-include $(ENV_FILE)
ifneq ("$(wildcard $(ENV_FILE))","")
# Export any VAR present in .gitlab.env whether lines are "KEY=V" or "export KEY=V"
export $(shell sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' $(ENV_FILE))
endif

# ---- Full Setup ----------------------------------------------------------------

.PHONY: up
up: gitlab-up argocd-up pf
	@echo "✅ GitLab and ArgoCD are up and running!"

.PHONY: setup
setup: gitlab-pat setup-account show-urls hint-remote-http hint-remote-ssh
	@echo "✅ GitLab account and PAT setup done!"

# ---- Helpers ------------------------------------------------------------------
.PHONY: help
help:
	@grep -E '^[a-zA-Z0-9_-]+:.*?#' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?#"} {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---- Inspect ------------------------------------------------------------------
.PHONY: status
status:  ## Show Pods/Services/PVCs in the GitLab namespace
	@echo "==> Pods";      $(KUBECTL) -n $(NS) get pods -o wide || true; echo
	@echo "==> Services";  $(KUBECTL) -n $(NS) get svc || true; echo
	@echo "==> PVCs";      $(KUBECTL) -n $(NS) get pvc || true

.PHONY: logs
logs:  ## Tail logs for webservice and sidekiq
	-$(KUBECTL) -n $(NS) logs deploy/$(REL)-webservice-default -c webservice -f --tail=200 &
	-$(KUBECTL) -n $(NS) logs deploy/$(REL)-sidekiq-all-in-1-v2 -c sidekiq -f --tail=200 & \
	wait || true

.PHONY: pf
pf:  ## Port-forward API(8081) and SSH(2222)
	@echo "API  -> http://localhost:8081"
	@echo "SSH  -> ssh://git@localhost:2222"
	-$(KUBECTL) -n $(NS) port-forward svc/$(REL)-webservice-default 8081:8181 &
	-$(KUBECTL) -n $(NS) port-forward svc/$(REL)-gitlab-shell 2222:22 &

# ---- Install / Upgrade --------------------------------------------------------

.PHONY: argocd-up
argocd-up:  ## Install/Upgrade ArgoCD in the cluster
	@./scripts/bootstrap_argocd.sh

.PHONY: gitlab-up
gitlab-up:  ## Install/Upgrade GitLab using LOW-MEM values (confs/gitlab.constrained.yaml)
	@./scripts/install_gitlab.sh $(VALUES)

# ---- DB migrations & rollouts -------------------------------------------------
.PHONY: migrate
migrate:  ## Run db:prepare + db:migrate in toolbox (with retries)
	@set -euo pipefail; \
	for cmd in "gitlab-rake db:prepare" "gitlab-rake db:migrate"; do \
	  echo ">>> $$cmd"; \
	  for i in 1 2 3 4 5; do \
	    if $(KUBECTL) -n $(NS) exec deploy/$(REL)-toolbox -c toolbox -- $$cmd; then \
	      echo "OK: $$cmd"; break; \
	    else \
	      echo "Retry $$i/5 in 10s..."; sleep 10; \
	    fi; \
	  done; \
	done

.PHONY: restart
restart:  ## Restart webservice + sidekiq and wait for rollout
	-$(KUBECTL) -n $(NS) rollout restart deploy/$(REL)-webservice-default || true
	-$(KUBECTL) -n $(NS) rollout restart deploy/$(REL)-sidekiq-all-in-1-v2 || true
	-$(KUBECTL) -n $(NS) rollout status deploy/$(REL)-webservice-default --timeout=1200s || true
	-$(KUBECTL) -n $(NS) rollout status deploy/$(REL)-sidekiq-all-in-1-v2 --timeout=1200s || true

# ---- Setup GitLab ------------------------------------------------------
.PHONY: setup-account
setup-account:  ## Setup GitLab account and upload local SSH key to GitLab
	@./scripts/setup_gitlab_account.sh

.PHONY: gitlab-pat
gitlab-pat:
	@if [ -n "$${REPO_PAT:-}" ]; then \
	  echo "✅ REPO_PAT already set in environment, skipping creation."; \
	  exit 0; \
	  return 0; \
	fi
	@set -euo pipefail; \
	echo "👉 Creating PAT (scopes: read_repository, write_repository, api, admin_mode)"; \
	TOKEN="$$( \
	  $(KUBECTL) -n $(NS) exec deploy/$(REL)-toolbox -c toolbox -- \
	  gitlab-rails runner \
	  "u = User.find_by_username('root'); \
	   t = u.personal_access_tokens.create(scopes: %w[read_repository write_repository api admin_mode], \
	                                       name: 'push-token', expires_at: 365.days.from_now); \
	   puts t.token" \
	)"; \
	echo "export REPO_PAT=$$TOKEN" >> .gitlab.env; \
	echo "✅ Wrote .gitlab.env"; \
	echo "👉 Smoke test: /api/v4/user"; \
	curl -fsS -H "PRIVATE-TOKEN: $$TOKEN" http://$(BASE_HOST)/api/v4/user >/dev/null && echo "✅ Token works"

# ---- Cleanup ------------------------------------------------------------------
.PHONY: unport-forward
unport-forward:  ## Kill any port-forwarding processes
	-@pkill -f "kubectl.*port-forward" || true
	@echo "✅ Killed port-forward processes."

.PHONY: clean
clean: unport-forward uninstall wait-gone  ## Uninstall Helm release (keeps namespace + PVCs/data)
	@echo "✅ Clean done (release removed, data kept)."
	@rm -f .gitlab.env
	@ssh-keygen -f "$(HOME)/.ssh/known_hosts" -R "[localhost]:2222"
	@unset GITLAB_ROOT_PASSWORD || true
	@unset REPO_PAT || true

.PHONY: purge
purge: clean delete-pvcs delete-ns  ## Full wipe: release + PVCs + namespace (DATA LOSS)
	@echo "🧨 Purge done (everything removed)."

.PHONY: uninstall
uninstall:  ## Helm uninstall of the GitLab release
	@echo "==> Helm uninstall $(REL) in namespace $(NS)"
	-@$(HELM) uninstall $(REL) -n $(NS) || { echo "Helm release not found."; exit 0; }

.PHONY: wait-gone
wait-gone:  ## Wait for all Pods in the namespace to terminate (best-effort)
	@echo "==> Waiting for Pods to terminate (best-effort)"
	-@$(KUBECTL) -n $(NS) wait --for=delete pod --all --timeout=120s || true

.PHONY: delete-pvcs
delete-pvcs:  ## Delete all PVCs in the namespace (DATA LOSS)
	@echo "==> Deleting PVCs in namespace $(NS) (DATA LOSS)"
	-@$(KUBECTL) -n $(NS) delete pvc --all || true

.PHONY: delete-ns
delete-ns:  ## Delete the entire namespace (DATA LOSS)
	@echo "==> Deleting namespace $(NS) (DATA LOSS)"
	-@$(KUBECTL) delete ns $(NS) --ignore-not-found

.PHONY: show-urls
show-urls:
	@echo "Web/UI:     http://$(BASE_HOST)"
	@echo "HTTP Git:   http://$(BASE_HOST)/$(REPO_PATH).git"
	@echo "SSH  Git:   ssh://git@localhost:2222/$(REPO_PATH).git"

.PHONY: env
env:
	@echo "NS=$(NS)"
	@echo "REL=$(REL)"
	@echo "BASE_HOST=$(BASE_HOST)"
	@echo "REPO_PAT set? $$( [ -n "$${REPO_PAT:-}" ] && echo yes || echo no )"
	@echo "GITLAB_ROOT_PASSWORD set? $$( [ -n "$${GITLAB_ROOT_PASSWORD:-}" ] && echo yes || echo no )"

.PHONY: test-http-git
test-http-git:
	@test -n "$$REPO_PAT" || (echo "❌ Please: source $(ENV_FILE) or export REPO_PAT=..."; exit 1)
	@echo "👉 Testing HTTP API with REPO_PAT"
	@curl -sS -H "PRIVATE-TOKEN: $$REPO_PAT" http://$(BASE_HOST)/api/v4/user && \
	echo -e "\n✅ HTTP API works" || (echo -e "\n❌ HTTP API failed"; exit 1)

.PHONY: hint-remote
hint-remote-http:
	@echo "# HTTP remote (use this if you set REPO_PAT in your git credentials)"
	@echo "git config --global credential.helper store"
	@echo 'printf "protocol=http\nhost=$(BASE_HOST)\nusername=root\npassword=$$REPO_PAT\n\n" | git credential approve'
	@echo "git remote set-url gitlab http://$(BASE_HOST)/$(REPO_PATH).git"

hint-remote-ssh:
	@echo "# SSH remote (ensure your SSH key is added to GitLab)"
	@echo "git remote set-url gitlab ssh://git@localhost:2222/$(REPO_PATH).git"

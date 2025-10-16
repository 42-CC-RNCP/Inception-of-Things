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

# Always use the low-memory values by default
VALUES   ?= confs/gitlab.constrained.yaml

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
	@echo "SSH  -> ssh://[email protected]:2222"
	-$(KUBECTL) -n $(NS) port-forward svc/$(REL)-webservice-default 8081:8080 &
	-$(KUBECTL) -n $(NS) port-forward svc/$(REL)-gitlab-shell 2222:22 & \
	wait || true

# ---- Install / Upgrade --------------------------------------------------------
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

# ---- Cleanup ------------------------------------------------------------------
.PHONY: clean
clean: uninstall wait-gone  ## Uninstall Helm release (keeps namespace + PVCs/data)
	@echo "✅ Clean done (release removed, data kept)."

.PHONY: purge
purge: uninstall wait-gone delete-pvcs delete-ns  ## Full wipe: release + PVCs + namespace (DATA LOSS)
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

# ---- Last resort --------------------------------------------------------------
.PHONY: nuke-finalizers
nuke-finalizers:  ## Remove finalizers from stuck PVCs (LAST RESORT)
	@echo "==> Removing finalizers from PVCs (last resort if stuck)"
	-@for pvc in $$($(KUBECTL) -n $(NS) get pvc -o name 2>/dev/null); do \
	  $(KUBECTL) -n $(NS) patch $$pvc -p '{"metadata":{"finalizers":[]}}' --type=merge || true; \
	done

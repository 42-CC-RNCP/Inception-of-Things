VAGRANT_FILE ?= Vagrantfile.ingress

HOSTS_LINE = 192.168.56.110 app1.com app2.com app3.com

VAGRANT_CMD = VAGRANT_VAGRANTFILE=$(VAGRANT_FILE) vagrant

all:
	@echo "Starting Vagrant VM unsing $(VAGRANT_FILE)..."
	$(VAGRANT_CMD) up

setup:
	@if ! grep -qF "$(HOSTS_LINE)" /etc/hosts; then \
		echo "Adding hosts entries to /etc/hosts..."; \
		echo "$(HOSTS_LINE)" | sudo tee -a /etc/hosts; \
	else \
		echo "Hosts entries already present."; \
	fi
	@echo "Starting Vagrant VM using $(VAGRANT_FILE)..."
	$(VAGRANT_CMD) up

into:
	$(VAGRANT_CMD) ssh k3s-server

destroy:
	@echo "Destroying Vagrant VM..."
	$(VAGRANT_CMD) destroy -f

.PHONY: all setup into destroy

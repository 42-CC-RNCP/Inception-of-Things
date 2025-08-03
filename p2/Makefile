HOSTS_LINE = 192.168.56.110 app1.com app2.com app3.com

all:
	@echo "Starting Vagrant VM..."
	vagrant up

setup:
	@if ! grep -qF "$(HOSTS_LINE)" /etc/hosts; then \
		echo "Adding hosts entries to /etc/hosts..."; \
		echo "$(HOSTS_LINE)" | sudo tee -a /etc/hosts; \
	else \
		echo "Hosts entries already present."; \
	fi
	@echo "Starting Vagrant VM..."
	vagrant up

into:
	vagrant ssh k3s-server

destroy:
	@echo "Destroying Vagrant VM..."
	vagrant destroy -f

.PHONY: setup destroy into all

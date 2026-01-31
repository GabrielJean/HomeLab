.PHONY: help pve-ubuntu-base pve-1-docker-apps pve-2-docker-apps updates pve-nas pve-plex rke tailscale-routers

ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_CONFIG ?= ansible.cfg

INVENTORY ?= inventories/home/inventory.ini
VAULT ?= --ask-vault-pass

# Default: show available targets
help:
	@echo "Ansible shortcuts (run from repo root: 'cd Ansible && make <target>')"
	@echo ""
	@echo "Targets:"
	@echo "  make pve-ubuntu-base      -> playbooks/pve-ubuntu-base.yml"
	@echo "  make pve-1-docker-apps     -> playbooks/pve-1-docker-apps.yml"
	@echo "  make pve-2-docker-apps     -> playbooks/pve-2-docker-apps.yml"
	@echo "  make updates              -> playbooks/updates.yml"
	@echo "  make pve-nas              -> playbooks/pve-nas.yml"
	@echo "  make pve-plex             -> playbooks/pve-plex.yml"
	@echo "  make rke                  -> playbooks/rke.yml"
	@echo "  make tailscale-routers    -> playbooks/tailscale-routers.yml"
	@echo ""
	@echo "Common overrides:"
	@echo "  make <target> VAULT='--vault-id @prompt'"
	@echo "  make <target> EXTRA='--extra-vars ansible_user=ci'"
	@echo "  make <target> LIMIT='--limit Docker-1'"
	@echo "  make <target> CHECK='--check'"
	@echo ""

define RUN
	ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) \
	$(ANSIBLE_PLAYBOOK) playbooks/$(1).yml \
		-i $(INVENTORY) \
		$(VAULT) \
		$${LIMIT} \
		$${CHECK} \
		$${EXTRA}
endef

pve-ubuntu-base:
	$(call RUN,pve-ubuntu-base)

pve-1-docker-apps:
	$(call RUN,pve-1-docker-apps)

pve-2-docker-apps:
	$(call RUN,pve-2-docker-apps)

updates:
	$(call RUN,updates)

pve-nas:
	$(call RUN,pve-nas)

pve-plex:
	$(call RUN,pve-plex)

rke:
	$(call RUN,rke)

tailscale-routers:
	$(call RUN,tailscale-routers)

# Vault: usa --ask-vault-pass di default, override con:
#   make <target> VAULT="--vault-password-file=/git/.vault_pass"
VAULT ?= --ask-vault-pass

AP = ansible-playbook $(VAULT)

.PHONY: help deploy zones acme cert-deploy renew dnssec vault-summary ping syntax snapshot

help:
	@echo "Uso: make <target> [VAULT=\"--vault-password-file=/path\"]"
	@echo ""
	@echo "  deploy        Deploy completo (primary + secondari + ACME)"
	@echo "  zones         Aggiorna solo le zone DNS"
	@echo "  acme          Emetti/rinnova cert e distribuiscili ai CT"
	@echo "  cert-deploy   Copia i cert esistenti dal primary ai CT"
	@echo "  renew         Rinnovo manuale forzato certificati ACME"
	@echo "  dnssec        Stato DNSSEC e prossime rotazioni chiavi"
	@echo "  vault-summary Riepilogo variabili vault"
	@echo "  ping          Verifica connettività a tutti gli host"
	@echo "  syntax        Syntax check di site.yml"
	@echo "  snapshot      Snapshot Proxmox del CT primary"

deploy:
	$(AP) playbooks/site.yml

zones:
	$(AP) playbooks/update-zones.yml

acme:
	$(AP) playbooks/acme-only.yml

cert-deploy:
	$(AP) playbooks/cert-deploy.yml

renew:
	$(AP) playbooks/renew-certs.yml

dnssec:
	$(AP) playbooks/dnssec-status.yml

vault-summary:
	$(AP) playbooks/vault_summary.yml

ping:
	ansible all -m ping

syntax:
	ansible-playbook --syntax-check playbooks/site.yml

snapshot:
	$(AP) playbooks/proxmox-snapshot.yml

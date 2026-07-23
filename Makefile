# Vault: usa --ask-vault-pass di default, override con:
#   make <target> VAULT="--vault-password-file=/git/.vault_pass"
VAULT ?= --ask-vault-pass
EXTRA ?=
ZONE  ?=
ARGS  ?=

AP = ansible-playbook $(VAULT) $(EXTRA)

.PHONY: help deploy zones zones-force acme cert-deploy renew dnssec dnssec-deploy dnssec-repair fix-delegation vault-summary ping syntax snapshot show-dns

help:
	@echo "Uso: make <target> [VAULT=\"--vault-password-file=/path\"]"
	@echo ""
	@echo "  deploy        Deploy completo (primary + secondari + ACME)"
	@echo "  zones         Aggiorna solo le zone DNS"
	@echo "  zones-force   Riscrive TUTTE le zone DDNS da YAML (azzera i record dinamici!)"
	@echo "  acme          Emetti/rinnova cert e distribuiscili ai CT"
	@echo "  cert-deploy   Copia i cert esistenti dal primary ai CT"
	@echo "  renew         Rinnovo manuale forzato certificati ACME"
	@echo "  dnssec        Stato DNSSEC e prossime rotazioni chiavi"
	@echo "  dnssec-deploy  Deploy/migrazione DNSSEC (usa EXTRA=\"-e dnssec_force_regen=true\" per reset chiavi)"
	@echo "  dnssec-repair  Ripara key tag nei filename chiavi DNSSEC (bug BIND alg15)"
	@echo "  fix-delegation Aggiunge delegation dyn.ninux-nnxx.it (NS+DS) al parent zone"
	@echo "  vault-summary Riepilogo variabili vault"
	@echo "  ping          Verifica connettività a tutti gli host"
	@echo "  syntax        Syntax check di site.yml"
	@echo "  snapshot      Snapshot Proxmox del CT primary"
	@echo "  show-dns      Dump di tutti i record di una zona (ZONE=<zona> [ARGS=\"-t A\"])"

deploy:
	$(AP) playbooks/site.yml

zones:
	$(AP) playbooks/update-zones.yml

# Riscrittura forzata delle zone DDNS dallo YAML: freeze -> rewrite -> thaw.
# ATTENZIONE: azzera i record dinamici (i client dyn devono ri-registrarsi).
zones-force:
	$(AP) playbooks/update-zones.yml -e dns_force_ddns_rewrite=true

acme:
	$(AP) playbooks/acme-only.yml

cert-deploy:
	$(AP) playbooks/cert-deploy.yml

renew:
	$(AP) playbooks/renew-certs.yml

dnssec:
	$(AP) playbooks/dnssec-status.yml

dnssec-deploy:
	$(AP) playbooks/dnssec-deploy.yml

dnssec-repair:
	$(AP) playbooks/dnssec-repair-keytag.yml

fix-delegation:
	$(AP) playbooks/fix-ninux-delegation.yml

vault-summary:
	$(AP) playbooks/vault_summary.yml

ping:
	ansible all -m ping

syntax:
	ansible-playbook --syntax-check playbooks/site.yml

snapshot:
	$(AP) playbooks/proxmox-snapshot.yml

# Dump di tutti i record di una zona via AXFR (SSH sul primary + TSIG key).
# Uso: make show-dns ZONE=romaclubmatera.it [ARGS="-t A"]  |  make show-dns ARGS=-l
show-dns:
	@if [ -z "$(ZONE)" ] && [ -z "$(findstring -l,$(ARGS))" ]; then \
		echo "Uso: make show-dns ZONE=<zona> [ARGS=\"-t A\"]   (oppure ARGS=-l per elencare le zone)"; \
		exit 1; \
	fi
	@./show-dns.sh $(if $(ZONE),-d $(ZONE)) $(ARGS)

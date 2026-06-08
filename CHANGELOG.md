# Changelog

Tutte le modifiche significative a questo progetto sono documentate in questo file.
Formato: [Keep a Changelog](https://keepachangelog.com/it/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/lang/it/)

---

## [1.1.0] — 2026-06-08

### Aggiunto
- Role `proxmox_vm` — provisioning VM primary su Proxmox VE via API + cloud-init
- Playbook `proxmox.yml`, `proxmox-prepare-template.yml`, `proxmox-snapshot.yml`
- Gruppi `proxmox` e `openwrt_routers` nell'inventory
- Sezione README per uso VM OVH come secondari (firewall Edge, Anti-DDoS)
- Aggiunto requirements.txt per cache pip nella CI
- CI: fix cache pip (cache-dependency-path), molecule-plugins[docker]
- CI: immagine molecule geerlingguy/docker-debian13-ansible con systemd
- CI: check vault.yml corretto per file escluso da git
- Aggiunto vault.yml.example come template committabile (vault reale resta escluso)
- Moduli Proxmox migrati a community.proxmox (deprecati in community.general 15.0.0)
- Fix Molecule: ANSIBLE_ROLES_PATH per trovare i role dalla cartella scenario
- Fix bug lookup zone: dns_zones_dir_src punta alla root (site.yml falliva)
- molecule/default/requirements.yml per dependency Galaxy
- Fix: check versione BIND in packages reso condizionale (named non ancora installato)
- Fix: deploy chiavi TSIG/DDNS prima dei conf BIND (validate include falliva)
- Fix: filtro ljust inesistente sostituito con format in zone.db.j2 e playbook
- Fix: placeholder hex non validi (TLSA/SSHFP) in example.com.yml sostituiti con hex validi
- Fix: deploy frammenti nft prima del ruleset principale (validate include)
- Fix: set nftables con join invece di loop malformati (sintassi nft valida)
- Fix: include anti-amplification mancante + regole reali nel frammento
- Fix: include TSIG key in named.conf.local del secondary (validate isolata)
- Fix: test_sequence molecule idempotency -> idempotence (nome corretto)
- Fix: rimosso timestamp volatile da zone.db.j2 per garantire idempotenza
- Fix: verify.yml usa named.service (nome reale su Trixie) + scope corretto
- Fix: verify secondary controlla allow-transfer none (allow-update vietato in slave)

### Corretto
- Bug precedenza operatori nel calcolo serial SOA (update-zones.yml)
- Variabile riservata `action` rinominata in `snap_action` (proxmox-snapshot.yml)
- `hardening_ssh_alt_port` mancante nei defaults (usata da fail2ban)
- Template alert Prometheus avvolti in `{% raw %}` per evitare collisione Jinja2
- `ansible.cfg`: rimosso commento inline su vault_password_file
- Secret in main.yml e monitoring collegati al vault invece di placeholder
- `proxmox-prepare-template.yml`: hosts da variabile a gruppo inventory
- Aggiunti `changed_when` ai comandi qm/rndc, jinja spacing, name[template]
- Config ansible-lint e yamllint allineate al profilo production


## [1.0.0] — 2026-06-07

### Aggiunto
- Role `bind9_primary` — hidden master BIND 9.20 con zone YAML
- Role `bind9_secondary` — N secondari pubblici con AXFR TSIG
- Role `dnssec` — inline signing automatico con dnssec-policy Ed25519
- Role `acme_dns` — certificati wildcard via acme.sh DNS-01
- Role `ddns_openwrt` — configurazione DDNS per router OpenWrt
- Role `nftables` — firewall con profili primary/secondary, anti-amplification
- Role `hardening` — 11 moduli: SSH, sysctl, filesystem, auditd, fail2ban, rkhunter...
- Role `packages` — pacchetti base, utils, sicurezza
- Role `monitoring` — Prometheus + bind_exporter + node_exporter + Alertmanager + Grafana
- Playbook `update-zones.yml` — serial SOA automatico YYYYMMDDnn con diff e propagation check
- Playbook `dnssec-status.yml` — stato DNSSEC e DS records per registrar
- Molecule scenario con Debian Trixie + verify assertions
- GitHub Actions CI: lint + syntax + molecule + trivy + release automatica
- README.md completo in italiano (945 righe)

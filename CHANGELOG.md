# Changelog

Tutte le modifiche significative a questo progetto sono documentate in questo file.
Formato: [Keep a Changelog](https://keepachangelog.com/it/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/lang/it/)

---

## [Unreleased]

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


## [1.0.0] — 2024-XX-XX

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

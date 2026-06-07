# Changelog

Tutte le modifiche significative a questo progetto sono documentate in questo file.
Formato: [Keep a Changelog](https://keepachangelog.com/it/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/lang/it/)

---

## [Unreleased]

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

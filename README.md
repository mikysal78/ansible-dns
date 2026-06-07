# 🌐 ansible-dns — Infrastruttura DNS Professionale

[![CI](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml/badge.svg)](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml)
[![ansible-lint](https://img.shields.io/badge/ansible--lint-passing-brightgreen)](https://github.com/ansible/ansible-lint)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Debian Trixie](https://img.shields.io/badge/Debian-Trixie-red)](https://www.debian.org/)
[![BIND9](https://img.shields.io/badge/BIND-9.20-blue)](https://www.isc.org/bind/)

Playbook Ansible completo per deployare un'infrastruttura DNS **production-ready** con hidden primary, N secondari pubblici, DNSSEC inline signing, hardening OS, monitoring e CI/CD integrato.

---

## 📋 Indice

- [Architettura](#architettura)
- [Funzionalità](#funzionalità)
- [Prerequisiti](#prerequisiti)
- [Struttura del progetto](#struttura-del-progetto)
- [Setup iniziale](#setup-iniziale)
- [Configurazione](#configurazione)
- [Deploy](#deploy)
- [Gestione zone](#gestione-zone)
- [DNSSEC](#dnssec)
- [DDNS — Router OpenWrt](#ddns--router-openwrt)
- [Monitoring](#monitoring)
- [Hardening](#hardening)
- [Firewall nftables](#firewall-nftables)
- [Certificati ACME](#certificati-acme)
- [CI/CD](#cicd)
- [Operazioni giornaliere](#operazioni-giornaliere)
- [Troubleshooting](#troubleshooting)
- [Sicurezza](#sicurezza)

---

## Architettura

```
┌─────────────────────────────────────────────────────────────────┐
│                    RETE PRIVATA / LOCALE                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         BIND9 Primary — Hidden Master                    │  │
│  │         192.168.1.10 (non raggiungibile dall'esterno)    │  │
│  │                                                          │  │
│  │  • Autoritative per tutte le zone                        │  │
│  │  • Inline DNSSEC signing (BIND 9.20 dnssec-policy)       │  │
│  │  • Accetta DDNS da router OpenWrt (TSIG)                 │  │
│  │  • acme.sh wildcard via DNS-01                           │  │
│  │  • Prometheus + Grafana + Alertmanager                   │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │ AXFR/IXFR (TSIG hmac-sha256)
                          │ NOTIFY
           ┌──────────────┼──────────────┐
           ▼              ▼              ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │  ns1 (VPS)  │ │  ns2 (VPS)  │ │  ns3 (VPS)  │
    │ 203.0.113.10│ │ 203.0.113.20│ │ 203.0.113.30│
    │             │ │             │ │             │
    │ Risponde a  │ │ Risponde a  │ │ Risponde a  │
    │ query DNS   │ │ query DNS   │ │ query DNS   │
    │ pubbliche   │ │ pubbliche   │ │ pubbliche   │
    └─────────────┘ └─────────────┘ └─────────────┘
           ▲              ▲              ▲
           └──────────────┼──────────────┘
                          │ Query DNS (UDP/TCP 53)
                    Internet / Utenti

    ┌──────────────────────────────────────┐
    │  Router OpenWrt (DDNS)               │
    │  nsupdate → dyn.example.com (TSIG)   │
    │  router-home.dyn.example.com → WAN   │
    └──────────────────────────────────────┘
```

---

## Funzionalità

### DNS Core
- **Hidden Primary** — il server master non è mai esposto a internet
- **N secondari pubblici** — da 2 a 5+ VPS, configurazione automatizzata
- **Zone in YAML** — formato leggibile con supporto a tutti i record professionali
- **AXFR/IXFR autenticato** — trasferimenti zona con chiave TSIG `hmac-sha256`
- **Record supportati** — A, AAAA, CNAME, MX, TXT, SRV, CAA, TLSA, SSHFP, NAPTR, PTR

### DNSSEC
- **Inline signing automatico** — BIND `dnssec-policy`, zero intervento manuale
- **Ed25519** — algoritmo moderno, chiavi compatte e veloci
- **KSK** rotazione annuale automatica, **ZSK** ogni 90 giorni
- **NSEC3** con `iterations=0` (RFC 9276)
- Compatible con zone DDNS

### DDNS — Router OpenWrt
- Aggiornamento record A tramite `nsupdate` con chiave TSIG
- Rilevamento automatico CGNAT — usa IP pubblico reale se dietro NAT
- Aggiornamento ogni 5 minuti, rilevamento cambio IP immediato
- Configurazione UCI automatizzata via Ansible

### Certificati ACME
- **acme.sh** con DNS-01 challenge via `nsupdate`
- Certificati **wildcard** `*.example.com` + root `example.com`
- Rinnovo automatico via cron (30 giorni prima della scadenza)
- Let's Encrypt production e staging supportati

### Hardening OS
- SSH con cifrari moderni (chacha20, AES-GCM, curve25519)
- Sysctl kernel: anti-spoofing, TCP syncookies, ASLR, kptr_restrict
- Filesystem: `/tmp`, `/var/tmp`, `/dev/shm` montati con `noexec,nosuid,nodev`
- auditd con regole CIS per file DNS, identity, syscall critiche
- sudo con log completo, requiretty, timestamp 5 min
- rkhunter con scan notturno e aggiornamento DB settimanale
- unattended-upgrades solo per patch di sicurezza (bind9 in blacklist)

### Firewall nftables
- **Primary** — porta 53 solo per localhost e secondari
- **Secondari** — rate limiting per IP, ban automatico IP flood (set dinamico)
- **Anti-amplification** — throttle risposte UDP > 512B in OUTPUT
- **Anti-spoofing** — drop bogon in tabella raw
- **Bypass conntrack** su UDP/53 per performance
- **fail2ban** integrato con set nftables `dns_flood`

### Monitoring
- **Prometheus** con scrape di tutti i nodi (primary + secondari)
- **bind_exporter** — query rate, zone transfer, DNSSEC errors, cache hit rate, serial
- **node_exporter** — CPU, memoria, disco, rete, systemd units
- **Alertmanager** — alert email/webhook, deduplica, silencing
- **Grafana** — dashboard DNS overview + system health, provisioning automatico
- Alert preconfigurati: BIND down, zone transfer failure, query rate flood, DNSSEC key expiry, serial mismatch

### CI/CD
- **ansible-lint** con profilo `production`
- **yamllint** per tutti i file YAML
- **Molecule** con driver Docker (Debian Trixie)
- **GitHub Actions** — lint + syntax check + molecule test + security scan
- **Trivy** — scan CVE e secrets nel codice
- Release automatica su tag `vX.Y.Z`

---

## Prerequisiti

### Controller Ansible
```bash
# Python 3.10+
python3 --version

# Ansible 2.16+
pip install ansible-core>=2.16 ansible-lint yamllint

# Molecule (per i test)
pip install molecule molecule-docker

# Collections
ansible-galaxy collection install -r requirements.yml
```

### Server DNS
- **OS**: Debian Trixie (13) — testato con BIND 9.20
- **CPU**: 1 vCPU minimo (2 consigliati per il primary)
- **RAM**: 512MB minimo (1GB per primary con monitoring)
- **Disco**: 10GB minimo
- **Rete**: accesso SSH dal controller Ansible

### Router OpenWrt
- OpenWrt 23.x o superiore
- Pacchetto `bind-client` disponibile (`opkg install bind-client`)

---

## Struttura del progetto

```
ansible-dns/
├── .ansible-lint              # configurazione ansible-lint
├── .yamllint                  # configurazione yamllint
├── .gitignore
├── ansible.cfg                # configurazione Ansible
├── requirements.yml           # collections Galaxy
├── README.md
│
├── inventory/
│   └── hosts.yml              # IP server e router
│
├── group_vars/
│   └── all/
│       ├── main.yml           # configurazione globale
│       └── vault.yml          # secrets cifrati (ansible-vault)
│
├── zones/                     # zone DNS in formato YAML
│   ├── example.com.yml        # zona principale
│   ├── dyn.example.com.yml    # zona DDNS (router OpenWrt)
│   └── 203.0.113.reverse.yml  # zona reverse PTR
│
├── roles/
│   ├── packages/              # pacchetti base, utils, sicurezza
│   ├── hardening/             # hardening OS (10+ moduli)
│   │   └── tasks/
│   │       ├── main.yml
│   │       ├── user.yml       # utente ansible + chiavi SSH
│   │       ├── ssh.yml        # sshd_config hardenizzato
│   │       ├── sysctl.yml     # parametri kernel
│   │       ├── filesystem.yml # mount options
│   │       ├── services.yml   # disabilita servizi inutili
│   │       ├── sudo.yml       # sudo con log completo
│   │       ├── auditd.yml     # syscall logging
│   │       ├── banner.yml     # banner + MOTD dinamico
│   │       ├── fail2ban.yml   # SSH + DNS jail
│   │       ├── rkhunter.yml   # rootkit scan
│   │       └── unattended_upgrades.yml
│   ├── nftables/              # firewall (primary vs secondary profile)
│   ├── bind9_primary/         # BIND9 hidden master
│   ├── bind9_secondary/       # BIND9 slave pubblici
│   ├── dnssec/                # DNSSEC inline signing
│   ├── acme_dns/              # certificati wildcard
│   ├── ddns_openwrt/          # configurazione router
│   └── monitoring/            # Prometheus + Grafana + Alertmanager
│
├── playbooks/
│   ├── site.yml               # deploy completo
│   ├── update-zones.yml       # aggiorna zone con serial auto
│   ├── renew-certs.yml        # rinnovo manuale certificati
│   └── dnssec-status.yml      # stato DNSSEC e DS records
│
├── molecule/
│   └── default/               # scenario di test Docker
│       ├── molecule.yml
│       ├── prepare.yml
│       ├── converge.yml
│       └── verify.yml
│
└── .github/
    └── workflows/
        ├── ci.yml             # lint + syntax + molecule + trivy
        └── release.yml        # release automatica su tag
```

---

## Setup iniziale

### 1. Clona il repository

```bash
git clone https://github.com/mikysal78/ansible-dns.git
cd ansible-dns
```

### 2. Installa le dipendenze

```bash
pip install ansible-core>=2.16
ansible-galaxy collection install -r requirements.yml
```

### 3. Genera le chiavi TSIG

```bash
# Chiave per i trasferimenti di zona (AXFR tra primary e secondari)
tsig-keygen -a hmac-sha256 axfr-key
# Output esempio:
# key "axfr-key" {
#     algorithm hmac-sha256;
#     secret "BASE64SECRET==";
# };

# Chiave per DDNS (router OpenWrt + acme.sh)
tsig-keygen -a hmac-sha256 ddns-key
```

Copia i valori `secret` nel vault.

### 4. Configura il vault

```bash
# Edita il file vault con i tuoi secret
cat > group_vars/all/vault.yml << EOF
---
vault_tsig_secret: "IL_TUO_SECRET_AXFR_BASE64=="
vault_ddns_secret: "IL_TUO_SECRET_DDNS_BASE64=="
vault_acme_email: "admin@example.com"
vault_grafana_admin_password: "PASSWORD_SICURA"
vault_alertmanager_smtp_password: "PASSWORD_SMTP"
EOF

# Cifra il vault
ansible-vault encrypt group_vars/all/vault.yml

# Verifica
ansible-vault view group_vars/all/vault.yml
```

### 5. Configura l'inventory

Edita `inventory/hosts.yml`:

```yaml
all:
  children:
    dns_primary:
      hosts:
        ns-primary:
          ansible_host: 192.168.1.10    # IP privato hidden primary
          ansible_user: ansible

    dns_secondary:
      hosts:
        ns1:
          ansible_host: 203.0.113.10    # VPS pubblico 1
          ansible_user: ansible
        ns2:
          ansible_host: 203.0.113.20    # VPS pubblico 2
          ansible_user: ansible
```

### 6. Configura le variabili globali

Edita `group_vars/all/main.yml` con i tuoi dati:

```yaml
dns_domain_base: "tuodominio.com"
dns_admin_email: "hostmaster@tuodominio.com"
dns_primary_ip: "192.168.1.10"
dns_secondary_ips:
  - "203.0.113.10"
  - "203.0.113.20"
```

### 7. Aggiungi la tua chiave SSH

In `group_vars/all/main.yml` o `host_vars/<hostname>/main.yml`:

```yaml
hardening_ssh_authorized_keys:
  - key: "ssh-ed25519 AAAA... tuo-commento"
    user: ansible
```

### 8. Configura le zone DNS

Edita `zones/example.com.yml` con i tuoi record. Rinomina i file con il tuo dominio reale e aggiorna `dns_zones` in `main.yml`.

---

## Configurazione

### Variabili principali (`group_vars/all/main.yml`)

| Variabile | Default | Descrizione |
|---|---|---|
| `dns_domain_base` | `example.com` | Dominio principale |
| `dns_primary_ip` | `192.168.1.10` | IP privato hidden primary |
| `dns_secondary_ips` | `[203.0.113.10, ...]` | Lista IP VPS secondari |
| `dns_tsig_key_name` | `axfr-key` | Nome chiave TSIG per AXFR |
| `ddns_key_name` | `ddns-key` | Nome chiave TSIG per DDNS |
| `ddns_zone` | `dyn.example.com` | Zona per record DDNS |
| `acme_email` | — | Email per Let's Encrypt |
| `acme_server` | production | URL server ACME |

### Formato zone YAML

```yaml
zone:
  name: "example.com"
  ttl: 3600
  soa:
    primary_ns: "ns1.example.com."
    admin: "hostmaster.example.com."
  ns:
    - "ns1.example.com."
    - "ns2.example.com."
  a:
    - name: "@"
      ip: "203.0.113.10"
    - name: "www"
      ip: "203.0.113.10"
  txt:
    - name: "@"
      value: "v=spf1 mx a ~all"
    - name: "_dmarc"
      value: "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"
  caa:
    - name: "@"
      flag: 0
      tag: "issue"
      value: "letsencrypt.org"
```

Tutti i tipi di record supportati: `a`, `aaaa`, `cname`, `mx`, `txt`, `srv`, `caa`, `tlsa`, `sshfp`, `ptr` (zone reverse).

---

## Deploy

```bash
# Deploy completo (tutti i server)
ansible-playbook playbooks/site.yml --ask-vault-pass

# Solo primary
ansible-playbook playbooks/site.yml --limit dns_primary --ask-vault-pass

# Solo secondari
ansible-playbook playbooks/site.yml --limit dns_secondary --ask-vault-pass

# Solo hardening (senza toccare BIND)
ansible-playbook playbooks/site.yml --tags hardening --ask-vault-pass

# Dry run (check mode)
ansible-playbook playbooks/site.yml --check --diff --ask-vault-pass
```

### Ordine di esecuzione roles

```
packages → hardening → nftables → bind9_primary → dnssec → acme_dns
                                → bind9_secondary (sui secondari)
```

---

## Gestione zone

### Aggiornamento zone con serial automatico

Il playbook calcola automaticamente il serial nel formato `YYYYMMDDnn`:
- Se il serial inizia con la data odierna → incrementa `nn`
- Se è un giorno passato → `YYYYMMDD01`
- Aggiorna **solo le zone cambiate** (calcola il diff prima del deploy)
- Verifica la sintassi con `named-checkzone` prima del reload
- Verifica la propagazione sui secondari dopo il reload

```bash
# Aggiorna tutte le zone
ansible-playbook playbooks/update-zones.yml --ask-vault-pass

# Aggiorna solo una zona specifica
ansible-playbook playbooks/update-zones.yml --ask-vault-pass \
  -e "zone_name=example.com"

# Forza reload anche senza modifiche (es. dopo rollback)
ansible-playbook playbooks/update-zones.yml --ask-vault-pass \
  -e "force_serial=true"
```

### Aggiungere una nuova zona

1. Crea il file `zones/nuova-zona.com.yml` seguendo il template esistente
2. Aggiungi la zona in `group_vars/all/main.yml`:
   ```yaml
   dns_zones:
     - name: "nuova-zona.com"
       file: "zones/nuova-zona.com.yml"
       type: master
       ddns_enabled: false
   ```
3. Esegui il deploy:
   ```bash
   ansible-playbook playbooks/update-zones.yml --ask-vault-pass
   ```

---

## DNSSEC

### Come funziona

BIND 9.20 con `dnssec-policy` gestisce tutto automaticamente:

```
[zona raw — file YAML → db.example.com]
           ↓ BIND firma inline
[zona signed — in memoria/journal]
           ↓ AXFR
[secondari servono record DNSSEC firmati]
```

### Configurazione (`roles/dnssec/defaults/main.yml`)

| Parametro | Valore | Descrizione |
|---|---|---|
| Algoritmo | Ed25519 | Moderno, chiavi compatte |
| KSK lifetime | 1 anno | Rotazione automatica |
| ZSK lifetime | 90 giorni | Rotazione automatica |
| NSEC3 iterations | 0 | RFC 9276 |
| Signature validity | 14 giorni | Rinnovo 3 giorni prima |

### Pubblicazione DS record

Dopo il primo deploy, recupera i DS record da pubblicare presso il registrar:

```bash
ansible-playbook playbooks/dnssec-status.yml --ask-vault-pass
```

L'output mostra i DS record pronti da copiare nel pannello del registrar.

### Verifica chain of trust

```bash
# Verifica firma locale
dig +dnssec example.com SOA @ns1.example.com

# Verifica chain of trust end-to-end
delv @8.8.8.8 example.com SOA +rtrace

# Stato chiavi sul primary
ansible dns_primary -m command -a "rndc dnssec -status example.com" --ask-vault-pass
```

---

## DDNS — Router OpenWrt

### Come funziona

Ogni router aggiorna periodicamente il proprio record A in `dyn.example.com` tramite `nsupdate` con autenticazione TSIG:

```
router-home.dyn.example.com.   60  IN  A  <IP WAN pubblico>
```

### Configurazione router

In `inventory/hosts.yml` aggiungi i router nella sezione `openwrt_routers`:

```yaml
openwrt_routers:
  hosts:
    router-home:
      ansible_host: 192.168.1.1
      ansible_user: root
      ddns_hostname: "router-home.dyn.example.com"
      ddns_interface: "wan"
    router-office:
      ansible_host: 192.168.100.1
      ansible_user: root
      ddns_hostname: "router-office.dyn.example.com"
      ddns_interface: "eth0.2"
```

Deploy:

```bash
ansible-playbook playbooks/site.yml --limit openwrt_routers --ask-vault-pass
```

### CGNAT

Lo script rileva automaticamente se il router è dietro CGNAT (range `100.64.0.0/10`, `192.168.x.x`, `10.x.x.x`) e in quel caso ottiene l'IP pubblico reale tramite `api4.my-ip.io`.

---

## Monitoring

### Accesso

I servizi di monitoring girano sul primary e ascoltano solo su `127.0.0.1`. Accedi tramite SSH tunnel:

```bash
# Apri tutti i tunnel in un comando
ssh -L 9090:127.0.0.1:9090 \
    -L 3000:127.0.0.1:3000 \
    -L 9093:127.0.0.1:9093 \
    ansible@192.168.1.10

# Poi apri nel browser:
# http://localhost:3000  → Grafana (admin / password configurata)
# http://localhost:9090  → Prometheus
# http://localhost:9093  → Alertmanager
```

### Alert configurati

| Alert | Severità | Condizione |
|---|---|---|
| `BINDDown` | critical | bind_exporter non risponde per 2+ min |
| `BINDZoneTransferFailed` | warning | trasferimento zona fallito |
| `BINDQueryRateHigh` | warning | > 5.000 query/s |
| `BINDQueryRateCritical` | critical | > 20.000 query/s (DDoS) |
| `BINDDNSSECValidationFailed` | warning | > 5 errori DNSSEC in 10 min |
| `BINDSerialMismatch` | warning | serial non allineato tra primary e secondari |
| `DNSSECKeyExpiringSoon` | warning | chiave DNSSEC scade in < 7 giorni |
| `DNSSECKeyExpiredCritical` | critical | chiave DNSSEC scade in < 24h |
| `NodeDown` | critical | server non raggiungibile |
| `DiskSpaceLow` | warning | < 15% spazio libero |
| `DiskSpaceCritical` | critical | < 5% spazio libero |
| `NTPOffsetHigh` | warning | offset > 100ms (critico per DNSSEC) |

### Configurare notifiche email

In `group_vars/all/main.yml`:

```yaml
alertmanager_smtp_enabled: true
alertmanager_smtp_host: "smtp.gmail.com:587"
alertmanager_smtp_from: "alerts@tuodominio.com"
alertmanager_smtp_to: "admin@tuodominio.com"
alertmanager_smtp_username: "alerts@tuodominio.com"
```

In `group_vars/all/vault.yml`:

```yaml
vault_alertmanager_smtp_password: "tua_app_password"
```

---

## Hardening

### Moduli attivi

| Modulo | Descrizione |
|---|---|
| `user` | Crea utente `ansible`, carica chiavi SSH pubbliche, blocca login root |
| `ssh` | chacha20/AES-GCM, curve25519, Ed25519 host key, no password auth |
| `sysctl` | 25+ parametri: TCP syncookies, ASLR, kptr_restrict, anti-spoofing |
| `filesystem` | `/tmp` `noexec,nosuid,nodev`, no core dump, permessi file sensibili |
| `services` | Disabilita avahi, cups, rpcbind, NFS, telnet e altri 10+ demoni |
| `sudo` | Log completo, `use_pty`, `requiretty`, timeout 5 min |
| `auditd` | Regole CIS: identity, network, PAM, zone DNS, chmod/chown, kernel modules |
| `banner` | Banner pre-login + MOTD dinamico con stato BIND/nftables/aggiornamenti |
| `fail2ban` | SSH jail + DNS flood jail con integrazione nftables |
| `rkhunter` | Scan notturno, aggiornamento DB settimanale, whitelist BIND |
| `unattended_upgrades` | Solo patch sicurezza, bind9 in blacklist, mai reboot automatico |

### Personalizzazione SSH

```yaml
# group_vars/all/main.yml
hardening_ssh_port: 2222                    # porta alternativa
hardening_ssh_allowed_sources:              # whitelist IP per SSH
  - "10.0.0.0/8"
  - "1.2.3.4"
hardening_ssh_authorized_keys:             # chiavi pubbliche
  - key: "ssh-ed25519 AAAA... admin"
    user: ansible
```

---

## Firewall nftables

### Primary (hidden master)

```
INPUT:
  lo        → ACCEPT
  established/related → ACCEPT
  ICMP      → ACCEPT (rate limited 5/s)
  SSH/22    → ACCEPT (rate limited, opz. whitelist)
  UDP/53    → ACCEPT solo da localhost + secondari
  TCP/53    → ACCEPT solo da secondari (AXFR) + localhost
  *         → DROP (con log rate limited)

OUTPUT:
  UDP sport 53 > 512B → throttle anti-amplification
```

### Secondari (VPS pubblici)

```
INPUT:
  UDP/53    → rate limit 30 pps/IP, ban 120s se superato
  TCP/53    → rate limit 10/s + AXFR illimitato dal primary
  SSH/22    → rate limited

OUTPUT:
  UDP sport 53 > 512B per IP → throttle 30s (anti-amplification)
```

### Verifica set dinamici

```bash
# IP attualmente bannati per DNS flood
nft list set inet filter dns_flood

# Destinazioni throttled per anti-amplification
nft list set inet filter amp_targets

# Ruleset completo
nft list ruleset
```

---

## Certificati ACME

### Certificati emessi

Per ogni dominio in `acme_domains` (defaults role `acme_dns`):
- `example.com` (root)
- `*.example.com` (wildcard)

### Rinnovo manuale

```bash
ansible-playbook playbooks/renew-certs.yml --ask-vault-pass
```

### Aggiungere un dominio

In `roles/acme_dns/defaults/main.yml`:

```yaml
acme_domains:
  - domain: "example.com"
    keylength: "ec-256"
  - domain: "altro-dominio.com"    # aggiungi qui
    keylength: "ec-256"
```

---

## CI/CD

### Pipeline GitHub Actions

Ogni push su `main` o `develop` esegue:

```
lint
  ├── yamllint (tutti i file YAML)
  └── ansible-lint (profilo production)
       ↓
syntax
  └── syntax-check tutti i playbook
       ↓
molecule
  └── test completo con Docker (Debian Trixie)
       ├── prepare   → installa systemd nel container
       ├── converge  → applica i roles
       ├── idempotency → verifica idempotenza
       └── verify    → assertions su stato sistema
validate-zones
  └── valida sintassi YAML zone files
security
  └── trivy scan (CVE + secrets)
```

### Eseguire i test in locale

```bash
# Lint
yamllint .
ansible-lint

# Syntax check
ansible-playbook playbooks/site.yml --syntax-check \
  -i inventory/hosts.yml \
  -e @group_vars/all/main.yml \
  -e "vault_tsig_secret=test vault_ddns_secret=test"

# Molecule
molecule test

# Solo converge (più veloce durante sviluppo)
molecule converge
molecule verify
```

### Release

Crea un tag per generare la release:

```bash
git tag -a v1.0.0 -m "Prima release stabile"
git push origin v1.0.0
```

GitHub Actions crea automaticamente la release con changelog e archivio.

---

## Operazioni giornaliere

### Comandi utili

```bash
# Stato BIND su tutti i nodi
ansible all -m command -a "systemctl status bind9" --ask-vault-pass

# Verifica serial zone
ansible dns_primary -m command \
  -a "rndc zonestatus example.com" --ask-vault-pass

# Forza zone transfer sui secondari
ansible dns_secondary -m command \
  -a "rndc retransfer example.com" --ask-vault-pass

# Log BIND in tempo reale
ansible dns_primary -m command \
  -a "journalctl -u bind9 -f --no-pager" --ask-vault-pass

# IP attualmente bannati
ansible dns_secondary -m command \
  -a "nft list set inet filter dns_flood" --ask-vault-pass

# Stato fail2ban
ansible all -m command \
  -a "fail2ban-client status" --ask-vault-pass

# Stato DNSSEC completo
ansible-playbook playbooks/dnssec-status.yml --ask-vault-pass
```

### Aggiornare BIND9

```bash
# 1. Testa prima su un secondario
ansible ns1 -m apt -a "name=bind9 state=latest" --ask-vault-pass
ansible ns1 -m command -a "systemctl restart bind9" --ask-vault-pass

# 2. Verifica che tutto funzioni
dig @203.0.113.10 example.com SOA

# 3. Aggiorna il primary
ansible dns_primary -m apt -a "name=bind9 state=latest" --ask-vault-pass
ansible dns_primary -m command -a "systemctl restart bind9" --ask-vault-pass

# 4. Aggiorna i secondari rimanenti
ansible dns_secondary -m apt -a "name=bind9 state=latest" --ask-vault-pass
```

---

## Troubleshooting

### BIND9 non si avvia

```bash
# Controlla i log
journalctl -u bind9 -n 50 --no-pager

# Verifica configurazione
named-checkconf /etc/bind/named.conf

# Verifica zone files
named-checkzone example.com /var/lib/bind/zones/db.example.com
```

### Zone transfer non funziona

```bash
# Verifica connettività primario → secondario
dig @192.168.1.10 example.com AXFR

# Controlla log trasferimenti
grep "transfer" /var/log/named/named.log

# Forza trasferimento manuale dal secondario
rndc retransfer example.com
```

### DNSSEC validation errors

```bash
# Verifica stato DNSSEC
rndc dnssec -status example.com

# Rigenera firma (inline signing)
rndc sign example.com

# Verifica validità firma
dnssec-verify -z example.com /var/lib/bind/zones/db.example.com
```

### Certificati ACME non si rinnovano

```bash
# Test manuale
/opt/acme.sh/acme.sh --renew -d example.com --force

# Verifica log
cat /var/log/acme-renew.log

# Debug DNS-01 challenge
/opt/acme.sh/acme.sh --issue --dns dns_nsupdate \
  -d example.com -d "*.example.com" --debug
```

### IP bloccato per DNS flood

```bash
# Rimuovi IP dal ban
nft delete element inet filter dns_flood { 1.2.3.4 }

# Sblocca da fail2ban
fail2ban-client set named-flood unbanip 1.2.3.4
```

---

## Sicurezza

### Gestione dei secret

Tutti i secret (chiavi TSIG, password, API key) devono essere in `group_vars/all/vault.yml` **cifrato con ansible-vault**. Il file in chiaro non deve mai essere committato.

```bash
# Verifica che il vault sia cifrato prima di committare
head -1 group_vars/all/vault.yml
# Output atteso: $ANSIBLE_VAULT;1.1;AES256
```

Il `.gitignore` esclude il file vault se non cifrato, ma è responsabilità dell'operatore verificarlo.

### Rotazione chiavi TSIG

```bash
# Genera nuova chiave
tsig-keygen -a hmac-sha256 axfr-key-new

# Aggiorna vault.yml
ansible-vault edit group_vars/all/vault.yml

# Rideploy
ansible-playbook playbooks/site.yml --ask-vault-pass

# Verifica che i trasferimenti funzionino ancora
dig @192.168.1.10 example.com AXFR
```

### Reporting vulnerabilità

Per segnalare vulnerabilità di sicurezza aprire una issue con il tag `security` o contattare direttamente il maintainer. Non pubblicare dettagli di exploit nelle issue pubbliche.

---

## Licenza

MIT — vedi [LICENSE](LICENSE)

---

## Contribuire

1. Fork del repository
2. Crea un branch: `git checkout -b feature/nome-feature`
3. Esegui lint e test: `yamllint . && ansible-lint && molecule test`
4. Commit: `git commit -m "feat: descrizione"`
5. Pull request su `main`

I contributi devono passare l'intera pipeline CI prima del merge.

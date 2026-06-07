# 🌐 ansible-dns — Infrastruttura DNS Professionale

[![CI](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml/badge.svg)](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml)
[![ansible-lint](https://img.shields.io/badge/ansible--lint-passing-brightgreen)](https://github.com/ansible/ansible-lint)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Debian Trixie](https://img.shields.io/badge/Debian-Trixie-red)](https://www.debian.org/)
[![BIND9](https://img.shields.io/badge/BIND-9.20-blue)](https://www.isc.org/bind/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange)](https://www.proxmox.com/)

Playbook Ansible completo per deployare un'infrastruttura DNS **production-ready** con hidden primary su Proxmox VE, N secondari pubblici su VPS, DNSSEC inline signing, hardening OS, firewall nftables, certificati ACME wildcard, DDNS per router OpenWrt e monitoring con Prometheus/Grafana.

---

## 📋 Indice

- [Architettura](#architettura)
- [Funzionalità](#funzionalità)
- [Prerequisiti](#prerequisiti)
- [Struttura del progetto](#struttura-del-progetto)
- [Proxmox — Provisioning VM](#proxmox--provisioning-vm)
- [Setup iniziale](#setup-iniziale)
- [Configurazione](#configurazione)
- [Deploy DNS](#deploy-dns)
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
┌─────────────────────────────────────────────────────────────────────┐
│                    PROXMOX VE (rete locale)                         │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  VM dns-primary (VMID 200) — Debian Trixie                 │    │
│  │  192.168.1.10 — 2 vCPU host — 2GB RAM — 40GB VirtIO       │    │
│  │                                                            │    │
│  │  • BIND9 Hidden Master (non esposto a internet)            │    │
│  │  • DNSSEC inline signing (Ed25519, dnssec-policy)          │    │
│  │  • acme.sh wildcard via DNS-01                             │    │
│  │  • Prometheus + Grafana + Alertmanager                     │    │
│  │  • fail2ban + nftables + auditd + rkhunter                 │    │
│  └──────────────────────┬─────────────────────────────────────┘    │
└─────────────────────────┼───────────────────────────────────────────┘
                          │ AXFR/IXFR (TSIG hmac-sha256) + NOTIFY
           ┌──────────────┼──────────────┬─────────────┐
           ▼              ▼              ▼             ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐  fino a 5
    │ ns1 (VPS)  │ │ ns2 (VPS)  │ │ ns3 (VPS)  │  secondari
    │Debian Trixie│ │Debian Trixie│ │Debian Trixie│
    │            │ │            │ │            │
    │ Query DNS  │ │ Query DNS  │ │ Query DNS  │
    │ pubbliche  │ │ pubbliche  │ │ pubbliche  │
    └────────────┘ └────────────┘ └────────────┘
           ▲              ▲              ▲
           └──────────────┼──────────────┘
                    UDP/TCP 53 pubblico
                    (rate limiting + anti-amplification)

    ┌─────────────────────────────────────────┐
    │  Router OpenWrt (DDNS)                  │
    │  nsupdate TSIG → dyn.example.com        │
    │  router-home.dyn.example.com → WAN IP   │
    └─────────────────────────────────────────┘
```

---

## Funzionalità

### Proxmox VE
- Provisioning VM primary via **API Proxmox** (`community.general.proxmox_kvm`)
- Creazione automatica **template Debian Trixie** genericcloud con `virt-customize`
- Clone template → VM con **cloud-init** (IP statico, utente, chiave SSH, pacchetti)
- Hardware ottimizzato: `q35`, `UEFI`, `CPU host` (AES-NI + rdrand), VirtIO, balloon disabilitato
- **Snapshot automatico** post-creazione come baseline pre-deploy
- Playbook dedicati per gestione snapshot (crea, lista, rollback, elimina)

### DNS Core
- **Hidden Primary** — il master non è mai esposto a internet
- **N secondari pubblici** — da 2 a 5+ VPS, configurazione automatizzata
- **Zone in YAML** — formato leggibile con supporto a tutti i record professionali
- **AXFR/IXFR autenticato** — chiave TSIG `hmac-sha256`
- **Record supportati** — A, AAAA, CNAME, MX, TXT, SRV, CAA, TLSA, SSHFP, PTR

### DNSSEC
- **Inline signing automatico** — `dnssec-policy` BIND 9.20, zero intervento manuale
- **Ed25519** — algoritmo moderno, chiavi compatte e veloci
- **KSK** rotazione annuale, **ZSK** ogni 90 giorni — entrambe automatiche
- **NSEC3** con `iterations=0` (RFC 9276)
- Compatibile con zone DDNS

### DDNS — Router OpenWrt
- Aggiornamento record A tramite `nsupdate` con TSIG
- Rilevamento automatico CGNAT
- Configurazione UCI automatizzata via Ansible

### Certificati ACME
- **acme.sh** con DNS-01 challenge via `nsupdate`
- Certificati **wildcard** `*.example.com` + root
- Rinnovo automatico via cron

### Hardening OS
- SSH con cifrari moderni (chacha20, AES-GCM, curve25519)
- Sysctl kernel: anti-spoofing, TCP syncookies, ASLR, kptr_restrict
- Filesystem: `/tmp`, `/var/tmp`, `/dev/shm` con `noexec,nosuid,nodev`
- auditd con regole CIS (identity, network, file DNS, syscall critiche)
- sudo con log completo, requiretty, timeout 5 min
- rkhunter scan notturno + unattended-upgrades solo sicurezza
- MOTD dinamico con stato BIND, nftables e IP bannati

### Firewall nftables
- Primary: porta 53 solo da localhost e secondari
- Secondari: rate limiting per IP, ban automatico set dinamico `dns_flood`
- Anti-amplification: throttle risposte UDP > 512B in OUTPUT
- Anti-spoofing bogon su tabella raw, bypass conntrack UDP/53
- fail2ban integrato con nftables

### Monitoring
- Prometheus + bind_exporter + node_exporter su tutti i nodi
- Grafana dashboard DNS overview + system health
- Alertmanager con 14 alert preconfigurati (email/webhook)
- Alert: BIND down, zone transfer failure, DDoS detection, DNSSEC key expiry

### CI/CD
- ansible-lint profilo `production` + yamllint
- Molecule con driver Docker (Debian Trixie) + verify assertions
- GitHub Actions: lint + syntax + molecule + trivy + release automatica

---

## Prerequisiti

### Controller Ansible
```bash
python3 --version   # 3.10+

pip install \
  ansible-core>=2.16 \
  ansible-lint \
  yamllint \
  molecule \
  molecule-docker

ansible-galaxy collection install -r requirements.yml
```

### Proxmox VE
- Versione 7.x o 8.x
- Utente API con token (vedi [Configurazione token API](#configurazione-token-api-proxmox))
- Storage con supporto snippet cloud-init abilitato
- Accesso SSH al nodo Proxmox per la creazione del template
- Connettività di rete tra VM primary e VPS secondari (porta 53 TCP)

### Server DNS
- **OS**: Debian Trixie (13)
- **Primary**: 2 vCPU, 2GB RAM, 40GB disco (VM Proxmox)
- **Secondari**: 1 vCPU, 512MB RAM, 10GB (VPS pubblici)

### Router OpenWrt
- OpenWrt 23.x o superiore
- `opkg install bind-client`

---

## Struttura del progetto

```
ansible-dns/
├── .ansible-lint
├── .yamllint
├── .gitignore
├── ansible.cfg
├── requirements.yml           # community.general, ansible.posix
├── README.md
├── LICENSE
├── CHANGELOG.md
│
├── inventory/
│   └── hosts.yml
│
├── group_vars/
│   └── all/
│       ├── main.yml           # configurazione globale
│       └── vault.yml          # secrets cifrati (ansible-vault)
│
├── zones/
│   ├── example.com.yml
│   ├── dyn.example.com.yml
│   └── 203.0.113.reverse.yml
│
├── roles/
│   ├── proxmox_vm/            # ← NUOVO: provisioning VM su Proxmox
│   │   ├── defaults/main.yml
│   │   ├── tasks/
│   │   │   ├── main.yml
│   │   │   ├── cloudinit_snippet.yml
│   │   │   ├── clone_vm.yml
│   │   │   ├── configure_vm.yml
│   │   │   ├── start_and_wait.yml
│   │   │   └── snapshot.yml
│   │   └── templates/
│   │       ├── cloudinit-user-data.yml.j2
│   │       └── cloudinit-network-config.yml.j2
│   ├── packages/
│   ├── hardening/
│   │   └── tasks/
│   │       ├── main.yml
│   │       ├── user.yml
│   │       ├── ssh.yml
│   │       ├── sysctl.yml
│   │       ├── filesystem.yml
│   │       ├── services.yml
│   │       ├── sudo.yml
│   │       ├── auditd.yml
│   │       ├── banner.yml
│   │       ├── fail2ban.yml
│   │       ├── rkhunter.yml
│   │       └── unattended_upgrades.yml
│   ├── nftables/
│   ├── bind9_primary/
│   ├── bind9_secondary/
│   ├── dnssec/
│   ├── acme_dns/
│   ├── ddns_openwrt/
│   └── monitoring/
│
├── playbooks/
│   ├── proxmox.yml                    # ← NUOVO: provisioning VM primary
│   ├── proxmox-prepare-template.yml   # ← NUOVO: crea template Debian Trixie
│   ├── proxmox-snapshot.yml           # ← NUOVO: gestione snapshot
│   ├── site.yml                       # deploy DNS completo
│   ├── update-zones.yml               # aggiorna zone con serial auto
│   ├── renew-certs.yml
│   └── dnssec-status.yml
│
├── molecule/
│   └── default/
│
└── .github/
    └── workflows/
        ├── ci.yml
        └── release.yml
```

---

## Proxmox — Provisioning VM

### Configurazione token API Proxmox

1. Accedi all'interfaccia web Proxmox (`https://proxmox.lan:8006`)
2. Vai in **Datacenter → Permissions → API Tokens → Add**
3. Configura:
   ```
   User:       ansible@pam
   Token ID:   ansible
   Privilege Separation: NO  ← importante
   ```
4. Copia il **Token Secret** mostrato (visibile solo una volta)
5. Aggiungi i permessi necessari:
   ```
   Datacenter → Permissions → Add → API Token Permission
   Path:       /
   Token:      ansible@pam!ansible
   Role:       PVEVMAdmin
   Propagate:  ✓
   ```

6. Salva il secret nel vault:
   ```bash
   ansible-vault edit group_vars/all/vault.yml
   # Aggiorna: vault_proxmox_token_secret: "il-tuo-token-secret"
   ```

### Abilitare lo storage snippets

Lo storage `local` su Proxmox deve avere i **Content: Snippets** abilitati:

1. **Datacenter → Storage → local → Edit**
2. **Content**: aggiungi `Snippets`
3. Salva

### Requisiti VM Proxmox consigliati

| Risorsa | Minimo | Consigliato | Note |
|---|---|---|---|
| CPU | 1 vCPU | **2 vCPU** | `host` passthrough per AES-NI |
| RAM | 1 GB | **2 GB** | Grafana (~300MB) + Prometheus (~200MB) |
| Disco | 20 GB | **40 GB** | 15GB `/` + 20GB `/var` (Prometheus) |
| Rete | 1 NIC | 1 NIC LAN | Bridge `vmbr0`, IP statico |
| Macchina | q35 | q35 | UEFI + TPM opzionale |
| BIOS | OVMF | OVMF | UEFI |

> **Nota disco**: il role hardening configura automaticamente `/tmp`, `/var/tmp` e `/dev/shm` come `tmpfs noexec`. Per separare `/var` (consigliato per Prometheus), aggiungi un secondo disco nella VM e configura il mount prima del deploy.

### Step 1 — Crea il template Debian Trixie

Il playbook si connette **via SSH al nodo Proxmox**, scarica l'immagine cloud Debian Trixie, installa `qemu-guest-agent` e la converte in template:

```bash
# Prima aggiungi il nodo Proxmox all'inventory
# inventory/hosts.yml:
#   all:
#     hosts:
#       proxmox.lan:
#         ansible_user: root

ansible-playbook playbooks/proxmox-prepare-template.yml --ask-vault-pass
```

Il playbook è **idempotente**: se il template VMID 9000 esiste già, non fa nulla.

**Cosa viene creato:**
- Template VMID `9000`, nome `debian-trixie-cloudinit`
- Immagine ottimizzata con `virt-customize`: qemu-guest-agent, cloud-init, python3
- Machine type q35, CPU host, VirtIO, drive cloud-init

### Step 2 — Provisioning VM primary

```bash
ansible-playbook playbooks/proxmox.yml --ask-vault-pass
```

**Flusso completo:**

```
1. Verifica esistenza template (VMID 9000)
2. Genera snippet cloud-init (user-data + network-config)
3. Carica snippet su Proxmox storage
4. Clona template → VM (VMID 200, clone completo)
5. Configura hardware:
   - CPU: host passthrough, 2 core
   - RAM: 2048MB, balloon disabilitato
   - Disco: ridimensiona a 40GB
   - Rete: VirtIO su vmbr0
   - Tags: dns, primary, ansible-managed
6. Configura cloud-init:
   - IP statico, gateway, DNS
   - Utente ansible con chiave SSH
   - Snippet custom con pacchetti
7. Avvia VM e attende SSH (120s timeout)
8. Attende completamento cloud-init
9. Verifica qemu-guest-agent via API
10. Crea snapshot baseline "post-cloudinit-base"
11. Stampa checklist VPS secondari
```

### Step 3 — Gestione snapshot

```bash
# Lista tutti gli snapshot
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=list"

# Crea snapshot manuale (prima del deploy DNS)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-deploy-dns"

# Rollback (con conferma interattiva)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=rollback snap_name=pre-deploy-dns"

# Elimina snapshot
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=delete snap_name=pre-deploy-dns"
```

### Configurazione Proxmox (`group_vars/all/main.yml`)

```yaml
# --- Connessione API ---
proxmox_host: "proxmox.lan"         # IP o hostname Proxmox
proxmox_user: "ansible@pam"
proxmox_token_id: "ansible"
proxmox_node: "pve"                 # nome nodo (pvesh nodes)

# --- Template ---
proxmox_template_vmid: 9000
proxmox_storage: "local-lvm"
proxmox_iso_storage: "local"        # deve avere Content: Snippets
proxmox_bridge: "vmbr0"

# --- VM Primary ---
proxmox_primary_vmid: 200
proxmox_primary_name: "dns-primary"
proxmox_primary_cores: 2
proxmox_primary_memory: 2048
proxmox_primary_disk_size: "40G"
proxmox_primary_ip: "192.168.1.10"
proxmox_primary_gw: "192.168.1.1"
proxmox_primary_netmask: "24"

# --- Cloud-init ---
cloudinit_user: "ansible"
cloudinit_timezone: "Europe/Rome"
cloudinit_ssh_authorized_keys:
  - "ssh-ed25519 AAAA... tua-chiave-pubblica"
```

---

## Setup iniziale

### 1. Clona il repository

```bash
git clone https://github.com/mikysal78/ansible-dns.git
cd ansible-dns
pip install ansible-core>=2.16
ansible-galaxy collection install -r requirements.yml
```

### 2. Genera le chiavi TSIG

```bash
# Chiave per trasferimenti zona (AXFR)
tsig-keygen -a hmac-sha256 axfr-key

# Chiave per DDNS (router OpenWrt + acme.sh)
tsig-keygen -a hmac-sha256 ddns-key
```

### 3. Configura il vault

```bash
cat > group_vars/all/vault.yml << EOF
---
vault_tsig_secret: "SECRET_AXFR_BASE64=="
vault_ddns_secret: "SECRET_DDNS_BASE64=="
vault_acme_email: "admin@example.com"
vault_grafana_admin_password: "PASSWORD_SICURA"
vault_alertmanager_smtp_password: "PASSWORD_SMTP"
vault_proxmox_token_secret: "TOKEN_SECRET_PROXMOX"
EOF

ansible-vault encrypt group_vars/all/vault.yml
```

### 4. Configura l'inventory

```yaml
# inventory/hosts.yml
all:
  children:
    dns_primary:
      hosts:
        ns-primary:
          ansible_host: 192.168.1.10
          ansible_user: ansible

    dns_secondary:
      hosts:
        ns1:
          ansible_host: 203.0.113.10
          ansible_user: ansible
        ns2:
          ansible_host: 203.0.113.20
          ansible_user: ansible

    openwrt_routers:
      hosts:
        router-home:
          ansible_host: 192.168.1.1
          ansible_user: root
          ddns_hostname: "router-home.dyn.example.com"
```

### 5. Aggiungi la chiave SSH pubblica

```yaml
# group_vars/all/main.yml
cloudinit_ssh_authorized_keys:
  - "ssh-ed25519 AAAA... tua-chiave"

hardening_ssh_authorized_keys:
  - key: "ssh-ed25519 AAAA... tua-chiave"
    user: ansible
```

---

## Configurazione

### Variabili principali (`group_vars/all/main.yml`)

| Variabile | Default | Descrizione |
|---|---|---|
| `dns_domain_base` | `example.com` | Dominio principale |
| `dns_primary_ip` | `192.168.1.10` | IP privato hidden primary |
| `dns_secondary_ips` | lista | IP VPS secondari pubblici |
| `dns_tsig_key_name` | `axfr-key` | Nome chiave TSIG AXFR |
| `ddns_zone` | `dyn.example.com` | Zona record DDNS |
| `proxmox_host` | `proxmox.lan` | Host Proxmox |
| `proxmox_primary_vmid` | `200` | VMID VM primary |
| `proxmox_primary_ip` | `192.168.1.10` | IP statico VM |
| `prometheus_retention` | `30d` | Retention dati Prometheus |
| `alertmanager_smtp_enabled` | `false` | Abilita notifiche email |

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
    - { name: "@",   ip: "203.0.113.10" }
    - { name: "www", ip: "203.0.113.10" }
    - { name: "mail", ip: "203.0.113.10" }
  mx:
    - { priority: 10, host: "mail.example.com." }
  txt:
    - { name: "@",     value: "v=spf1 mx a ~all" }
    - { name: "_dmarc", value: "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com" }
  caa:
    - { name: "@", flag: 0, tag: "issue",     value: "letsencrypt.org" }
    - { name: "@", flag: 0, tag: "issuewild",  value: "letsencrypt.org" }
```

---

## Deploy DNS

### Flusso completo consigliato

```bash
# 1. Crea template Debian Trixie su Proxmox (una volta sola)
ansible-playbook playbooks/proxmox-prepare-template.yml --ask-vault-pass

# 2. Provisioning VM primary
ansible-playbook playbooks/proxmox.yml --ask-vault-pass

# 3. Snapshot pre-deploy (sicurezza)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-deploy-dns"

# 4. Deploy infrastruttura DNS completa
ansible-playbook playbooks/site.yml --ask-vault-pass

# 5. Verifica e pubblica DS record DNSSEC presso il registrar
ansible-playbook playbooks/dnssec-status.yml --ask-vault-pass
```

### Opzioni deploy parziale

```bash
# Solo primary
ansible-playbook playbooks/site.yml --limit dns_primary --ask-vault-pass

# Solo secondari
ansible-playbook playbooks/site.yml --limit dns_secondary --ask-vault-pass

# Solo hardening
ansible-playbook playbooks/site.yml --tags hardening --ask-vault-pass

# Dry run
ansible-playbook playbooks/site.yml --check --diff --ask-vault-pass
```

### Ordine roles in `site.yml`

```
packages → hardening → nftables → bind9_primary → dnssec → acme_dns → monitoring
                                → bind9_secondary (sui secondari)
```

---

## Gestione zone

### Aggiornamento con serial automatico

Il playbook calcola il serial nel formato `YYYYMMDDnn`:
- Data odierna + serial esistente → incrementa `nn`
- Data passata → `YYYYMMDD01`
- Aggiorna **solo le zone cambiate** (diff prima del deploy)
- Verifica sintassi con `named-checkzone`
- Controlla propagazione sui secondari

```bash
# Tutte le zone
ansible-playbook playbooks/update-zones.yml --ask-vault-pass

# Zona specifica
ansible-playbook playbooks/update-zones.yml --ask-vault-pass \
  -e "zone_name=example.com"

# Forza reload
ansible-playbook playbooks/update-zones.yml --ask-vault-pass \
  -e "force_serial=true"
```

### Aggiungere una zona

1. Crea `zones/nuova-zona.com.yml`
2. Aggiungi in `group_vars/all/main.yml`:
   ```yaml
   dns_zones:
     - name: "nuova-zona.com"
       file: "zones/nuova-zona.com.yml"
       type: master
       ddns_enabled: false
   ```
3. `ansible-playbook playbooks/update-zones.yml --ask-vault-pass`

---

## DNSSEC

### Configurazione automatica

BIND 9.20 con `dnssec-policy` gestisce tutto:

| Parametro | Valore | Note |
|---|---|---|
| Algoritmo | Ed25519 | Chiavi da 32 byte |
| KSK lifetime | 1 anno | Rotazione automatica |
| ZSK lifetime | 90 giorni | Rotazione automatica |
| NSEC3 iterations | 0 | RFC 9276 |
| Signature validity | 14 giorni | Rinnovo 3gg prima |

### Pubblicazione DS record

```bash
ansible-playbook playbooks/dnssec-status.yml --ask-vault-pass
# Output: DS record da incollare nel pannello del registrar
```

### Verifica

```bash
# Firma locale
dig +dnssec example.com SOA @ns1.example.com

# Chain of trust end-to-end
delv @8.8.8.8 example.com SOA +rtrace

# Stato DNSSEC
ansible dns_primary -m command \
  -a "rndc dnssec -status example.com" --ask-vault-pass
```

---

## DDNS — Router OpenWrt

Il router aggiorna automaticamente il proprio record A ogni 5 minuti:

```
router-home.dyn.example.com.  60  IN  A  <IP WAN pubblico>
```

```yaml
# inventory/hosts.yml
openwrt_routers:
  hosts:
    router-home:
      ansible_host: 192.168.1.1
      ansible_user: root
      ddns_hostname: "router-home.dyn.example.com"
      ddns_interface: "wan"
```

```bash
ansible-playbook playbooks/site.yml --limit openwrt_routers --ask-vault-pass
```

Lo script rileva automaticamente CGNAT e ottiene l'IP pubblico reale.

---

## Monitoring

### Accesso via SSH tunnel

```bash
ssh -L 9090:127.0.0.1:9090 \
    -L 3000:127.0.0.1:3000 \
    -L 9093:127.0.0.1:9093 \
    ansible@192.168.1.10

# Grafana:      http://localhost:3000
# Prometheus:   http://localhost:9090
# Alertmanager: http://localhost:9093
```

### Alert preconfigurati

| Alert | Severità | Condizione |
|---|---|---|
| `BINDDown` | critical | bind_exporter non risponde 2+ min |
| `BINDQueryRateCritical` | critical | > 20.000 query/s |
| `BINDSerialMismatch` | warning | serial non allineato tra nodi |
| `DNSSECKeyExpiredCritical` | critical | chiave DNSSEC scade in < 24h |
| `NodeDown` | critical | server non raggiungibile |
| `DiskSpaceCritical` | critical | < 5% spazio libero |
| `NTPOffsetHigh` | warning | offset > 100ms |
| *(+7 altri)* | | |

### Notifiche email

```yaml
# group_vars/all/main.yml
alertmanager_smtp_enabled: true
alertmanager_smtp_host: "smtp.gmail.com:587"
alertmanager_smtp_from: "alerts@example.com"
alertmanager_smtp_to: "admin@example.com"
```

```yaml
# group_vars/all/vault.yml
vault_alertmanager_smtp_password: "app_password"
```

---

## Hardening

### Moduli attivi

| Modulo | Descrizione |
|---|---|
| `user` | Crea utente ansible, carica chiavi SSH, blocca root |
| `ssh` | chacha20/AES-GCM, curve25519, no password auth |
| `sysctl` | 25+ parametri kernel hardening |
| `filesystem` | `/tmp` noexec, no core dump, permessi file sensibili |
| `services` | Disabilita 10+ demoni inutili |
| `sudo` | Log completo, use_pty, requiretty |
| `auditd` | Regole CIS per file DNS, syscall critiche |
| `banner` | Banner pre-login + MOTD dinamico |
| `fail2ban` | SSH jail + DNS flood jail con nftables |
| `rkhunter` | Scan notturno, aggiornamento DB settimanale |
| `unattended_upgrades` | Solo patch sicurezza, bind9 in blacklist |

---

## Firewall nftables

### Primary (hidden master)

```
INPUT:  loopback, established, ICMP rate-limited, SSH, UDP/53 solo secondari+localhost
OUTPUT: throttle UDP > 512B per IP (anti-amplification)
RAW:    anti-spoofing bogon, bypass conntrack UDP/53
```

### Secondari (VPS pubblici)

```
INPUT:  UDP/53 pubblico rate-limited (30pps/IP, ban 120s), TCP/53 rate-limited,
        AXFR TCP illimitato dal primary, SSH rate-limited
OUTPUT: throttle UDP > 512B (anti-amplification, set dinamico amp_targets)
```

### Comandi utili

```bash
# IP bannati per DNS flood
nft list set inet filter dns_flood

# Sblocca IP manualmente
nft delete element inet filter dns_flood { 1.2.3.4 }

# Ruleset completo
nft list ruleset
```

---

## Certificati ACME

```bash
# Rinnovo manuale
ansible-playbook playbooks/renew-certs.yml --ask-vault-pass

# Aggiungere dominio: roles/acme_dns/defaults/main.yml
acme_domains:
  - domain: "example.com"
    keylength: "ec-256"
  - domain: "altro.com"
    keylength: "ec-256"
```

---

## CI/CD

### Pipeline GitHub Actions

```
push → lint (yamllint + ansible-lint)
     → syntax (tutti i playbook)
     → molecule (Docker Debian Trixie: prepare → converge → idempotency → verify)
     → validate-zones (valida YAML zone files)
     → security (trivy CVE + verifica vault cifrato)

tag vX.Y.Z → release (archivio + changelog automatico)
```

### Test in locale

```bash
yamllint .
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check \
  -i inventory/hosts.yml -e @group_vars/all/main.yml \
  -e "vault_tsig_secret=test vault_ddns_secret=test vault_proxmox_token_secret=test"
molecule test
```

---

## Operazioni giornaliere

```bash
# Stato BIND su tutti i nodi
ansible all -m command -a "systemctl status bind9" --ask-vault-pass

# Serial zone correnti
ansible dns_primary -m command \
  -a "rndc zonestatus example.com" --ask-vault-pass

# Forza zone transfer sui secondari
ansible dns_secondary -m command \
  -a "rndc retransfer example.com" --ask-vault-pass

# IP bannati per DNS flood
ansible dns_secondary -m command \
  -a "nft list set inet filter dns_flood" --ask-vault-pass

# Stato DNSSEC + DS records
ansible-playbook playbooks/dnssec-status.yml --ask-vault-pass

# Snapshot prima di un'operazione rischiosa
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-manutenzione"
```

### Aggiornare BIND9

```bash
# Testa prima su un secondario
ansible ns1 -m apt -a "name=bind9 state=latest" --ask-vault-pass
ansible ns1 -m command -a "systemctl restart bind9" --ask-vault-pass
dig @203.0.113.10 example.com SOA

# Poi primary (crea snapshot prima)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-bind9-upgrade"
ansible dns_primary -m apt -a "name=bind9 state=latest" --ask-vault-pass
ansible dns_primary -m command -a "systemctl restart bind9" --ask-vault-pass

# Infine gli altri secondari
ansible dns_secondary -m apt -a "name=bind9 state=latest" --ask-vault-pass
```

---

## Troubleshooting

### BIND9 non si avvia

```bash
journalctl -u bind9 -n 50 --no-pager
named-checkconf /etc/bind/named.conf
named-checkzone example.com /var/lib/bind/zones/db.example.com
```

### Zone transfer non funziona

```bash
dig @192.168.1.10 example.com AXFR
grep "transfer" /var/log/named/named.log
rndc retransfer example.com
```

### DNSSEC validation errors

```bash
rndc dnssec -status example.com
rndc sign example.com
dnssec-verify -z example.com /var/lib/bind/zones/db.example.com
```

### Certificati ACME non si rinnovano

```bash
/opt/acme.sh/acme.sh --renew -d example.com --force
cat /var/log/acme-renew.log
```

### Proxmox — clone fallisce

```bash
# Verifica che il template esista
qm status 9000

# Verifica permessi token API
pvesh get /access/acl

# Log Proxmox
journalctl -u pvedaemon -n 50
```

### Proxmox — cloud-init non applica IP

```bash
# Controlla lo status cloud-init sulla VM
ssh ansible@192.168.1.10 "cloud-init status"
ssh ansible@192.168.1.10 "cat /var/log/cloud-init.log | tail -30"

# Rigenera immagine cloud-init e riavvia
qm set 200 --cicustom ""
qm cloudinit update 200
qm reboot 200
```

### VM non risponde dopo creazione

```bash
# Verifica stato VM
qm status 200

# Console VM su Proxmox
qm terminal 200

# Log avvio
qm showcmd 200
```

---

## Sicurezza

### Gestione secret

Tutti i secret sono in `group_vars/all/vault.yml` cifrato con ansible-vault. Il file in chiaro non deve mai essere committato. Il `.gitignore` esclude il vault non cifrato.

```bash
# Verifica che il vault sia cifrato
head -1 group_vars/all/vault.yml
# Output atteso: $ANSIBLE_VAULT;1.1;AES256
```

### Rotazione chiavi TSIG

```bash
tsig-keygen -a hmac-sha256 axfr-key-new
ansible-vault edit group_vars/all/vault.yml
ansible-playbook playbooks/site.yml --ask-vault-pass
dig @192.168.1.10 example.com AXFR   # verifica
```

### Rotazione token API Proxmox

1. Crea nuovo token in Proxmox
2. Aggiorna `vault_proxmox_token_secret` nel vault
3. Esegui `ansible-playbook playbooks/proxmox.yml --ask-vault-pass` per verificare
4. Revoca il vecchio token

---

## Licenza

MIT — vedi [LICENSE](LICENSE)

---

## Contribuire

1. Fork del repository
2. Branch: `git checkout -b feature/nome`
3. Test: `yamllint . && ansible-lint && molecule test`
4. Commit: `git commit -m "feat: descrizione"`
5. Pull request su `main`

I contributi devono passare l'intera pipeline CI prima del merge.

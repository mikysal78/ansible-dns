# 🌐 ansible-dns — Infrastruttura DNS Professionale

[![CI](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml/badge.svg)](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml)
[![ansible-lint](https://img.shields.io/badge/ansible--lint-passing-brightgreen)](https://github.com/ansible/ansible-lint)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Debian Trixie](https://img.shields.io/badge/Debian-Trixie-red)](https://www.debian.org/)
[![BIND9](https://img.shields.io/badge/BIND-9.20-blue)](https://www.isc.org/bind/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange)](https://www.proxmox.com/)

Playbook Ansible completo per deployare un'infrastruttura DNS **production-ready** con hidden primary su Proxmox VE, N secondari pubblici su VPS, DNSSEC inline signing, hardening OS, firewall nftables, certificati ACME wildcard con deploy automatico ai CT Proxmox, DDNS per router OpenWrt e monitoring con Prometheus/Grafana.

---

## 📋 Indice

- [Architettura](#architettura)
- [Funzionalità](#funzionalità)
- [Prerequisiti](#prerequisiti)
- [Struttura del progetto](#struttura-del-progetto)
- [Makefile — comandi rapidi](#makefile--comandi-rapidi)
- [Proxmox — Provisioning VM](#proxmox--provisioning-vm)
- [OVH — VM secondarie](#ovh--vm-secondarie)
- [Setup iniziale](#setup-iniziale)
- [Configurazione](#configurazione)
- [Deploy DNS](#deploy-dns)
- [Tunnel WireGuard](#tunnel-wireguard)
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
                          │  Tunnel WireGuard cifrato (10.99.0.0/24)
                          │  AXFR/IXFR (TSIG) + NOTIFY viaggiano qui dentro
           ┌──────────────┼──────────────┬─────────────┐
           ▼              ▼              ▼             ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐  fino a 5
    │ ns1 (VPS)  │ │ ns2 (VPS)  │ │ ns3 (VPS)  │  secondari
    │Debian Trixie│ │Debian Trixie│ │Debian Trixie│
    │ wg 10.99.0.2│ │ wg 10.99.0.3│ │ wg 10.99.0.4│
    │ Query DNS  │ │ Query DNS  │ │ Query DNS  │
    │ pubbliche  │ │ pubbliche  │ │ pubbliche  │
    └────────────┘ └────────────┘ └────────────┘
           ▲              ▲              ▲
           └──────────────┼──────────────┘
                    UDP/TCP 53 pubblico
                    (rate limiting + anti-amplification)

  Il primary (dietro NAT) inizia il tunnel verso i secondari (endpoint
  pubblici); PersistentKeepalive mantiene aperto il percorso. Così il
  primary resta nascosto e il transfer di zona è cifrato end-to-end.

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

### Tunnel WireGuard (primary ↔ secondari)
- **Trasferimento di zona cifrato** — AXFR/IXFR e NOTIFY viaggiano dentro un tunnel WireGuard, mai in chiaro su internet
- **Primary dietro NAT** — pensato per il caso reale di un hidden primary in LAN (senza IP pubblico) e secondari su VPS cloud
- **Topologia roaming peer** — il primary inizia la connessione verso i secondari (endpoint pubblici fissi) con `PersistentKeepalive`, mantenendo aperto il percorso attraverso il NAT
- **Subnet dedicata** `10.99.0.0/24` — gli IP del tunnel diventano gli indirizzi che BIND usa per il transfer
- Chiavi generate per host e distribuite automaticamente via `hostvars`

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
- **acme.sh** con DNS-01 challenge via `nsupdate` (plugin ufficiale `dns_nsupdate`, RFC 2136)
- Certificati **wildcard** `*.example.com` + root, versione acme.sh pinned
- Rinnovo automatico via cron (02:30 ogni notte)
- **Deploy automatico ai CT Proxmox**: il primary genera una chiave SSH ed25519 dedicata, la distribuisce ai CT consumer e copia i certificati rinnovati via rsync (porta configurabile)
- Deploy **best-effort**: se un CT è irraggiungibile, il rinnovo sul primary non fallisce

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
- Gli exporter dei secondari sono raggiunti dal primary **via tunnel WireGuard** (non esposti su internet)
- Grafana 13 con dashboard DNS overview + system health
- Alertmanager con 14 alert preconfigurati (email/webhook)
- Alert: BIND down, zone transfer failure, DDoS detection, DNSSEC key expiry
- Grafana ascolta solo su `127.0.0.1`: accesso via tunnel SSH (vedi sezione Accesso)

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
- **Secondari**: 1 vCPU, 512MB RAM, 10GB (VPS pubblici — OVH, Hetzner, Contabo, ecc.)

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
├── requirements.yml           # community.general, ansible.posix, community.proxmox
├── README.md
├── LICENSE
├── CHANGELOG.md
│
├── inventory/
│   ├── hosts.yml              # inventory reale (escluso da git)
│   ├── hosts.yml.example      # template inventory (committato)
│   └── group_vars/
│       └── all/
│           ├── main.yml           # configurazione globale (escluso da git)
│           ├── main.yml.example   # template configurazione (committato)
│           ├── vault.yml.example  # template secret (committato)
│           └── vault.yml          # secret reali cifrati (escluso da git)
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
│   ├── wireguard/             # tunnel cifrato primary <-> secondari
│   ├── bind9_primary/
│   ├── bind9_secondary/
│   ├── dnssec/
│   ├── acme_dns/
│   ├── ddns_openwrt/
│   └── monitoring/
│
├── Makefile                           # comandi rapidi (deploy, zones, acme, ...)
├── playbooks/
│   ├── proxmox.yml                    # provisioning VM primary
│   ├── proxmox-prepare-template.yml   # crea template Debian Trixie
│   ├── proxmox-snapshot.yml           # gestione snapshot
│   ├── site.yml                       # deploy DNS completo
│   ├── update-zones.yml               # aggiorna zone con serial auto
│   ├── acme-only.yml                  # emissione cert + deploy ai CT
│   ├── cert-deploy.yml                # copia cert dal primary ai CT (via control node)
│   ├── renew-certs.yml                # rinnovo manuale forzato
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

## Makefile — comandi rapidi

Il `Makefile` alla radice del progetto evita di ricordare i path dei playbook.

```bash
make deploy        # deploy completo (site.yml)
make zones         # aggiorna solo le zone DNS
make acme          # emetti/rinnova cert e distribuiscili ai CT
make cert-deploy   # ricopia cert esistenti ai CT (senza re-emettere)
make renew         # rinnovo manuale forzato certificati ACME
make dnssec        # stato DNSSEC e prossime rotazioni chiavi
make vault-summary # riepilogo variabili vault
make ping          # verifica connettività a tutti gli host
make syntax        # syntax check di site.yml
make snapshot      # snapshot Proxmox del CT primary
```

Di default usa `--ask-vault-pass`. Per un file password:

```bash
make deploy VAULT="--vault-password-file=/git/.vault_pass"
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
   ansible-vault edit inventory/group_vars/all/vault.yml
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

### Configurazione Proxmox (`inventory/group_vars/all/main.yml`)

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

---

## OVH — VM secondarie

Le VM OVH funzionano come **secondari pubblici** insieme (o al posto) di Hetzner/Contabo. I ruoli `bind9_secondary`, `nftables`, `hardening`, `packages` e `monitoring` non dipendono da Proxmox: agiscono su qualsiasi Debian Trixie raggiungibile via SSH.

> **Provisioning**: a differenza del primary su Proxmox (creazione VM automatizzata via API), le VM OVH vengono ordinate manualmente dal pannello OVH. Ansible automatizza solo la configurazione successiva. Per OVH Public Cloud (OpenStack) è teoricamente possibile automatizzare anche la creazione con la collection `openstack.cloud`, ma non è incluso in questo progetto.

### 1. Ordina la VM OVH

Prodotti adatti come secondario DNS:
- **OVH VPS** (da ~3,50€/mese) — sufficiente: 1 vCPU, 2GB RAM
- **OVH Public Cloud** (istanze a consumo)
- **OVH Bare Metal / Eco** (overkill per un secondario, ma valido)

Durante l'ordine seleziona **Debian Trixie (13)** come sistema operativo e carica la tua **chiave SSH pubblica**.

### 2. Configura il firewall OVH (Edge Network Firewall)

Questo è il punto più importante e specifico di OVH. L'Edge Network Firewall di OVH ha tre caratteristiche che vanno comprese:

- È **stateless** e integrato nell'infrastruttura Anti-DDoS: filtra solo il traffico proveniente da **fuori** dalla rete OVH. Il traffico interno OVH raggiunge comunque il server su qualsiasi porta.
- **Non sostituisce** il firewall a livello server: per questo il role `nftables` resta indispensabile (protegge anche dal traffico interno OVH e applica rate limiting + anti-amplification).
- La logica delle **priorità è invertita**: numeri più bassi hanno priorità più alta, e serve **sempre** una regola finale di blocco esplicita, altrimenti le sole regole di autorizzazione sono inefficaci.

Configurazione consigliata nell'Edge Network Firewall (pannello OVH → IP → firewall):

| Priorità | Azione | Protocollo | Porta | Opzione | Note |
|---|---|---|---|---|---|
| 0 | Authorize | TCP | 22 | — | SSH (meglio se da IP fisso) |
| 1 | Authorize | UDP | 53 | — | query DNS |
| 2 | Authorize | TCP | 53 | — | query DNS grandi + AXFR |
| 3 | Authorize | TCP | — | established | risposte sessioni TCP |
| 4 | Authorize | ICMP | — | — | ping / traceroute |
| 19 | Deny | IPv4 | — | — | **blocco finale obbligatorio** |

> Essendo stateless, il firewall OVH non tiene traccia delle connessioni: la regola `TCP established` (priorità 3) è necessaria per le risposte. Per il DNS su UDP non serve, perché ogni pacchetto è indipendente.

> **Attenzione Anti-DDoS**: durante un attacco la mitigazione automatica OVH può temporaneamente limitare il traffico DNS verso la VM. Avere più secondari su provider diversi (OVH + Hetzner + ...) mitiga questo rischio: se un secondario è sotto mitigazione, gli altri continuano a rispondere.

### 3. Aggiungi la VM all'inventory

```yaml
# inventory/hosts.yml
dns_secondary:
  hosts:
    ns1:
      ansible_host: 203.0.113.10        # es. Hetzner
      ansible_user: ansible
      dns_secondary_index: 1
    ns2-ovh:
      ansible_host: 51.91.x.x           # IP pubblico VM OVH
      ansible_user: ansible
      dns_secondary_index: 2
```

```yaml
# inventory/group_vars/all/main.yml
dns_secondary_ips:
  - "203.0.113.10"
  - "51.91.x.x"          # VM OVH
```

### 4. Deploy

```bash
ansible-playbook playbooks/site.yml --limit dns_secondary --ask-vault-pass
```

### 5. Verifica

```bash
# Query diretta alla VM OVH
dig @51.91.x.x example.com SOA

# Verifica che il firewall nftables del server sia attivo
ansible ns2-ovh -m command -a "nft list ruleset" --ask-vault-pass

# Verifica zone transfer ricevuto dal primary
ansible ns2-ovh -m command -a "rndc zonestatus example.com" --ask-vault-pass
```

### Primary su OVH (sconsigliato ma possibile)

Se vuoi mettere anche il **primary** su OVH rinunciando all'hidden primary locale, funziona ma cambia il modello di sicurezza: il primary diventa raggiungibile da internet. In tal caso:
- Le regole nftables del role primary già limitano la porta 53 a localhost e secondari
- Apri nell'Edge Firewall OVH solo SSH + la porta 53 verso gli IP dei secondari
- Perdi il vantaggio principale dell'architettura hidden primary (master non esposto)

L'approccio consigliato resta: **primary locale su Proxmox** + **secondari pubblici su OVH/Hetzner/ecc.**


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

Copia il template `vault.yml.example` e compilalo con i valori reali:

```bash
cp inventory/group_vars/all/vault.yml.example inventory/group_vars/all/vault.yml

# Modifica con i tuoi secret (TSIG, password, token Proxmox)
$EDITOR inventory/group_vars/all/vault.yml

# Cifra il file (non sarà mai committato in chiaro grazie a .gitignore)
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

Le chiavi richieste sono documentate in `vault.yml.example`:
`vault_tsig_secret`, `vault_ddns_secret`, `vault_acme_email`,
`vault_grafana_admin_password`, `vault_alertmanager_smtp_password`,
`vault_proxmox_token_secret`.

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
# inventory/group_vars/all/main.yml
cloudinit_ssh_authorized_keys:
  - "ssh-ed25519 AAAA... tua-chiave"

hardening_ssh_authorized_keys:
  - key: "ssh-ed25519 AAAA... tua-chiave"
    user: ansible
```

---

## Configurazione

### Variabili principali (`inventory/group_vars/all/main.yml`)

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

### Riepilogo a fine deploy

`site.yml` termina con un play di riepilogo che mostra:

- **INFRASTRUTTURA** — IP primary, NS1/NS2 pubblici, indirizzi WireGuard
- **ZONE DNS** — zone attive con tipo e stato DDNS
- **MONITORING** — URL Grafana/Prometheus/Alertmanager con credenziali e comando SSH tunnel pronto per il notebook
- **MONITORING SMTP** — stato notifiche email/webhook
- **CERTIFICATI ACME** — file per dominio e CT destinatari
- **CT CONSUMER** — elenco CT con cert e reload command
- **VAULT** — valori delle variabili cifrate

```bash
# nasconde i valori sensibili (utile su shell condivise o in CI)
ansible-playbook playbooks/site.yml --ask-vault-pass -e reveal_secrets=false
```

> ⚠️ Con `reveal_secrets=true` (default) le password appaiono in chiaro nello stdout.
> Non eseguire con output visibile ad altri. Per ispezionare il vault:
> `ansible-vault view inventory/group_vars/all/vault.yml`.

### Ordine roles in `site.yml`

```
packages → hardening → nftables → bind9_primary → dnssec → acme_dns → monitoring
                                → bind9_secondary (sui secondari)
```

---

## Tunnel WireGuard

Il primary è un **hidden master in LAN dietro NAT**, senza IP pubblico. I secondari sono su VPS pubblici. Senza un percorso tra i due, l'AXFR non potrebbe funzionare (un IP privato non è instradabile su internet). La soluzione è un tunnel WireGuard cifrato.

### Topologia

Il primary (dietro NAT) **inizia** la connessione verso i secondari, che hanno endpoint pubblici fissi. `PersistentKeepalive` tiene aperto il percorso attraverso il NAT. Una volta su, il tunnel è bidirezionale e AXFR/NOTIFY ci viaggiano dentro cifrati.

```
Primary (NAT)              Secondari (IP pubblici)
10.99.0.1   ──connette──►  10.99.0.2  (ns1, ascolta :51820)
            ──connette──►  10.99.0.3  (ns2, ascolta :51820)
            keepalive 25s mantiene aperti i buchi NAT
```

### Configurazione

Ogni host DNS ha un indirizzo nel tunnel, assegnato nell'inventory:

```yaml
# inventory/hosts.yml
ns-primary:
  ansible_host: 10.0.0.14
  wg_address: 10.99.0.1      # IP nel tunnel
ns1:
  ansible_host: 203.0.113.10
  wg_address: 10.99.0.2
ns2:
  ansible_host: 203.0.113.20
  wg_address: 10.99.0.3
```

Gli IP DNS usati per il transfer puntano al tunnel:

```yaml
# inventory/group_vars/all/main.yml
dns_primary_ip: "10.99.0.1"
dns_secondary_ips:
  - "10.99.0.2"
  - "10.99.0.3"
```

Il play WireGuard in `site.yml` gira su primary e secondari **insieme**, perché il template ha bisogno delle chiavi pubbliche di tutti gli host (via `hostvars`).

### Verifica

```bash
# handshake attivo con entrambi i peer?
ssh -p 2400 root@10.0.0.14 "wg show"

# il primary raggiunge i secondari nel tunnel?
ssh -p 2400 root@10.0.0.14 "ping -c2 10.99.0.2"

# AXFR funziona via tunnel?
ssh -p 2400 root@10.0.0.14 "dig @127.0.0.1 example.com AXFR | head"
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
2. Aggiungi in `inventory/group_vars/all/main.yml`:
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

Grafana, Prometheus e Alertmanager ascoltano solo su `127.0.0.1` del primary (IP privato LAN, non esposto su internet). Il role hardening abilita `PermitOpen` solo per le porte di monitoraggio.

```bash
# Apri il tunnel dal tuo notebook (rimane in background con -N)
ssh -p 2400 -N \
    -L 3000:127.0.0.1:3000 \
    -L 9090:127.0.0.1:9090 \
    -L 9093:127.0.0.1:9093 \
    root@<primary-ip>

# Grafana:      http://localhost:3000   (admin / vault_grafana_admin_password)
# Prometheus:   http://localhost:9090
# Alertmanager: http://localhost:9093
```

Il comando SSH tunnel preciso (con IP reale) viene stampato a fine di ogni `make deploy` nella sezione **MONITORING — accesso**.

> Se il primary non è raggiungibile direttamente dal notebook, fai il jump via Proxmox:
> ```bash
> ssh -J root@<proxmox-ip> -p 2400 -N \
>     -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 \
>     root@<primary-ip>
> ```

> **Firewall**: se non riesci a connetterti anche con il tunnel aperto, aggiungi il tuo IP a `monitoring_allowed_sources` in `group_vars/all/main.yml` e rilancia `make deploy`.

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
# inventory/group_vars/all/main.yml
alertmanager_smtp_enabled: true
alertmanager_smtp_host: "smtp.gmail.com:587"
alertmanager_smtp_from: "alerts@example.com"
alertmanager_smtp_to: "admin@example.com"
```

```yaml
# inventory/group_vars/all/vault.yml
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

### Come funziona

1. acme.sh sul primary ottiene i certificati wildcard (`*.example.com` + root) via DNS-01 challenge usando `nsupdate` con la TSIG key `ddns-key`
2. Al rinnovo (cron 02:30) o al primo deploy, il primary copia i certificati ai CT consumer via SSH (chiave ed25519 dedicata)
3. Dopo la copia, il CT esegue il `reload_cmd` configurato (nginx, postfix, dovecot…)

### Configurare i domini e i CT destinatari

```yaml
# inventory/group_vars/all/main.yml
acme_deploy_key: "/root/.ssh/acme_deploy_id_ed25519"
acme_deploy_ssh_port: 2400   # porta SSH dei CT

acme_domains:
  - domain: "example.com"
    keylength: "ec-256"
    deploy:
      - host: "10.0.0.16"          # CT nginx
        reload_cmd: "systemctl reload nginx"
  - domain: "altro.com"
    keylength: "ec-256"
    deploy:
      - host: "10.0.0.6"           # CT mail
        reload_cmd: "systemctl reload postfix && systemctl reload dovecot"
```

```yaml
# inventory/hosts.yml — gruppo cert_consumers
cert_consumers:
  hosts:
    ct-web:
      ansible_host: 10.0.0.16
      ansible_user: root
      ansible_port: 2400
      cert_domain: "example.com"
      cert_reload_cmd: "systemctl reload nginx"
    ct-mail:
      ansible_host: 10.0.0.6
      ansible_user: root
      ansible_port: 2400
      cert_domain: "altro.com"
      cert_reload_cmd: "systemctl reload postfix && systemctl reload dovecot"
```

### Comandi

```bash
# Emette/rinnova cert E distribuisce ai CT (tutto in una run)
make acme

# Ricopia solo i cert già emessi ai CT (senza re-emettere)
make cert-deploy

# Rinnovo manuale forzato
make renew

# Controlla i log di rinnovo automatico sul primary
ssh -p 2400 root@<primary-ip> "tail -50 /var/log/acme-renew.log"
```

### Troubleshooting

```bash
# Forza rinnovo manuale di un singolo dominio
ssh -p 2400 root@<primary-ip> \
  "/opt/acme.sh/acme.sh --renew -d example.com --force --home /opt/acme.sh"

# Verifica che i cert siano arrivati sul CT
ssh -p 2400 root@<ct-ip> "ls -la /etc/ssl/acme/"
ssh -p 2400 root@<ct-ip> \
  "openssl x509 -noout -subject -enddate -in /etc/ssl/acme/example.com.fullchain.pem"
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
  -i inventory/hosts.yml -e @inventory/group_vars/all/main.yml \
  -e "vault_tsig_secret=test vault_ddns_secret=test vault_proxmox_token_secret=test"
molecule test
```

---

## Operazioni giornaliere

```bash
# Aggiorna zone DNS
make zones

# Stato DNSSEC + DS records
make dnssec

# Snapshot prima di un'operazione rischiosa
make snapshot

# Ricopia certificati ai CT (dopo un rinnovo manuale o una nuova VM)
make cert-deploy

# Verifica connettività a tutti gli host
make ping
```

Comandi diretti utili:

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

# Log rinnovo certificati
ssh -p 2400 root@<primary-ip> "tail -50 /var/log/acme-renew.log"

# Snapshot con nome personalizzato
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
ssh -p 2400 root@10.0.0.14 "cloud-init status"
ssh -p 2400 root@10.0.0.14 "cat /var/log/cloud-init.log | tail -30"

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

Tutti i secret sono in `inventory/group_vars/all/vault.yml` cifrato con ansible-vault. Il file in chiaro non deve mai essere committato. Il `.gitignore` esclude il vault non cifrato.

```bash
# Verifica che il vault sia cifrato
head -1 inventory/group_vars/all/vault.yml
# Output atteso: $ANSIBLE_VAULT;1.1;AES256
```

### Rotazione chiavi TSIG

```bash
tsig-keygen -a hmac-sha256 axfr-key-new
ansible-vault edit inventory/group_vars/all/vault.yml
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

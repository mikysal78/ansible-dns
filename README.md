# 🌐 ansible-dns — Professional DNS Infrastructure

[🇮🇹 Italiano](README.it.md) · 🇬🇧 English

[![CI](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml/badge.svg)](https://github.com/mikysal78/ansible-dns/actions/workflows/ci.yml)
[![ansible-lint](https://img.shields.io/badge/ansible--lint-passing-brightgreen)](https://github.com/ansible/ansible-lint)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Debian Trixie](https://img.shields.io/badge/Debian-Trixie-red)](https://www.debian.org/)
[![BIND9](https://img.shields.io/badge/BIND-9.20-blue)](https://www.isc.org/bind/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange)](https://www.proxmox.com/)
[![Made in Italy](https://img.shields.io/badge/Made%20in-Italy%20🇮🇹-green)](README.it.md)

> 🇮🇹 **An Italian project** — born to run the DNS infrastructure of the
> [Ninux](https://ninux.org) wireless community network in Basilicata, Italy.
> The original (and most complete) documentation is in [Italian](README.it.md);
> this English version is kept in sync with it.

A complete Ansible playbook that deploys a **production-ready** DNS infrastructure: hidden primary on Proxmox VE, N public secondaries on VPS, DNSSEC inline signing, OS hardening, nftables firewall, wildcard ACME certificates with automatic deployment to Proxmox CTs, DDNS for OpenWrt routers, and Prometheus/Grafana monitoring.

---

## 📋 Table of contents

- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Project layout](#project-layout)
- [Makefile — quick commands](#makefile--quick-commands)
- [Proxmox — VM provisioning](#proxmox--vm-provisioning)
- [OVH — secondary VMs](#ovh--secondary-vms)
- [Initial setup](#initial-setup)
- [Configuration](#configuration)
- [DNS deployment](#dns-deployment)
- [WireGuard tunnel](#wireguard-tunnel)
- [Zone management](#zone-management)
- [DNSSEC](#dnssec)
- [DDNS — OpenWrt routers](#ddns--openwrt-routers)
- [Monitoring](#monitoring)
- [Hardening](#hardening)
- [nftables firewall](#nftables-firewall)
- [ACME certificates](#acme-certificates)
- [CI/CD](#cicd)
- [Day-to-day operations](#day-to-day-operations)
- [Troubleshooting](#troubleshooting)
- [Security](#security)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PROXMOX VE (local network)                       │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  VM dns-primary (VMID 200) — Debian Trixie                 │    │
│  │  192.168.1.10 — 2 host vCPU — 2GB RAM — 40GB VirtIO        │    │
│  │                                                            │    │
│  │  • BIND9 hidden master (never exposed to the internet)     │    │
│  │  • DNSSEC inline signing (Ed25519, dnssec-policy)          │    │
│  │  • acme.sh wildcard via DNS-01                             │    │
│  │  • Prometheus + Grafana + Alertmanager                     │    │
│  │  • fail2ban + nftables + auditd + rkhunter                 │    │
│  └──────────────────────┬─────────────────────────────────────┘    │
└─────────────────────────┼───────────────────────────────────────────┘
                          │  Encrypted WireGuard tunnel (10.99.0.0/24)
                          │  AXFR/IXFR (TSIG) + NOTIFY travel in here
           ┌──────────────┼──────────────┬─────────────┐
           ▼              ▼              ▼             ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐  up to 5
    │ ns1 (VPS)  │ │ ns2 (VPS)  │ │ ns3 (VPS)  │  secondaries
    │Debian Trixie│ │Debian Trixie│ │Debian Trixie│
    │ wg 10.99.0.2│ │ wg 10.99.0.3│ │ wg 10.99.0.4│
    │ Public DNS │ │ Public DNS │ │ Public DNS │
    │  queries   │ │  queries   │ │  queries   │
    └────────────┘ └────────────┘ └────────────┘
           ▲              ▲              ▲
           └──────────────┼──────────────┘
                    public UDP/TCP 53
                    (rate limiting + anti-amplification)

  The primary (behind NAT) initiates the tunnel towards the secondaries
  (public endpoints); PersistentKeepalive keeps the path open. The
  primary stays hidden and zone transfers are encrypted end-to-end.

    ┌─────────────────────────────────────────┐
    │  OpenWrt router (DDNS)                  │
    │  nsupdate TSIG → dyn.example.com        │
    │  router-home.dyn.example.com → WAN IP   │
    └─────────────────────────────────────────┘
```

---

## Features

### Proxmox VE
- Primary VM provisioning via the **Proxmox API** (`community.general.proxmox_kvm`)
- Automatic **Debian Trixie genericcloud template** creation with `virt-customize`
- Template clone → VM with **cloud-init** (static IP, user, SSH key, packages)
- Tuned hardware: `q35`, `UEFI`, `host CPU` (AES-NI + rdrand), VirtIO, ballooning disabled
- **Automatic post-creation snapshot** as a pre-deploy baseline
- Dedicated snapshot management playbooks (create, list, rollback, delete)

### DNS core
- **Hidden primary** — the master is never exposed to the internet
- **N public secondaries** — from 2 to 5+ VPS, fully automated configuration
- **Zones as YAML** — readable format supporting every professional record type
- **Authenticated AXFR/IXFR** — `hmac-sha256` TSIG key
- **Supported records** — A, AAAA, CNAME, MX, TXT, SRV, CAA, TLSA, SSHFP, PTR

### WireGuard tunnel (primary ↔ secondaries ↔ Proxmox)
- **Encrypted zone transfers** — AXFR/IXFR and NOTIFY travel inside a WireGuard tunnel, never in cleartext across the internet
- **Primary behind NAT** — designed for the real-world case of a hidden primary on a LAN (no public IP) with secondaries on cloud VPS
- **Roaming-peer topology** — the primary initiates the connection towards the secondaries (fixed public endpoints) with `PersistentKeepalive`, keeping the path open across NAT
- **Dedicated subnet** `10.99.0.0/24` — the tunnel IPs become the addresses BIND uses for transfers
- Per-host keys generated and distributed automatically via `hostvars`
- **Optional extra peers** (e.g. the Proxmox host itself: `proxmox` inventory group with `wg_address` set): same logic as the secondaries (fixed endpoint + keepalive, the primary talks to them), used to let external nsupdate/RFC2136 clients on the LAN reach BIND without ever exposing BIND outside loopback+WireGuard — see [Proxmox built-in ACME](#proxmox-built-in-acme-web-ui-certificate) below

### DNSSEC
- **Automatic inline signing** — BIND 9.20 `dnssec-policy`, zero manual intervention
- **Ed25519** — modern algorithm, compact and fast keys
- **KSK** rotated yearly, **ZSK** every 90 days — both automatic
- **NSEC3** with `iterations=0` (RFC 9276)
- Compatible with DDNS zones

### DDNS — OpenWrt routers
- A-record updates via `nsupdate` with TSIG
- Automatic CGNAT detection
- UCI configuration automated with Ansible

### ACME certificates
- **acme.sh** with DNS-01 challenge via `nsupdate` (official `dns_nsupdate` plugin, RFC 2136)
- **Wildcard** certificates `*.example.com` + apex, pinned acme.sh version
- Automatic renewal via cron (02:30 nightly)
- **Automatic deployment to Proxmox CTs**: the primary generates a dedicated ed25519 SSH key, distributes it to the consumer CTs and copies renewed certificates over SSH (configurable port)
- **Best-effort** deployment: if a CT is unreachable, renewal on the primary does not fail
- **Reload only when the certificate changed**: `--install-cert` (which always runs the reloadcmd) and the CT reloads only fire when the issued cert differs from the installed one — re-running the deploy never restarts nginx/postfix/dovecot for nothing. To force (e.g. after changing a `reload_cmd`): `-e acme_force_install=true`
- Renewal log (`/var/log/acme-renew.log`) rotated monthly via logrotate

### Proxmox built-in ACME (web UI certificate)
To renew the `pveproxy` certificate (the Proxmox VE web UI) with Proxmox's native ACME (not acme.sh), instead of opening BIND on the LAN the Proxmox host is added as a **WireGuard peer** — consistent with the hidden-primary architecture, BIND is never exposed outside loopback+tunnel:

1. In `inventory/hosts.yml`, the `proxmox` group already has `wg_address: 10.99.0.4` for the `pve` host; `make deploy` (or the "Setup WireGuard tunnel" play) generates the keys and configures the peer on both the primary and Proxmox.
2. `ddns_allowed_sources` in `inventory/group_vars/all/main.yml` includes `10.99.0.4` (the tunnel IP, not a LAN IP): the primary's firewall accepts DDNS/nsupdate updates from that address, still authenticated by the `ddns-key` TSIG key.
3. Configure Proxmox's `nsupdate` DNS plugin (`Datacenter → ACME` or `pvenode acme plugin`) with:
   - **Server**: `10.99.0.1` (the primary's WireGuard IP, port 53)
   - **Key name**: `ddns-key`, **algorithm**: `hmac-sha256`
   - **Secret**: `ansible-vault view inventory/group_vars/all/vault.yml` (variable `vault_ddns_secret`)
4. Register the Proxmox GUI domain/hostname as an ACME domain on the host, using the DNS plugin just created.

Note: `ddns-key` is not restricted to the `_acme-challenge` record — whoever holds it can update any record in the DDNS zones. The only real additional barrier of the WireGuard peer is the cryptographic authentication of the tunnel itself.

### OS hardening
- SSH with modern ciphers (chacha20, AES-GCM, curve25519)
- Kernel sysctl: anti-spoofing, TCP syncookies, ASLR, kptr_restrict
- Filesystem: `/tmp`, `/var/tmp`, `/dev/shm` mounted `noexec,nosuid,nodev`
- auditd with CIS rules (identity, network, DNS files, critical syscalls)
- sudo with full logging, requiretty, 5-minute timeout
- Nightly rkhunter scan + security-only unattended-upgrades
- Dynamic MOTD with BIND status, nftables state and banned IPs

### nftables firewall
- Primary: port 53 only from localhost and the secondaries
- Secondaries: per-IP rate limiting, automatic bans via the `dns_flood` dynamic set
- Anti-amplification: throttle UDP responses > 512B in OUTPUT
- Bogon anti-spoofing on the raw table, UDP/53 conntrack bypass
- fail2ban integrated with nftables

### Monitoring
- Prometheus + bind_exporter + node_exporter on every node
- The secondaries' exporters are scraped by the primary **through the WireGuard tunnel** (not exposed to the internet)
- Grafana 13 with DNS overview + system health dashboards
- Alertmanager with 14 preconfigured alerts (email/webhook)
- Alerts: BIND down, zone transfer failure, DDoS detection, DNSSEC key expiry
- Grafana listens on `127.0.0.1` only: access via SSH tunnel (see the Access section)

### CI/CD
- ansible-lint `production` profile + yamllint
- Molecule with the Docker driver (Debian Trixie) + verify assertions
- GitHub Actions: lint + syntax + molecule + trivy + automatic releases

---

## Prerequisites

### Ansible controller
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

> SSH host keys are verified in **TOFU** mode (`StrictHostKeyChecking=accept-new`):
> new hosts are accepted on first contact, a *changed* key is rejected.
> If you reinstall a host, remove its old key first: `ssh-keygen -R <ip-or-hostname>`.

### Proxmox VE
- Version 8.x or 9.x (tested on 9.2)
- API user with token (see [API token configuration](#proxmox-api-token-configuration))
- Storage with cloud-init snippet support enabled
- SSH access to the Proxmox node for template creation
- Network connectivity between the primary VM and the secondary VPS (TCP port 53)

### DNS servers
- **OS**: Debian Trixie (13)
- **Primary**: 2 vCPU, 2GB RAM, 40GB disk (Proxmox VM)
- **Secondaries**: 1 vCPU, 512MB RAM, 10GB (public VPS — OVH, Hetzner, Contabo, etc.)

### OpenWrt routers
- OpenWrt 23.x or later
- `opkg install bind-client`

---

## Project layout

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
│   ├── hosts.yml              # real inventory (git-ignored)
│   ├── hosts.yml.example      # inventory template (committed)
│   └── group_vars/
│       └── all/
│           ├── main.yml           # global configuration (git-ignored)
│           ├── main.yml.example   # configuration template (committed)
│           ├── vault.yml.example  # secrets template (committed)
│           └── vault.yml          # real encrypted secrets (git-ignored)
│
├── zones/
│   ├── example.com.yml
│   ├── dyn.example.com.yml
│   └── 203.0.113.reverse.yml
│
├── roles/
│   ├── proxmox_vm/            # ← VM provisioning on Proxmox
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
│   ├── wireguard/             # encrypted primary <-> secondaries tunnel
│   ├── bind9_primary/
│   ├── bind9_secondary/
│   ├── dnssec/
│   ├── acme_dns/
│   ├── ddns_openwrt/
│   └── monitoring/
│
├── Makefile                           # quick commands (deploy, zones, acme, ...)
├── playbooks/
│   ├── proxmox.yml                    # primary VM provisioning
│   ├── proxmox-prepare-template.yml   # creates the Debian Trixie template
│   ├── proxmox-snapshot.yml           # snapshot management
│   ├── site.yml                       # full DNS deployment
│   ├── update-zones.yml               # updates zones with automatic serial
│   ├── acme-only.yml                  # cert issuance + deployment to CTs
│   ├── cert-deploy.yml                # copies certs from primary to CTs (via control node)
│   ├── renew-certs.yml                # forced manual renewal
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

## Makefile — quick commands

The `Makefile` at the project root saves you from remembering playbook paths.

```bash
make deploy        # full deployment (site.yml)
make zones         # update DNS zones only
make acme          # issue/renew certs and distribute them to the CTs
make cert-deploy   # re-copy existing certs to the CTs (without re-issuing)
make renew         # forced manual ACME certificate renewal
make dnssec        # DNSSEC status and upcoming key rotations
make vault-summary # vault variables summary
make ping          # check connectivity to every host
make syntax        # syntax check of site.yml
make snapshot      # Proxmox snapshot of the primary
```

By default it uses `--ask-vault-pass`. For a password file:

```bash
make deploy VAULT="--vault-password-file=/git/.vault_pass"
```

---

## Proxmox — VM provisioning

### Proxmox API token configuration

1. Log into the Proxmox web UI (`https://proxmox.lan:8006`)
2. Go to **Datacenter → Permissions → API Tokens → Add**
3. Configure:
   ```
   User:       ansible@pam
   Token ID:   ansible
   Privilege Separation: NO  ← important
   ```
4. Copy the **Token Secret** shown (visible only once)
5. Add the required permissions:
   ```
   Datacenter → Permissions → Add → API Token Permission
   Path:       /
   Token:      ansible@pam!ansible
   Role:       PVEVMAdmin
   Propagate:  ✓
   ```

6. Save the secret in the vault:
   ```bash
   ansible-vault edit inventory/group_vars/all/vault.yml
   # Update: vault_proxmox_token_secret: "your-token-secret"
   ```

### Enable the snippets storage

The `local` storage on Proxmox must have **Content: Snippets** enabled:

1. **Datacenter → Storage → local → Edit**
2. **Content**: add `Snippets`
3. Save

### Recommended Proxmox VM sizing

| Resource | Minimum | Recommended | Notes |
|---|---|---|---|
| CPU | 1 vCPU | **2 vCPU** | `host` passthrough for AES-NI |
| RAM | 1 GB | **2 GB** | Grafana (~300MB) + Prometheus (~200MB) |
| Disk | 20 GB | **40 GB** | 15GB `/` + 20GB `/var` (Prometheus) |
| Network | 1 NIC | 1 LAN NIC | Bridge `vmbr0`, static IP |
| Machine | q35 | q35 | UEFI + optional TPM |
| BIOS | OVMF | OVMF | UEFI |

> **Disk note**: the hardening role automatically mounts `/tmp`, `/var/tmp` and `/dev/shm` as `tmpfs noexec`. To separate `/var` (recommended for Prometheus), add a second disk to the VM and configure the mount before deploying.

### Step 1 — Create the Debian Trixie template

The playbook connects **to the Proxmox node via SSH**, downloads the Debian Trixie cloud image, installs `qemu-guest-agent` and converts it into a template:

```bash
# First add the Proxmox node to the inventory
# inventory/hosts.yml:
#   all:
#     hosts:
#       proxmox.lan:
#         ansible_user: root

ansible-playbook playbooks/proxmox-prepare-template.yml --ask-vault-pass
```

The playbook is **idempotent**: if template VMID 9000 already exists, it does nothing.

**What gets created:**
- Template VMID `9000`, named `debian-trixie-cloudinit`
- Image optimised with `virt-customize`: qemu-guest-agent, cloud-init, python3
- Machine type q35, host CPU, VirtIO, cloud-init drive

### Step 2 — Primary VM provisioning

```bash
ansible-playbook playbooks/proxmox.yml --ask-vault-pass
```

**Full flow:**

```
1. Check template existence (VMID 9000)
2. Generate cloud-init snippets (user-data + network-config)
3. Upload snippets to Proxmox storage
4. Clone template → VM (VMID 200, full clone)
5. Configure hardware:
   - CPU: host passthrough, 2 cores
   - RAM: 2048MB, ballooning disabled
   - Disk: resize to 40GB
   - Network: VirtIO on vmbr0
   - Tags: dns, primary, ansible-managed
6. Configure cloud-init:
   - static IP, gateway, DNS
   - ansible user with SSH key
   - custom snippet with packages
7. Start the VM and wait for SSH (120s timeout)
8. Wait for cloud-init completion
9. Check qemu-guest-agent via API
10. Create the "post-cloudinit-base" baseline snapshot
11. Print the secondary VPS checklist
```

### Step 3 — Snapshot management

```bash
# List all snapshots
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=list"

# Create a manual snapshot (before the DNS deployment)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-deploy-dns"

# Rollback (with interactive confirmation)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=rollback snap_name=pre-deploy-dns"

# Delete a snapshot
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=delete snap_name=pre-deploy-dns"
```

### Proxmox configuration (`inventory/group_vars/all/main.yml`)

```yaml
# --- API connection ---
proxmox_host: "proxmox.lan"         # Proxmox IP or hostname
proxmox_user: "ansible@pam"
proxmox_token_id: "ansible"
proxmox_node: "pve"                 # node name (pvesh nodes)

# --- Template ---
proxmox_template_vmid: 9000
proxmox_storage: "local-lvm"
proxmox_iso_storage: "local"        # must have Content: Snippets
proxmox_bridge: "vmbr0"

# --- Primary VM ---
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
  - "ssh-ed25519 AAAA... your-public-key"
```

---

## OVH — secondary VMs

OVH VMs work as **public secondaries** alongside (or instead of) Hetzner/Contabo. The `bind9_secondary`, `nftables`, `hardening`, `packages` and `monitoring` roles do not depend on Proxmox: they work on any Debian Trixie reachable over SSH.

> **Provisioning**: unlike the primary on Proxmox (automated VM creation via API), OVH VMs are ordered manually from the OVH panel. Ansible only automates the configuration that follows. For OVH Public Cloud (OpenStack) it is theoretically possible to automate creation too with the `openstack.cloud` collection, but that is out of scope for this project.

### 1. Order the OVH VM

Suitable products for a DNS secondary:
- **OVH VPS** (from ~€3.50/month) — sufficient: 1 vCPU, 2GB RAM
- **OVH Public Cloud** (pay-as-you-go instances)
- **OVH Bare Metal / Eco** (overkill for a secondary, but works)

During the order pick **Debian Trixie (13)** as the operating system and upload your **public SSH key**.

### 2. Configure the OVH firewall (Edge Network Firewall)

This is the most important, OVH-specific step. OVH's Edge Network Firewall has three characteristics you need to understand:

- It is **stateless** and integrated into the Anti-DDoS infrastructure: it only filters traffic coming from **outside** the OVH network. Internal OVH traffic reaches the server on any port anyway.
- It does **not replace** the host firewall: that is why the `nftables` role remains essential (it also protects against internal OVH traffic and applies rate limiting + anti-amplification).
- The **priority logic is inverted**: lower numbers have higher priority, and you **always** need a final explicit deny rule, otherwise the authorize rules alone are ineffective.

Recommended Edge Network Firewall configuration (OVH panel → IP → firewall):

| Priority | Action | Protocol | Port | Option | Notes |
|---|---|---|---|---|---|
| 0 | Authorize | TCP | 22 | — | SSH (ideally from a fixed IP) |
| 1 | Authorize | UDP | 53 | — | DNS queries |
| 2 | Authorize | TCP | 53 | — | large DNS queries + AXFR |
| 3 | Authorize | TCP | — | established | TCP session replies |
| 4 | Authorize | ICMP | — | — | ping / traceroute |
| 19 | Deny | IPv4 | — | — | **mandatory final deny** |

> Being stateless, the OVH firewall does not track connections: the `TCP established` rule (priority 3) is required for replies. DNS over UDP does not need it, since every packet is independent.

> **Anti-DDoS caveat**: during an attack, OVH's automatic mitigation may temporarily throttle DNS traffic towards the VM. Having multiple secondaries across different providers (OVH + Hetzner + ...) mitigates this risk: if one secondary is under mitigation, the others keep answering.

### 3. Add the VM to the inventory

```yaml
# inventory/hosts.yml
dns_secondary:
  hosts:
    ns1:
      ansible_host: 203.0.113.10        # e.g. Hetzner
      ansible_user: ansible
      dns_secondary_index: 1
    ns2-ovh:
      ansible_host: 51.91.x.x           # OVH VM public IP
      ansible_user: ansible
      dns_secondary_index: 2
```

```yaml
# inventory/group_vars/all/main.yml
dns_secondary_ips:
  - "203.0.113.10"
  - "51.91.x.x"          # OVH VM
```

### 4. Deploy

```bash
ansible-playbook playbooks/site.yml --limit dns_secondary --ask-vault-pass
```

### 5. Verify

```bash
# Direct query to the OVH VM
dig @51.91.x.x example.com SOA

# Check the host nftables firewall is active
ansible ns2-ovh -m command -a "nft list ruleset" --ask-vault-pass

# Check the zone transfer received from the primary
ansible ns2-ovh -m command -a "rndc zonestatus example.com" --ask-vault-pass
```

### Primary on OVH (discouraged but possible)

If you want to put the **primary** on OVH too, giving up the local hidden primary, it works but changes the security model: the primary becomes reachable from the internet. In that case:
- The primary role's nftables rules already restrict port 53 to localhost and the secondaries
- In the OVH Edge Firewall open only SSH + port 53 towards the secondaries' IPs
- You lose the main advantage of the hidden primary architecture (master not exposed)

The recommended approach remains: **local primary on Proxmox** + **public secondaries on OVH/Hetzner/etc.**


## Initial setup

### 1. Clone the repository

```bash
git clone https://github.com/mikysal78/ansible-dns.git
cd ansible-dns
pip install ansible-core>=2.16
ansible-galaxy collection install -r requirements.yml
```

### 2. Generate the TSIG keys

```bash
# Zone transfer key (AXFR)
tsig-keygen -a hmac-sha256 axfr-key

# DDNS key (OpenWrt routers + acme.sh)
tsig-keygen -a hmac-sha256 ddns-key
```

### 3. Configure the vault

Copy the `vault.yml.example` template and fill it with real values:

```bash
cp inventory/group_vars/all/vault.yml.example inventory/group_vars/all/vault.yml

# Edit with your secrets (TSIG, passwords, Proxmox token)
$EDITOR inventory/group_vars/all/vault.yml

# Encrypt the file (it will never be committed in cleartext thanks to .gitignore)
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

The required keys are documented in `vault.yml.example`:
`vault_tsig_secret`, `vault_ddns_secret`, `vault_acme_email`,
`vault_grafana_admin_password`, `vault_alertmanager_smtp_password`,
`vault_proxmox_token_secret`.

### 4. Configure the inventory

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

### 5. Add your public SSH key

```yaml
# inventory/group_vars/all/main.yml
cloudinit_ssh_authorized_keys:
  - "ssh-ed25519 AAAA... your-key"

hardening_ssh_authorized_keys:
  - key: "ssh-ed25519 AAAA... your-key"
    user: ansible
```

---

## Configuration

### Main variables (`inventory/group_vars/all/main.yml`)

| Variable | Default | Description |
|---|---|---|
| `dns_domain_base` | `example.com` | Main domain |
| `dns_primary_ip` | `192.168.1.10` | Hidden primary private IP |
| `dns_secondary_ips` | list | Public secondary VPS IPs |
| `dns_tsig_key_name` | `axfr-key` | AXFR TSIG key name |
| `ddns_zone` | `dyn.example.com` | DDNS records zone |
| `proxmox_host` | `proxmox.lan` | Proxmox host |
| `proxmox_primary_vmid` | `200` | Primary VM VMID |
| `proxmox_primary_ip` | `192.168.1.10` | VM static IP |
| `prometheus_retention` | `30d` | Prometheus data retention |
| `alertmanager_smtp_enabled` | `false` | Enable email notifications |

### YAML zone format

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

> ⚠️ **SOA `expire` in DDNS zones**: keep it high (default `1209600` = 14 days)
> even when the zone is dynamic. It is the time after which the *secondaries*
> stop serving the zone if they cannot reach the primary: with a low value
> (e.g. 3600) one hour of tunnel downtime is enough to make the zone vanish
> from the public NS with SERVFAIL. The low TTL for dynamic records is set
> with `ttl`/`minimum`, not with `expire`.

---

## DNS deployment

### Recommended full flow

```bash
# 1. Create the Debian Trixie template on Proxmox (one-off)
ansible-playbook playbooks/proxmox-prepare-template.yml --ask-vault-pass

# 2. Primary VM provisioning
ansible-playbook playbooks/proxmox.yml --ask-vault-pass

# 3. Pre-deploy snapshot (safety)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-deploy-dns"

# 4. Full DNS infrastructure deployment
ansible-playbook playbooks/site.yml --ask-vault-pass

# 5. Verify and publish the DNSSEC DS records at the registrar
ansible-playbook playbooks/dnssec-status.yml --ask-vault-pass
```

### Partial deployment options

```bash
# Primary only
ansible-playbook playbooks/site.yml --limit dns_primary --ask-vault-pass

# Secondaries only
ansible-playbook playbooks/site.yml --limit dns_secondary --ask-vault-pass

# Hardening only
ansible-playbook playbooks/site.yml --tags hardening --ask-vault-pass

# Dry run
ansible-playbook playbooks/site.yml --check --diff --ask-vault-pass
```

### End-of-deploy summary

`site.yml` ends with a summary play showing:

- **INFRASTRUCTURE** — primary IP, public NS1/NS2, WireGuard addresses
- **DNS ZONES** — active zones with type and DDNS status
- **MONITORING** — Grafana/Prometheus/Alertmanager URLs with credentials and a ready-made SSH tunnel command
- **MONITORING SMTP** — email/webhook notification status
- **ACME CERTIFICATES** — files per domain and target CTs
- **CT CONSUMERS** — CT list with cert and reload command
- **VAULT** — encrypted variable values

```bash
# hide sensitive values (useful on shared shells or in CI)
ansible-playbook playbooks/site.yml --ask-vault-pass -e reveal_secrets=false
```

> ⚠️ With `reveal_secrets=true` (the default) passwords are printed in cleartext
> to stdout. Do not run it with your output visible to others. To inspect the
> vault: `ansible-vault view inventory/group_vars/all/vault.yml`.

### Role order in `site.yml`

```
packages → hardening → nftables → bind9_primary → dnssec → acme_dns → monitoring
                                → bind9_secondary (on the secondaries)
```

The secondaries are updated **one at a time** (`serial: 1`): during a deployment — even if a handler restarts BIND or a config is broken — one of the two public NS always stays in service.

Before every BIND reload the full configuration is validated with `named-checkconf`: if it is broken the play fails *before* the reload and named keeps serving with the previous config.

---

## WireGuard tunnel

The primary is a **hidden master on a LAN behind NAT**, with no public IP. The secondaries are on public VPS. Without a path between the two, AXFR could not work (a private IP is not routable on the internet). The solution is an encrypted WireGuard tunnel.

### Topology

The primary (behind NAT) **initiates** the connection towards the secondaries, which have fixed public endpoints. `PersistentKeepalive` keeps the path open through NAT. Once up, the tunnel is bidirectional and AXFR/NOTIFY travel inside it encrypted.

```
Primary (NAT)              Secondaries (public IPs)
10.99.0.1   ──connects──►  10.99.0.2  (ns1, listens :51820)
            ──connects──►  10.99.0.3  (ns2, listens :51820)
            25s keepalive keeps the NAT holes open
```

### Configuration

Every DNS host has an address inside the tunnel, assigned in the inventory:

```yaml
# inventory/hosts.yml
ns-primary:
  ansible_host: 10.0.0.14
  wg_address: 10.99.0.1      # tunnel IP
ns1:
  ansible_host: 203.0.113.10
  wg_address: 10.99.0.2
ns2:
  ansible_host: 203.0.113.20
  wg_address: 10.99.0.3
```

The DNS IPs used for transfers point at the tunnel:

```yaml
# inventory/group_vars/all/main.yml
dns_primary_ip: "10.99.0.1"
dns_secondary_ips:
  - "10.99.0.2"
  - "10.99.0.3"
```

The WireGuard play in `site.yml` runs on the primary and the secondaries **together**, because the template needs every host's public key (via `hostvars`).

### Verify

```bash
# active handshake with both peers?
ssh -p 2400 root@10.0.0.14 "wg show"

# does the primary reach the secondaries inside the tunnel?
ssh -p 2400 root@10.0.0.14 "ping -c2 10.99.0.2"

# does AXFR work through the tunnel?
ssh -p 2400 root@10.0.0.14 "dig @127.0.0.1 example.com AXFR | head"
```

---

## Zone management

### Updates with automatic serial

The playbook computes the serial in `YYYYMMDDnn` format:
- Today's date + existing serial → increments `nn`
- Past date → `YYYYMMDD01`
- Updates **only the zones that changed** (diff before deploy)
- Syntax check with `named-checkzone`
- Checks propagation on the secondaries

```bash
# All zones
ansible-playbook playbooks/update-zones.yml --ask-vault-pass

# A specific zone
ansible-playbook playbooks/update-zones.yml --ask-vault-pass \
  -e "zone_name=example.com"

# Force reload
ansible-playbook playbooks/update-zones.yml --ask-vault-pass \
  -e "force_serial=true"
```

### Adding a zone

1. Create `zones/new-zone.com.yml`
2. Add to `inventory/group_vars/all/main.yml`:
   ```yaml
   dns_zones:
     - name: "new-zone.com"
       file: "zones/new-zone.com.yml"
       type: master
       ddns_enabled: false
   ```
3. `ansible-playbook playbooks/update-zones.yml --ask-vault-pass`

### TLSA (DANE)

Every zone supports a `tlsa` list (see `zones/example.com.yml`). With `usage: 3, selector: 1, matching: 1` (DANE-EE of the public key) the hash is derived from the acme.sh certificate in use:

```bash
openssl x509 -in /etc/ssl/acme/<domain>.fullchain.pem -noout -pubkey \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256
```

Recommended records for a web+mail host (same certificate, same hash on every port):

| Owner name              | Service           | Why |
|--------------------------|-------------------|-----|
| `_443._tcp.www`          | HTTPS             | standard web certificate validation |
| `_25._tcp.mail`          | SMTP (MTA-to-MTA) | STARTTLS is opportunistic and vulnerable to downgrade/stripping; the TLSA record (RFC 7672) forces DANE-capable senders (Postfix `smtp_tls_security_level=dane`, Exim, etc.) to refuse cleartext delivery instead of silently degrading |
| `_587._tcp.mail`         | Submission        | implicit/mandatory TLS |
| `_465._tcp.mail`         | SMTPS             | implicit TLS |
| `_993._tcp.mail`         | IMAPS             | implicit TLS |
| `_995._tcp.mail`         | POP3S             | implicit TLS |

Do not publish TLSA on client-side STARTTLS ports (`_110._tcp`, `_143._tcp`, cleartext POP3/IMAP): mail clients do not validate DANE on those ports, unlike MTAs delivering SMTP — it would be a record with no practical effect.

If the certificate key changes (a new keypair, not just a renewal with the same key), the hash must be regenerated and redistributed to every owner name that references it.

---

## DNSSEC

### Automatic configuration

BIND 9.20 with `dnssec-policy` handles everything:

| Parameter | Value | Notes |
|---|---|---|
| Algorithm | Ed25519 | 32-byte keys |
| KSK lifetime | 1 year | Automatic rotation |
| ZSK lifetime | 90 days | Automatic rotation |
| NSEC3 iterations | 0 | RFC 9276 |
| Signature validity | 14 days | Renewed 3 days early |

### DS records — what they are and where they go

The **DS record** (Delegation Signer) is a hash of your KSK (Key Signing Key). It must be entered in the **registrar's panel** where the domain is registered (Aruba, Register.it, Namecheap, etc.), in the "DNSSEC" or "DS Records" section. It creates the **chain of trust**: without it DNSSEC is configured but not verifiable by public resolvers.

> **Exception**: subdomain zones (e.g. `dyn.example.com`) do not go to the registrar. Their DS record is managed automatically by BIND inside the parent zone (`example.com`).

### How to get the DS records

```bash
make dnssec
```

The playbook prints, for each zone:

```
ninux-nnxx.it. IN DS 24729 15 2 B73CAF4FE07BE64E...
```

The fields to enter at the registrar are:

| Registrar field | Where to find it in the output |
|---|---|
| **Key Tag** (or Key ID) | first number after `DS` — e.g. `24729` |
| **Algorithm** | second number — `15` = Ed25519 |
| **Digest Type** | third number — `2` = SHA-256 |
| **Digest** | final hexadecimal string |

### Entering it at the registrar

Every registrar has a different interface, but the fields are always the same. Example for a domain using Ed25519:

| Field | Example value |
|---|---|
| Key Tag | `24729` |
| Algorithm | `15` |
| Digest Type | `2` |
| Digest | `B73CAF4FE07BE64E29EB7A57ABBC791D757CC5B8B0790B4DCE532352765EF729` |

Propagation usually takes 1–24 hours (depending on the TLD registry TTL).

### Chain of trust verification

```bash
# End-to-end chain of trust (after DS propagation at the registrar)
delv @8.8.8.8 example.com SOA +rtrace
# Expected output: "; fully validated"

# Local signing (without waiting for propagation)
dig +dnssec example.com SOA @ns1.example.com

# DNSSEC key status and upcoming rotations
make dnssec
```

### Key rotation (automatic)

BIND rotates KSK and ZSK automatically according to the policy. When a **KSK rotation** happens you must update the DS record at the registrar with the new Key Tag. The `make dnssec` playbook always shows the active DS record to publish.

---

## DDNS — OpenWrt routers

The router updates its own A record automatically every 5 minutes:

```
router-home.dyn.example.com.  60  IN  A  <public WAN IP>
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

The script automatically detects CGNAT and obtains the real public IP.

---

## Monitoring

### Access via SSH tunnel

Grafana, Prometheus and Alertmanager listen only on the primary's `127.0.0.1` (private LAN IP, not exposed to the internet). The hardening role enables `PermitOpen` only for the monitoring ports.

```bash
# Open the tunnel from your laptop (stays in the background with -N)
ssh -p 2400 -N \
    -L 3000:127.0.0.1:3000 \
    -L 9090:127.0.0.1:9090 \
    -L 9093:127.0.0.1:9093 \
    root@<primary-ip>

# Grafana:      http://localhost:3000   (admin / vault_grafana_admin_password)
# Prometheus:   http://localhost:9090
# Alertmanager: http://localhost:9093
```

The exact SSH tunnel command (with the real IP) is printed at the end of every `make deploy` in the **MONITORING — access** section.

> If the primary is not directly reachable from your laptop, jump via Proxmox:
> ```bash
> ssh -J root@<proxmox-ip> -p 2400 -N \
>     -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 \
>     root@<primary-ip>
> ```

> **Firewall**: if you cannot connect even with the tunnel open, add your IP to `monitoring_allowed_sources` in `group_vars/all/main.yml` and re-run `make deploy`.

### Preconfigured alerts

| Alert | Severity | Condition |
|---|---|---|
| `BINDDown` | critical | bind_exporter unresponsive for 2+ min |
| `BINDQueryRateCritical` | critical | > 20,000 queries/s |
| `BINDSerialMismatch` | warning | serial misaligned across nodes |
| `DNSSECKeyExpiredCritical` | critical | DNSSEC key expires in < 24h |
| `NodeDown` | critical | server unreachable |
| `DiskSpaceCritical` | critical | < 5% free space |
| `NTPOffsetHigh` | warning | offset > 100ms |
| *(+7 more)* | | |

### Email notifications

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

### Active modules

| Module | Description |
|---|---|
| `user` | Creates the ansible user, loads SSH keys, locks root |
| `ssh` | chacha20/AES-GCM, curve25519, no password auth |
| `sysctl` | 25+ kernel hardening parameters |
| `filesystem` | `/tmp` noexec, no core dumps, sensitive file permissions |
| `services` | Disables 10+ unneeded daemons |
| `sudo` | Full logging, use_pty, requiretty |
| `auditd` | CIS rules for DNS files, critical syscalls |
| `banner` | Pre-login banner + dynamic MOTD |
| `fail2ban` | SSH jail + DNS flood jail with nftables |
| `rkhunter` | Nightly scan, weekly DB update |
| `unattended_upgrades` | Security patches only, bind9 blacklisted |

---

## nftables firewall

### Primary (hidden master)

```
INPUT:  loopback, established, rate-limited ICMP, SSH, UDP/53 secondaries+localhost only
OUTPUT: throttle UDP > 512B per IP (anti-amplification)
RAW:    bogon anti-spoofing, UDP/53 conntrack bypass
```

### Secondaries (public VPS)

```
INPUT:  public UDP/53 rate-limited (30pps/IP, 120s ban), rate-limited TCP/53,
        unlimited AXFR TCP from the primary, rate-limited SSH
OUTPUT: throttle UDP > 512B (anti-amplification, dynamic set amp_targets)
```

### Useful commands

```bash
# IPs banned for DNS flooding
nft list set inet filter dns_flood

# Unban an IP manually
nft delete element inet filter dns_flood { 1.2.3.4 }

# Full ruleset
nft list ruleset
```

---

## ACME certificates

### How it works

1. acme.sh on the primary obtains the wildcard certificates (`*.example.com` + apex) via DNS-01 challenge using `nsupdate` with the `ddns-key` TSIG key
2. On renewal (02:30 cron) or first deployment, the primary copies the certificates to the consumer CTs over SSH (dedicated ed25519 key)
3. After the copy, the CT runs the configured `reload_cmd` (nginx, postfix, dovecot…)

### Configuring domains and target CTs

```yaml
# inventory/group_vars/all/main.yml
acme_deploy_key: "/root/.ssh/acme_deploy_id_ed25519"
acme_deploy_ssh_port: 2400   # CT SSH port

acme_domains:
  - domain: "example.com"
    keylength: "ec-256"
    deploy:
      - host: "10.0.0.16"          # nginx CT
        reload_cmd: "systemctl reload nginx"
  - domain: "other.com"
    keylength: "ec-256"
    deploy:
      - host: "10.0.0.6"           # mail CT
        reload_cmd: "systemctl reload postfix && systemctl reload dovecot"
```

```yaml
# inventory/hosts.yml — cert_consumers group
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
      cert_domain: "other.com"
      cert_reload_cmd: "systemctl reload postfix && systemctl reload dovecot"
```

### Commands

```bash
# Issue/renew certs AND distribute them to the CTs (single run)
make acme

# Only re-copy already-issued certs to the CTs (without re-issuing)
make cert-deploy

# Forced manual renewal
make renew

# Check the automatic renewal logs on the primary
ssh -p 2400 root@<primary-ip> "tail -50 /var/log/acme-renew.log"
```

### Troubleshooting

```bash
# Force a manual renewal of a single domain
ssh -p 2400 root@<primary-ip> \
  "/opt/acme.sh/acme.sh --renew -d example.com --force --home /opt/acme.sh"

# Check the certs reached the CT
ssh -p 2400 root@<ct-ip> "ls -la /etc/ssl/acme/"
ssh -p 2400 root@<ct-ip> \
  "openssl x509 -noout -subject -enddate -in /etc/ssl/acme/example.com.fullchain.pem"
```

---

## CI/CD

### GitHub Actions pipeline

```
push → lint (yamllint + ansible-lint)
     → syntax (every playbook)
     → molecule (Docker Debian Trixie: prepare → converge → idempotency → verify)
     → validate-zones (validates YAML zone files)
     → security (trivy CVE + encrypted-vault check)

tag vX.Y.Z → release (archive + automatic changelog)
```

### Local testing

```bash
yamllint .
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check \
  -i inventory/hosts.yml -e @inventory/group_vars/all/main.yml \
  -e "vault_tsig_secret=test vault_ddns_secret=test vault_proxmox_token_secret=test"
molecule test
```

---

## Day-to-day operations

```bash
# Update DNS zones
make zones

# DNSSEC status + DS records
make dnssec

# Snapshot before a risky operation
make snapshot

# Re-copy certificates to the CTs (after a manual renewal or a new VM)
make cert-deploy

# Check connectivity to every host
make ping
```

Useful direct commands:

```bash
# BIND status on every node
ansible all -m command -a "systemctl status bind9" --ask-vault-pass

# Current zone serials
ansible dns_primary -m command \
  -a "rndc zonestatus example.com" --ask-vault-pass

# Force a zone transfer on the secondaries
ansible dns_secondary -m command \
  -a "rndc retransfer example.com" --ask-vault-pass

# IPs banned for DNS flooding
ansible dns_secondary -m command \
  -a "nft list set inet filter dns_flood" --ask-vault-pass

# Certificate renewal log
ssh -p 2400 root@<primary-ip> "tail -50 /var/log/acme-renew.log"

# Snapshot with a custom name
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-maintenance"
```

### Upgrading BIND9

```bash
# Test on a secondary first
ansible ns1 -m apt -a "name=bind9 state=latest" --ask-vault-pass
ansible ns1 -m command -a "systemctl restart bind9" --ask-vault-pass
dig @203.0.113.10 example.com SOA

# Then the primary (snapshot first)
ansible-playbook playbooks/proxmox-snapshot.yml \
  --ask-vault-pass -e "snap_action=create snap_name=pre-bind9-upgrade"
ansible dns_primary -m apt -a "name=bind9 state=latest" --ask-vault-pass
ansible dns_primary -m command -a "systemctl restart bind9" --ask-vault-pass

# Finally the remaining secondaries
ansible dns_secondary -m apt -a "name=bind9 state=latest" --ask-vault-pass
```

---

## Troubleshooting

### BIND9 does not start

```bash
journalctl -u bind9 -n 50 --no-pager
named-checkconf /etc/bind/named.conf
named-checkzone example.com /var/lib/bind/zones/db.example.com
```

### Zone transfers do not work

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

### ACME certificates not renewing

```bash
/opt/acme.sh/acme.sh --renew -d example.com --force
cat /var/log/acme-renew.log
```

### Proxmox — clone fails

```bash
# Check the template exists
qm status 9000

# Check API token permissions
pvesh get /access/acl

# Proxmox logs
journalctl -u pvedaemon -n 50
```

### Proxmox — cloud-init does not apply the IP

```bash
# Check cloud-init status on the VM
ssh -p 2400 root@10.0.0.14 "cloud-init status"
ssh -p 2400 root@10.0.0.14 "cat /var/log/cloud-init.log | tail -30"

# Regenerate the cloud-init image and reboot
qm set 200 --cicustom ""
qm cloudinit update 200
qm reboot 200
```

### VM unresponsive after creation

```bash
# Check VM status
qm status 200

# VM console on Proxmox
qm terminal 200

# Boot log
qm showcmd 200
```

---

## Security

### Secrets management

All secrets live in `inventory/group_vars/all/vault.yml`, encrypted with ansible-vault. The cleartext file must never be committed. `.gitignore` excludes the unencrypted vault.

```bash
# Check the vault is encrypted
head -1 inventory/group_vars/all/vault.yml
# Expected output: $ANSIBLE_VAULT;1.1;AES256
```

### TSIG key rotation

```bash
tsig-keygen -a hmac-sha256 axfr-key-new
ansible-vault edit inventory/group_vars/all/vault.yml
ansible-playbook playbooks/site.yml --ask-vault-pass
dig @192.168.1.10 example.com AXFR   # verify
```

### Proxmox API token rotation

1. Create a new token in Proxmox
2. Update `vault_proxmox_token_secret` in the vault
3. Run `ansible-playbook playbooks/proxmox.yml --ask-vault-pass` to verify
4. Revoke the old token

---

## Changelog

The [CHANGELOG](CHANGELOG.md) is maintained in Italian, the project's native language.

---

## License

MIT — see [LICENSE](LICENSE)

---

## Contributing

1. Fork the repository
2. Branch: `git checkout -b feature/name`
3. Test: `yamllint . && ansible-lint && molecule test`
4. Commit: `git commit -m "feat: description"`
5. Pull request against `main`

Issues and PRs are welcome in English or Italian.
All contributions must pass the full CI pipeline before merging.

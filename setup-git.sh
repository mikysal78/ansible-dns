#!/usr/bin/env bash
# ============================================================
# setup-git.sh
# Inizializza il repo git e fa il primo commit su GitHub
# Uso: bash setup-git.sh
# ============================================================

set -euo pipefail

REPO_NAME="ansible-dns"
GITHUB_USER="mikysal78"
REMOTE_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
# Alternativa HTTPS (se non hai SSH configurato):
# REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo "============================================================"
echo " Inizializzazione repo: ${REPO_NAME}"
echo " Remote: ${REMOTE_URL}"
echo "============================================================"

# --- Verifica che vault.yml sia cifrato ---
if [ -f "group_vars/all/vault.yml" ]; then
  if ! head -1 group_vars/all/vault.yml | grep -q '\$ANSIBLE_VAULT'; then
    echo ""
    echo "⛔  ERRORE: group_vars/all/vault.yml NON è cifrato!"
    echo "   Esegui prima: ansible-vault encrypt group_vars/all/vault.yml"
    exit 1
  fi
  echo "✓ vault.yml cifrato correttamente"
fi

# --- Git init ---
git init
git config user.name  "mikysal78"
git config user.email "mikysal78@users.noreply.github.com"  # aggiorna con la tua email

# --- .gitignore già presente, verifica ---
echo "✓ .gitignore presente"

# --- Stage tutti i file (vault.yml è cifrato, sicuro) ---
git add .

# --- Verifica cosa sta per essere committato ---
echo ""
echo "File in staging:"
git status --short
echo ""

# --- Primo commit ---
git commit -m "feat: initial release — DNS infrastructure as code

Infrastruttura DNS production-ready con:
- BIND9 hidden primary + N secondari pubblici
- DNSSEC inline signing (Ed25519, dnssec-policy)
- Hardening OS (SSH, sysctl, auditd, fail2ban, rkhunter)
- Firewall nftables con anti-amplification e rate limiting
- Certificati wildcard via acme.sh DNS-01
- DDNS per router OpenWrt via nsupdate TSIG
- Monitoring: Prometheus + Grafana + Alertmanager
- Provisioning VM Proxmox via API con cloud-init
- CI/CD: ansible-lint + Molecule + GitHub Actions
- README completo in italiano (993 righe)

Tested on: Debian Trixie, BIND 9.20, Proxmox VE 8.x"

# --- Imposta branch main ---
git branch -M main

# --- Aggiungi remote ---
git remote add origin "${REMOTE_URL}"

echo ""
echo "============================================================"
echo " Pronto per il push. Esegui:"
echo ""
echo "   git push -u origin main"
echo ""
echo " Se è il tuo primo push SSH, verifica la chiave con:"
echo "   ssh -T git@github.com"
echo "============================================================"

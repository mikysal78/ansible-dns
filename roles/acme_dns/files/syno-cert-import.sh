#!/bin/bash
# ============================================================
# syno-cert-import.sh
# Importa/aggiorna il certificato wildcard ninux-nnxx.it nello
# store certificati di DSM. Eseguito come root via sudo NOPASSWD
# da michele; i file (fullchain + privkey) arrivano dal primary
# nella dir STAGE tramite il deploy hook di acme.sh.
# NON modificare manualmente: gestito da Ansible (roles/acme_dns).
# ============================================================
set -euo pipefail

STAGE=/tmp/nnxx-cert-stage
ARCH=/usr/syno/etc/certificate/_archive
ID=nnxxWc                       # cartella archive del wildcard ninux-nnxx.it

FC="$STAGE/fullchain.pem"
KEY="$STAGE/privkey.pem"

[ -s "$FC" ] && [ -s "$KEY" ] || { echo "ERRORE: manca fullchain/privkey in $STAGE"; exit 1; }
[ -d "$ARCH/$ID" ] || { echo "ERRORE: archive $ID inesistente"; exit 1; }

# La chiave deve combaciare con il leaf
cpub=$(openssl x509 -in "$FC" -noout -pubkey | openssl md5)
kpub=$(openssl pkey -in "$KEY" -pubout | openssl md5)
[ "$cpub" = "$kpub" ] || { echo "ERRORE: chiave e certificato non combaciano"; exit 1; }

# Split: cert.pem = primo blocco (leaf), chain.pem = blocchi successivi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
awk -v c="$tmp/cert.pem" -v ch="$tmp/chain.pem" '
  /BEGIN CERTIFICATE/{n++}
  { if (n==1) print > c; else print > ch }' "$FC"
cp "$FC" "$tmp/fullchain.pem"
cp "$KEY" "$tmp/privkey.pem"

for f in cert.pem chain.pem fullchain.pem privkey.pem; do
  install -m 400 -o root -g root "$tmp/$f" "$ARCH/$ID/$f"
done

# Rigenera i bundle DSM e ricarica i servizi web (se il cert e' assegnato)
/usr/syno/bin/synow3tool --gen-all >/dev/null 2>&1 || true
/usr/syno/bin/synosystemctl restart nginx >/dev/null 2>&1 || true

# Pulizia staging (rimuove la chiave privata)
rm -f "$STAGE"/*.pem 2>/dev/null || true

echo "syno-cert-import OK: ninux-nnxx.it scade $(openssl x509 -in "$ARCH/$ID/cert.pem" -noout -enddate | cut -d= -f2)"

#!/usr/bin/env bash
# ============================================================
# show-dns.sh — dump di tutti i record di una zona DNS
#
# Il primary è un hidden master (allow-query { localhost; secondaries })
# e sulla LAN un dnsmasq intercetta la porta 53: interrogarlo dalla
# workstation NON funziona. Quindi lo script si collega in SSH al primary
# ed esegue lì un AXFR (zone transfer) su localhost autenticato con la
# TSIG key axfr-key — l'unico modo per enumerare TUTTI i record.
#
# Uso:
#   ./show-dns.sh -d romaclubmatera.it
#   ./show-dns.sh -d ninux-nnxx.it -t A        # solo record A
#   ./show-dns.sh -d dyn.ninux-nnxx.it -D      # includi record DNSSEC
#   ./show-dns.sh -l                           # elenca le zone servite
#
# Override (env var o flag):
#   PRIMARY_HOST (-H)  default 10.27.22.14   IP/host del primary
#   SSH_PORT     (-p)  default 2400          porta SSH del primary
#   SSH_USER           default root          utente SSH
#   KEYFILE            default /etc/bind/tsig-axfr.key   TSIG key sul primary
# ============================================================
set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-10.27.22.14}"
SSH_PORT="${SSH_PORT:-2400}"
SSH_USER="${SSH_USER:-root}"
KEYFILE="${KEYFILE:-/etc/bind/tsig-axfr.key}"
CONNECT_TIMEOUT=8

ZONE=""
TYPE=""
WITH_DNSSEC=0
LIST_ZONES=0

# Colori solo se stdout è un terminale
if [ -t 1 ]; then
    C_HDR=$'\033[1;36m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_HDR=""; C_DIM=""; C_RST=""
fi

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

err() { printf '%s\n' "errore: $*" >&2; }

# --- parsing argomenti ---
while getopts ":d:t:H:p:Dlh" opt; do
    case "$opt" in
        d) ZONE="$OPTARG" ;;
        t) TYPE="$(printf '%s' "$OPTARG" | tr '[:lower:]' '[:upper:]')" ;;
        H) PRIMARY_HOST="$OPTARG" ;;
        p) SSH_PORT="$OPTARG" ;;
        D) WITH_DNSSEC=1 ;;
        l) LIST_ZONES=1 ;;
        h) usage 0 ;;
        :) err "l'opzione -$OPTARG richiede un argomento"; usage 1 ;;
        \?) err "opzione sconosciuta: -$OPTARG"; usage 1 ;;
    esac
done

# Esegue un comando sul primary via SSH (banner/motd soppressi: -q + stderr scartato)
on_primary() {
    ssh -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout="$CONNECT_TIMEOUT" \
        -p "$SSH_PORT" "$SSH_USER@$PRIMARY_HOST" "$@" 2>/dev/null
}

# --- modalità: elenco zone ---
if [ "$LIST_ZONES" -eq 1 ]; then
    printf '%sZone servite dal primary (%s):%s\n' "$C_HDR" "$PRIMARY_HOST" "$C_RST"
    if ! on_primary "grep -oE 'zone \"[^\"]+\"' /etc/bind/named.conf.local | sed 's/zone \"//;s/\"//' | sort -u"; then
        err "impossibile raggiungere il primary $PRIMARY_HOST:$SSH_PORT via SSH"
        exit 2
    fi
    exit 0
fi

if [ -z "$ZONE" ]; then
    err "specificare la zona con -d <zona>  (es. -d romaclubmatera.it)"
    usage 1
fi

# --- AXFR ---
raw="$(on_primary "dig +noall +answer +time=5 @localhost AXFR $(printf '%q' "$ZONE") -k $(printf '%q' "$KEYFILE")")" || {
    err "impossibile raggiungere il primary $PRIMARY_HOST:$SSH_PORT via SSH"
    exit 2
}

# Nessuna riga SOA = trasferimento fallito (zona inesistente, key errata, ecc.)
if ! printf '%s\n' "$raw" | grep -qiE '[[:space:]]SOA[[:space:]]'; then
    err "AXFR fallito per '$ZONE' — zona inesistente o trasferimento negato"
    printf '%s\n' "$raw" | grep -iE 'transfer failed|timed out|not found|REFUSED' >&2 || true
    exit 3
fi

# --- filtri ---
# Il tipo di record è il 4° campo: <name> <ttl> <class> <TYPE> <rdata...>
records="$raw"
if [ "$WITH_DNSSEC" -eq 0 ]; then
    records="$(printf '%s\n' "$records" \
        | awk '$4 !~ /^(RRSIG|DNSKEY|NSEC|NSEC3|NSEC3PARAM|CDS|CDNSKEY|TYPE65534)$/')"
fi
if [ -n "$TYPE" ]; then
    records="$(printf '%s\n' "$records" | awk -v t="$TYPE" '$4 == t')"
fi

# Dedup (l'AXFR ripete il SOA in testa e in coda) e rimozione righe vuote
records="$(printf '%s\n' "$records" | awk 'NF' | sort -u)"

# --- output ---
serial="$(printf '%s\n' "$raw" | awk '$4=="SOA"{print $7; exit}')"
count="$(printf '%s\n' "$records" | grep -c . || true)"

printf '%szona:%s   %s\n' "$C_HDR" "$C_RST" "$ZONE"
printf '%sserial:%s %s   %ssource:%s %s (AXFR via SSH)\n' \
    "$C_HDR" "$C_RST" "$serial" "$C_DIM" "$C_RST" "$PRIMARY_HOST"
printf '%srecord:%s %s%s%s\n\n' "$C_HDR" "$C_RST" "$count" \
    "${TYPE:+  (tipo=$TYPE)}" "$([ "$WITH_DNSSEC" -eq 1 ] && echo '  (DNSSEC incl.)' || echo '')"

if [ "$count" -eq 0 ]; then
    err "nessun record corrisponde ai filtri"
    exit 0
fi

# Ordina per tipo poi per nome, e allinea SOLO i primi campi (name/ttl/type),
# tenendo l'rdata intatto (TXT/TLSA/SRV hanno spazi nell'rdata).
printf '%s\n' "$records" | sort -k4,4 -k1,1 | awk '
    { lines[NR]=$0; if (length($1) > w1) w1 = length($1) }
    END {
        if (w1 > 44) w1 = 44
        for (i = 1; i <= NR; i++) {
            $0 = lines[i]
            rd = ""
            for (j = 5; j <= NF; j++) rd = rd (j > 5 ? " " : "") $j
            printf "%-*s  %5s  %-6s  %s\n", w1, $1, $2, $4, rd
        }
    }'

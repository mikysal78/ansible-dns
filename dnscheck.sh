#!/bin/bash

DOMAIN="$1"

if [ -z "$DOMAIN" ]; then
    echo "Uso: $0 dominio.tld"
    exit 1
fi

echo "=== DNS records per $DOMAIN ==="
echo

RECORDS=(
    A
    AAAA
    MX
    NS
    TXT
    CNAME
    SOA
    SRV
    CAA
    PTR
    ANY
)

for TYPE in "${RECORDS[@]}"; do
    echo "----- $TYPE -----"
    dig +nocmd "$DOMAIN" "$TYPE" +noall +answer
    echo
done

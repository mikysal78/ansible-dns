#!/bin/bash

DOMAIN="$1"

SUBS=(
    www
    mail
    webmail
    ftp
    ns1
    ns2
    vpn
    api
    dev
    test
    mx
    imap
    pop3
    smtp
)

for SUB in "${SUBS[@]}"; do
    HOST="$SUB.$DOMAIN"

    RESULT=$(dig +short "$HOST")

    if [ -n "$RESULT" ]; then
        echo "[$HOST]"
        echo "$RESULT"
        echo
    fi
done

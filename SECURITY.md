# Security Policy

Questo repository contiene playbook Ansible per un'infrastruttura DNS
production (BIND9 hidden primary, DNSSEC, WireGuard, ACME, hardening OS).
Nessun segreto reale (vault, chiavi TSIG, inventory) è incluso nel
repository: solo template `.example` e valori placeholder.

## Segnalare una vulnerabilità

Se trovi un problema di sicurezza (es. un bug nei ruoli che espone un
servizio non previsto, una configurazione firewall/TSIG errata, o una
falla nella logica DNSSEC/ACME), **non aprire una issue pubblica**.

Usa invece uno di questi canali privati:

- **GitHub Security Advisories** — tab "Security" → "Report a vulnerability" di questo repository (preferito, permette una discussione privata prima della pubblicazione)
- **Email**: mikysal78@gmail.com

Includi, se possibile:
- ruolo/playbook coinvolto e versione (tag o commit)
- impatto atteso (es. esposizione di BIND fuori da loopback/WireGuard, bypass ACL, leak di secret)
- passi per riprodurre

## Cosa aspettarsi

- Conferma di ricezione entro pochi giorni
- Una fix o una mitigazione documentata nel `CHANGELOG.md` una volta risolta
- Nessun bug bounty: questo è un progetto personale, non un servizio commerciale

## Versioni supportate

Essendo infrastruttura-as-code applicata a un singolo ambiente reale,
non esiste un concetto di "versioni multiple supportate": solo l'ultimo
tag su `main` riceve fix di sicurezza.

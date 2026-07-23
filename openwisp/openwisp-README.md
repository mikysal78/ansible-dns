# Template OpenWISP 2 — DDNS via nsupdate (TSIG)

Ogni router OpenWrt registra il proprio record A nella zona dinamica del primary
BIND tramite `nsupdate` con chiave TSIG. Lo script di update è sempre lo stesso
(`/usr/lib/ddns/update_nsupdate.sh`, fa `delete + add` in un'unica transazione);
cambia **chi lo lancia** e **quale IP** registra.

## Due varianti

| File | IP registrato | Motore | A cosa serve |
|---|---|---|---|
| `openwisp-ddns-lan-template.json` | **IP di management** (`br-lan`) | **cron** | nome host per l'accesso **LuCI**; IP privato ma instradato in tutta NINUX via Babel |
| `openwisp-ddns-template.json` | **IP pubblico WAN** (via `icanhazip` se dietro NAT/CGNAT) | ddns-scripts | raggiungere il router da Internet |

Stessa zona, stessa chiave TSIG. **Hostname**: la variante cron usa il **nome
puro** del device (`<nome>.<zona>`), la variante ddns-scripts usa
`router-<nome>.<zona>`. Applica **una sola** variante per device.

> La variante `br-lan` è caricata su OpenWISP (org Basilicata) come
> **"DDNS nsupdate (br-lan / LuCI)"**, **non** *enabled by default*. Perché
> funzioni servono: (1) il `ddns_secret` reale nei Default Values, (2) il primary
> con la zona `dyn` in `allow-update { key ddns-key }`, (3) BIND raggiungibile
> dai router sulla LAN (`dns_primary_lan_ip` + `ddns_allowed_sources` con il CIDR
> `10.27.0.0/16` — vedi `group_vars/all/main.yml`).

---

## Variante consigliata: `openwisp-ddns-lan-template.json` (cron)

Backend = **OpenWRT**, Type = *Generic*. Spinge come *additional files*:

- `/usr/lib/ddns/update_nsupdate.sh` (0755) — legge l'IP di `br-lan` e fa
  `nsupdate` (`update delete … A` + `update add … A`) verso il primary.
- `/etc/ddns/ddns.key` (0600) — chiave TSIG.
- `/etc/crontabs/root` (0600) — `*/{{ ddns_cron_minutes }} * * * *` che lancia lo
  script.
- `/etc/uci-defaults/99-install-ddns` (0755) — installa `bind-client` (nsupdate)
  con **apk _o_ opkg** e avvia `cron` (eseguito al boot).

### Variabili (Default Values)

| Variabile | Default | Note |
|---|---|---|
| `ddns_zone` | `dyn.ninux-nnxx.it` | zona dinamica sul primary |
| `dns_primary_ip` | `10.27.22.14` | IP LAN del primary BIND (listen-on + firewall aperti alla LAN) |
| `ddns_interface` | `br-lan` | interfaccia di cui registrare l'IP (device name, es. `br-lan`) |
| `ddns_ttl` | `60` | TTL del record A |
| `ddns_key_name` | `ddns-key` | deve combaciare con la key sul primary |
| `ddns_algorithm` | `hmac-sha256` | algoritmo TSIG |
| `ddns_secret` | `CHANGEME…` | **segreto TSIG** — impostare il valore reale (in chiaro nel config del device) |
| `ddns_cron_minutes` | `5` | ogni quanti minuti gira l'update |

L'hostname **non** è una variabile: è `{{ name }}.{{ ddns_zone }}`, dove `name`
è il nome del device in OpenWISP. Nominali in modo coerente (es. `matera`,
`salandra`).

### Comportamento

Il `delete + add` in un'unica transazione rende l'update **idempotente**:

- **IP invariato** → BIND calcola diff nullo = **no-op** (nessun bump del serial,
  nessun AXFR ai secondari): zero churn anche girando ogni 5 min.
- **IP cambiato** → il record segue il nuovo IP.
- **Record perso** (reset zona, cancellazione) → **self-heal** entro ≤ `ddns_cron_minutes`.

### Attivazione (importante)

`openwisp-config` **posa** i file ma non li **esegue**: l'`uci-defaults`
(installa `bind-client` + avvia cron) parte **al boot**. Quindi sul primo apply
di un router serve **un reboot** — oppure un kick manuale una tantum:

```sh
# su router apk (OpenWrt 24.10+/25.x)
apk add bind-client && /etc/init.d/cron enable && /etc/init.d/cron restart
# su router opkg (23.05 e precedenti)
opkg update && opkg install bind-client && /etc/init.d/cron enable && /etc/init.d/cron restart
```

### Perché cron e non ddns-scripts

Provato sul campo (OpenWrt 25.12 / apk, ddns-scripts 2.8.3): la strada
ddns-scripts richiede troppi workaround per registrare un **IP privato fisso**:

1. `service_name 'custom'` → in 2.8.3 fa cercare una service-definition
   inesistente e **ignora `update_script`** (*"No update_url/update_script"*).
2. IP privato **rifiutato** senza `config ddns 'global' / option upd_privateip '1'`.
3. `uci-defaults` con solo `opkg` **fallisce** sui router apk.
4. `/etc/config/ddns` applicato via `uci import` è **additivo**: le opzioni tolte
   dal template non vengono rimosse dal router (trappola di `service_name`).
5. Lo **stato** di ddns-scripts non ripristina rapidamente un record perso.

Il cron è stateless e li evita tutti. Unico vantaggio che si perde: la pagina di
stato DDNS in **LuCI** (che qui non serve).

---

## Variante alternativa: `openwisp-ddns-template.json` (ddns-scripts, IP pubblico)

Registra l'IP **pubblico** della WAN (fallback `icanhazip` dietro NAT), utile per
raggiungere il router da Internet. Usa il framework `ddns-scripts`
(`/etc/config/ddns` con `update_script`).

> ⚠️ **Non testata sul fleet attuale.** Su router **apk** / ddns-scripts 2.8.3
> richiede gli stessi fix visti sopra (togliere `service_name`, `uci-defaults`
> apk+opkg). L'IP pubblico non ha il problema `upd_privateip`.

Variabili aggiuntive rispetto alla variante cron: `ddns_section` (`ninux`),
`ddns_check_interval` (`300`), `ddns_force_interval` (`72`).

---

## Come importarlo

1. *Templates* → *Add template*: Name a piacere, Backend = **OpenWRT**.
2. Editor JSON (Advanced mode) → incolla il contenuto di `config`.
3. Incolla `default_values` nel campo **Default Values** e imposta `ddns_secret`.
4. Assegna il template al device (o *Enabled by default* per i nuovi).

## Verifica

Il primary **non** risponde alle query dai router (`allow-query { localhost;
secondaries; }`): verifica sui **secondari** o via risoluzione pubblica.

```sh
dig +short @135.125.196.114 <nome>.dyn.ninux-nnxx.it A   # ns1
dig +short <nome>.dyn.ninux-nnxx.it A                     # risoluzione pubblica
```

Sul router: `logread | grep -i ddns` (riga `Aggiornamento <nome> -> <ip>`) e
`crontab -l`.

## Coerenza con Ansible

Il primary è gestito da Ansible (`bind9_primary`): zona `dyn` con `allow-update`
per `ddns-key`. Un router va gestito **o** da `ddns_openwrt` (Ansible) **o** da
questo template OpenWISP, mai da entrambi. Nota: anche il ruolo `ddns_openwrt` è
ddns-scripts + IP pubblico e, su router apk, richiederebbe gli stessi fix.

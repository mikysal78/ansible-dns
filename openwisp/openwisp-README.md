# Template OpenWISP 2 — DDNS via nsupdate (TSIG)

Porta su OpenWISP la stessa configurazione DDNS del ruolo Ansible `ddns_openwrt`:
ogni router OpenWrt registra il proprio record A nella zona dinamica del primary
BIND tramite `nsupdate` con chiave TSIG.

## Due varianti

| File | IP registrato | A cosa serve |
|---|---|---|
| `openwisp-ddns-template.json` | **IP pubblico WAN** (via `icanhazip` se la WAN è privata/CGNAT) | raggiungere il router da Internet |
| `openwisp-ddns-lan-template.json` | **IP dell'interfaccia di management** (default `br-lan`) | nome host per l'accesso **LuCI**; l'IP è privato ma instradato in tutta NINUX via Babel |

Sono lo stesso meccanismo (nsupdate/TSIG, stessa zona, stesso `router-<nome>.<zona>`):
cambia solo **quale IP** finisce nel record A. La variante `br-lan` non ha il
fallback su IP pubblico e usa `ip_source 'interface'` in `/etc/config/ddns`.
Applica **una sola** delle due allo stesso device (stesso hostname → si
sovrascriverebbero).

> Caricato su OpenWISP (org Basilicata) come **"DDNS nsupdate (br-lan / LuCI)"**,
> per ora **non** *enabled by default*: prima imposta il `ddns_secret` reale e
> assicurati che il primary abbia la zona `dyn` con `allow-update` deployata e
> raggiungibile dai router.

## Cosa contiene `openwisp-ddns-template.json`

- `config` → da incollare nell'editor JSON (advanced mode) del **Template**
  (Backend = *OpenWRT*, Type = *Generic*). Spinge come *additional files*:
  - `/usr/lib/ddns/update_nsupdate.sh` (0755) — lo script di update
  - `/etc/ddns/ddns.key` (0600) — la chiave TSIG
  - `/etc/config/ddns` (0644) — la sezione UCI del servizio `ddns`
  - `/etc/uci-defaults/99-install-ddns` (0755) — installa i pacchetti al primo apply
- `default_values` → da incollare nel campo **Default Values** del template.

## Variabili

| Variabile             | Default                     | Note |
|-----------------------|-----------------------------|------|
| `ddns_zone`           | `dyn.ninux-nnxx.it`         | zona dinamica sul primary |
| `dns_primary_ip`      | `10.27.0.1`                 | IP del primary BIND raggiungibile dai router |
| `ddns_interface`      | `wan`                       | interfaccia da monitorare |
| `ddns_ttl`            | `60`                        | TTL del record A |
| `ddns_key_name`       | `ddns-key`                  | deve combaciare con la key sul primary |
| `ddns_algorithm`      | `hmac-sha256`               | algoritmo TSIG |
| `ddns_secret`         | `CHANGEME...`               | **segreto TSIG** — impostare il valore reale |
| `ddns_section`        | `ninux`                     | nome sezione UCI `ddns` |
| `ddns_check_interval` | `300`                       | intervallo di check (secondi) |
| `ddns_force_interval` | `72`                        | force update (ore) |

L'hostname NON è una variabile: viene composto come `router-{{ name }}.{{ ddns_zone }}`,
dove `name` è il nome del device in OpenWISP. Quindi basta nominare i device in modo
coerente (es. `matera`, `salandra`).

## Come importarlo

1. *Templates* → *Add template*: Name a piacere, Backend = **OpenWRT**.
2. Apri l'editor JSON (Advanced mode) e incolla il contenuto di `config`.
3. Incolla `default_values` nel campo **Default Values** e imposta `ddns_secret`.
4. Spunta *Enabled by default* se vuoi assegnarlo automaticamente ai nuovi device,
   oppure assegnalo manualmente ai device esistenti.

## Note operative

- **Pacchetti**: i router devono avere `ddns-scripts`, `bind-client` (nsupdate) e
  `curl`. Lo script `uci-defaults` li installa al primo apply (serve rete + feed
  opkg raggiungibili). In alternativa includili nell'immagine firmware OpenWISP.
- **Reload servizio**: alla modifica di `/etc/config/ddns` l'agent openwisp-config
  esegue il reload del pacchetto `ddns`. Al primo deploy lo script uci-defaults fa
  comunque `enable` + `restart`.
- **Segreto TSIG**: `ddns_secret` finisce in chiaro nel config del device sul
  controller. Trattalo come gli altri segreti OpenWISP (accesso al controller).
- **Verifica** sul primary:
  `dig @127.0.0.1 +short router-<device>.dyn.ninux-nnxx.it A`
  e `rndc zonestatus dyn.ninux-nnxx.it`.

## Coerenza con Ansible

Il primary continua a essere gestito da Ansible (`bind9_primary`): zona `dyn`
con `allow-update` per `ddns-key`. I router possono essere gestiti **o** da
`ddns_openwrt` (Ansible) **o** da questo template OpenWISP — non entrambi sullo
stesso device, per evitare config concorrenti.

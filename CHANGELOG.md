# Changelog

Tutte le modifiche significative a questo progetto sono documentate in questo file.
Formato: [Keep a Changelog](https://keepachangelog.com/it/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/lang/it/)

---

## [1.8.0] — 2026-07-09

### Aggiunto
- **Stack monitoring su CT dedicato** — Prometheus, Alertmanager e Grafana escono dal primary e girano su un CT LXC dedicato (nuovo gruppo inventory `monitoring_server`, esempio in `hosts.yml.example`). Il CT entra nella mesh WireGuard come peer (nuovo ramo nel template `wg.conf.j2`: peer diretti verso i secondari con endpoint pubblico + keepalive, e i secondari lo accettano come peer roaming) e scrapa gli exporter di tutti gli host DNS **dentro il tunnel** — mai via IP pubblico. Nuova play `Deploy Monitoring (CT dedicato)` in `site.yml` (tag `monitoring`), rieseguibile da sola.
- **Reverse proxy nginx sul CT monitoring** — le tre GUI rispondono sulla porta 80 con un virtual host per nome (`grafana.`, `prometheus.`, `alertmanager.` — domini in `grafana_domain`/`prometheus_domain`/`alertmanager_domain`): niente porte da digitare, i servizi ascoltano solo su loopback. Template nftables dedicato (`nftables-dns-monitoring.nft.j2`): la :80 è raggiungibile solo dalle reti in `monitoring_allowed_sources`.
- **Migrazione automatica dal primary** — il role monitoring ferma e disabilita lo stack legacy (`prometheus`, `alertmanager`, `grafana-server`) sugli host `dns_primary`; i dati restano su disco (`/var/lib/prometheus`, `/var/lib/grafana`) finché non si decide di rimuoverli.
- **Retry sui download degli exporter** — `get_url` di node_exporter/bind_exporter/prometheus/alertmanager con `timeout: 60` e 3 tentativi (un timeout transitorio di GitHub non fa più fallire il deploy).
- **README bilingue** — `README.md` ora in inglese (per la visibilità internazionale del progetto) con nota "progetto italiano 🇮🇹" e badge Made in Italy; la versione italiana originale vive in `README.it.md`. Link-bandierina in cima a entrambi. Il CHANGELOG resta in italiano, la lingua madre del progetto.

### Corretto
- **`make deploy` completo era rotto dalla v1.7.5** — `bind9_primary` riscrive `named.conf.options` *senza* la definizione della `dnssec-policy` che il suo `named.conf.local` referenzia per zona: il `named-checkconf` pre-reload (introdotto proprio in v1.7.5) falliva sempre lì, prima che il role `dnssec` potesse rideployare le options complete — lasciando su disco una config non avviabile. Ora il template options del primary definisce la policy (stessi parametri del role dnssec) quando `bind_dnssec_policy` è impostata: ogni stato intermedio del deploy è valido, qualunque sia l'ordine dei role.
- **Gli exporter non erano mai stati installati sui secondari** — il role `monitoring` non compariva nella play dei secondari in `site.yml`: i target `node`/`bind_secondary` di Prometheus erano DOWN da sempre. Ora la play li installa e Prometheus li scrapa via WireGuard.
- **Prometheus scrapava i secondari sugli IP pubblici** — i target sono ora derivati da `hostvars[...].wg_address` (niente più `dns_secondary_ips` pubblici nel template `prometheus.yml.j2`).
- **La porta WireGuard non era mai aperta su nftables dei secondari** — il tunnel sopravviveva solo grazie alla entry conntrack creata prima del load del firewall: dopo un reboot del secondario l'handshake non sarebbe più passato. Aggiunta la regola `udp dport 51820 accept` (primary e monitoring CT sono dietro NAT: sorgente non prevedibile, autentica la crypto WireGuard).
- **nftables apriva SSH sulla porta 22, ma sshd gira sulla 2400** — `nft_ssh_port` ora segue `hardening_ssh_port` (esempio in `main.yml.example`); anche qui l'accesso sopravviveva solo per via del conntrack.
- **`gnupg` mancante sui CT minimali** — `apt_repository` (repo Grafana con signed-by) fallisce senza gpg: aggiunto alle dipendenze del role monitoring.

### Modificato
- Gli exporter ascoltano su `0.0.0.0` (prima `127.0.0.1`, che rendeva impossibile lo scraping remoto): l'accesso è limitato da nftables al solo IP WireGuard del monitoring server (`tcp dport {9100,9119} ip saddr <wg del CT>`).
- `grafana.ini`: `http_addr`, `root_url` e `cookie_secure` parametrizzati (`monitoring_gui_listen_addr`, `grafana_root_url`, `grafana_cookie_secure`) — l'accesso HTTP via nginx richiede `cookie_secure: false`.
- Riepilogo di `site.yml`: la sezione MONITORING mostra gli URL per nome host del CT invece del comando SSH tunnel verso il primary.

## [1.7.5] — 2026-07-06

### Corretto
- **`acme_dns`: `--install-cert` solo se il certificato è cambiato** — acme.sh esegue *sempre* il reloadcmd insieme a `--install-cert`, quindi ogni deploy riavviava nginx/postfix/dovecot sui CT anche a certificati invariati. Ora un `cmp` confronta il cert emesso con quello installato e l'install scatta solo su rinnovo o prima installazione (forzabile con `-e acme_force_install=true`, es. dopo aver cambiato un reloadcmd).
- **`cert-deploy.yml`: reload sui CT solo se i file sono cambiati** — stesso principio: il task di reload ora itera solo sui `reload_cmd` dei domini le cui copy (fullchain/chiave) risultano `changed`.

### Aggiunto
- **`named-checkconf` completo prima di ogni reload di BIND** (`bind9_primary/zones`, `dnssec`) — i fragment non sono validabili singolarmente con `validate: %s` (referenziano la `dnssec-policy` di `named.conf.options`): ora la config completa viene verificata subito dopo il deploy dei template, così un errore fa fallire il play *prima* che l'handler ricarichi named, che continua a servire con la config precedente.

### Modificato
- `acme-only.yml`: chiave deploy derivata da `groups['dns_primary'][0]` invece dell'hostname cablato `ns-primary` (come già fatto per il riepilogo di `site.yml`).
- **`zones/dyn.example.com.yml`: SOA `expire` 3600 → 1209600** — con expire a 1 ora bastava 1 ora di primary irraggiungibile (tunnel giù, riavvio) perché i secondari smettessero di servire la zona DDNS: da fuori la zona *spariva* con SERVFAIL. È successo davvero sulla zona dyn reale, scoperto durante i test post-deploy v1.7.4: entrambi i secondari rispondevano "zone not loaded". Ripristinata con `rndc retransfer` e SOA corretta live via nsupdate (senza perdere i record dinamici dei router); expire ora a 14 giorni come le altre zone.

## [1.7.4] — 2026-07-06

### Corretto
- **`dnssec`: l'attesa delle chiavi ora aspetta davvero** — il `wait_for` puntava alla *directory* delle chiavi, appena creata dal task precedente, quindi era sempre un no-op: al primo deploy, se BIND impiegava qualche secondo a generare le chiavi, il `find` successivo falliva. Ora è il `find` stesso a riprovare (`retries: 12 / delay: 5 / until: matched > 0`).
- **`dnssec`: niente più reload di BIND a ogni run** — il task "Ricarica BIND" incondizionato è sostituito da `meta: flush_handlers`: il reload scatta solo se i template `named.conf.*` sono effettivamente cambiati, restando deterministico per la generazione chiavi al primo deploy.

### Modificato
- **`site.yml`: `serial: 1` sui secondari** — i due NS pubblici vengono aggiornati uno alla volta: durante un deploy (o un restart da handler) uno dei due resta sempre in servizio e la risoluzione non si interrompe mai.
- **`site.yml`: riepilogo senza hostname cablati** — primary e secondari sono ora derivati dai gruppi inventory (`groups['dns_primary'][0]`, loop su `groups['dns_secondary']`) e la porta SSH da `ansible_port`: il riepilogo funziona qualunque nome abbiano gli host, non solo `ns-primary`/`ns1`/`ns2`.
- **`ansible.cfg`: host key TOFU** — `StrictHostKeyChecking=no` → `accept-new` (+ `host_key_checking = True`): gli host nuovi vengono accettati al primo contatto, ma una chiave *cambiata* viene rifiutata (protezione MITM). Se un host viene reinstallato: `ssh-keygen -R <host>`.

### Aggiunto
- `acme_dns`: logrotate per `/var/log/acme-renew.log` (mensile, 6 rotazioni, compress) — prima cresceva all'infinito.

## [1.7.3] — 2026-07-05

### Corretto
- **`packages`: installazione util in best-effort per-pacchetto** — prima, con `ignore_errors` su una singola lista apt, un solo pacchetto mancante su Trixie faceva fallire l'intera transazione senza installarne *nessuno*, in silenzio. Ora il loop installa ogni pacchetto singolarmente: quelli mancanti vengono tollerati (`failed_when` che ignora solo "no installation candidate"/"Unable to locate package"), mentre un errore reale (mirror giù, lock dpkg, dipendenze rotte) fa comunque fallire il task.
- CI GitHub Actions aggiornate a runtime Node 24: `actions/checkout@v7`, `actions/setup-python@v6`, `softprops/action-gh-release@v3`; `aquasecurity/trivy-action` pinnato a `@v0.36.0` (era `@master`, non riproducibile).

### Modificato
- Rimosso `ignore_errors` superfluo dai task apt `state: absent` (`packages`, `nftables`): apt è idempotente sui pacchetti già assenti, non fallisce, e ignorare gli errori maschererebbe solo problemi reali di dpkg.
- `dnssec-diag.yml`: aggiunto `set -o pipefail` alle shell con pipe (diagnostica più affidabile).
- `packages`: `mode: "0644"` esplicito sul file logwatch creato con `create: true`.
- Indentazione YAML uniformata a 2 spazi in `hardening_ssh_permit_open` (inventory ed esempio).

## [1.7.2] — 2026-07-05

### Aggiunto
- **TLSA (DANE)** — README: nuova sezione "Gestione zone → TLSA (DANE)" con procedura per ricavare l'hash dal certificato acme.sh (`usage 3/selector 1/matching 1`) e tabella dei record consigliati per un host web+mail.
- `zones/example.com.yml`: esempio TLSA esteso con gli owner name mail (`_25`, `_587`, `_465`, `_993`, `_995._tcp.mail`) oltre a `_443._tcp.www`, con commento sul perché SMTP (STARTTLS opportunistico, RFC 7672) beneficia di DANE mentre POP3/IMAP in chiaro no (nessun client li valida via DANE).
- `SECURITY.md`: policy di responsible disclosure (GitHub Security Advisories o email), essendo il repo pubblico.
- `.github/dependabot.yml`: aggiornamento mensile automatico delle GitHub Actions usate in `ci.yml`/`release.yml`.

## [1.7.1] — 2026-07-04

### Aggiunto
- **Peer WireGuard per Proxmox**: l'host Proxmox (`inventory/hosts.yml`, gruppo `proxmox`) può ora avere un `wg_address` ed entrare nel tunnel WireGuard come peer aggiuntivo, con la stessa logica endpoint+keepalive già usata per i secondari. Serve a far raggiungere BIND ai client nsupdate/RFC2136 esterni sulla LAN (es. l'ACME built-in di Proxmox per il certificato di `pveproxy`) senza mai esporre BIND fuori da loopback+WireGuard.
- `roles/wireguard/templates/wg.conf.j2`: nuovo loop per i peer del gruppo `proxmox`; `ListenPort` ora impostata anche per questi host (necessaria perché il primary possa dialogare verso di loro).
- `playbooks/site.yml`: la play "Setup tunnel WireGuard" include ora anche `proxmox` tra gli host (il ruolo `packages` resta escluso su quel gruppo, per non toccare il pacchettizzo dell'hypervisor).
- `ddns_allowed_sources` di esempio aggiornato con l'IP del tunnel WireGuard di Proxmox (`10.99.0.4`) al posto di una subnet LAN — nessuna apertura di BIND/firewall sulla LAN è necessaria o prevista.
- README: nuova sezione "ACME built-in di Proxmox (certificato interfaccia web)" con i passi di configurazione del plugin DNS `nsupdate` nativo di Proxmox.

## [1.7.0] — 2026-07-01

### Aggiunto
- **Migrazione DNSSEC alg 15 → alg 13**: cambiato algoritmo da Ed25519 (alg 15, non supportato da OVH) a ecdsap256sha256 (alg 13, OVH supporta alg 8-14). Variabili `dnssec_algorithm`, `dnssec_ksk_algorithm`, `dnssec_zsk_algorithm` aggiornate nei defaults del role `dnssec`.
- `dnssec_force_regen`: flag per reset completo chiavi/journal DNSSEC durante migrazioni algoritmo (stop bind9 → rm K* + *.jnl + *.signed → start bind9 → rndc sign).
- `playbooks/dnssec-deploy.yml`: playbook dedicato al role `dnssec` (il tag `--tags dnssec` su `site.yml` non è sufficiente per il force_regen).
- `playbooks/dnssec-repair-keytag.yml`: rinomina i file K* al keytag corretto (workaround bug BIND con alg 15 dove il keytag nel filename non corrisponde a quello calcolato).
- `playbooks/dnssec-diag.yml`: playbook diagnostico (chiavi attive, seriali raw/signed, ultimi log BIND, rndc notify).
- `playbooks/fix-ninux-delegation.yml`: aggiunge la delegation `dyn.ninux-nnxx.it` (NS + DS) al parent zone con la sequenza `rndc freeze → template → rndc thaw`, senza toccare `dyn.ninux-nnxx.it` (zona DDNS con record dinamici).
- `dnssec-ovh.txt`: riepilogo DS record e chiavi pubbliche DNSKEY per la registrazione su OVH (ninux-nnxx.it, romaclubmatera.it, dyn.ninux-nnxx.it).
- `zone.db.j2`: sezione delegazioni sottozone — renderizza record NS + DS dalla chiave `delegations` del file YAML di zona.
- `Makefile`: variabile `EXTRA` per passare parametri extra ad ansible-playbook; nuovi target `dnssec-deploy`, `dnssec-repair`, `fix-delegation`.

### Corretto
- `bind9_primary/templates/named.conf.local.j2`: aggiunge `dnssec-policy` e `inline-signing yes` per ogni zona, usando `bind_dnssec_policy` e `bind_dnssec_key_directory` dai defaults. Impediva la perdita della firma DNSSEC dopo ogni esecuzione di `update-zones.yml`.
- `bind9_primary/tasks/zones.yml`: aggiunti `| bool` ai `when: dns_force_ddns_rewrite` (Ansible passava una stringa invece di booleano con `-e var=true`); rimosso `validate: named-checkconf` da `named.conf.local` (la `dnssec-policy` è definita in `named.conf.options`, non visibile alla validazione standalone).
- `dnssec/tasks/main.yml`: aggiunto `| bool` al `when: dnssec_force_regen` per lo stesso motivo.
- `bind_transfers_out`: aggiunto ai defaults del role `dnssec` (era definito solo in `bind9_primary`, causava errore "undefined" nel template `named.conf.options-dnssec.j2`).

## [1.6.0] — 2026-07-01

### Aggiunto
- `Makefile`: target rapidi per i comandi più comuni (`make deploy`, `make zones`, `make acme`, `make cert-deploy`, `make renew`, `make dnssec`, `make ping`, `make syntax`, `make snapshot`). Supporta override vault via `VAULT="--vault-password-file=..."`.
- `playbooks/acme-only.yml`: playbook mirato per emissione certificati ACME + distribuzione chiave SSH deploy + copia certificati ai CT, tutto in un'unica run.
- `playbooks/cert-deploy.yml`: copia certificati esistenti dal primary ai CT consumer direttamente dal control node (senza passare per il primary). Usabile come task manuale o schedulato.
- `roles/acme_dns`: deploy automatico dei certificati rinnovati ai CT Proxmox consumer. Genera una chiave SSH ed25519 dedicata sul primary, la distribuisce ai CT via `authorized_keys`, crea uno script di deploy per dominio (`/opt/acme.sh/deploy-<domain>.sh`) usato come `--reloadcmd` di acme.sh — attivato al rinnovo automatico (cron 02:30).
- `roles/acme_dns`: download del plugin `dns_nsupdate` (RFC 2136) con versione pinned; download di `acme.sh` versionato (tag reale da GitHub releases, non da `master`).
- `inventory/hosts.yml`: gruppo `cert_consumers` con variabili `cert_domain`, `cert_reload_cmd`, `ansible_port: 2400` per ct-web (nginx, romaclubmatera.it) e ct-mail (postfix+dovecot, ninux-nnxx.it).
- `playbooks/site.yml`: riepilogo deploy esteso con sezioni INFRASTRUTTURA, ZONE DNS, MONITORING (URL + credenziali + comando SSH tunnel per accesso da notebook), SMTP alerts, CERTIFICATI ACME, CT CONSUMER, VAULT.

### Modificato
- `roles/acme_dns/templates/cert-deploy.sh.j2`: lo script di deploy usa porta SSH configurabile (`acme_deploy_ssh_port`, default 2400); gli errori SSH verso i CT sono non-bloccanti (best-effort) — il rinnovo sul primary non fallisce se un CT è irraggiungibile.
- `inventory/group_vars/all/main.yml`: aggiunte variabili `acme_deploy_key`, `acme_deploy_ssh_port`, `acme_domains` con campo `deploy` per mappare dominio → CT + reload command.

### Rimosso
- `roles/acme_dns/templates/acme-dns-hook.sh.j2`: sostituito dal template `cert-deploy.sh.j2` per dominio con supporto multi-CT.

---

## [1.5.0] — 2026-06-18

### Aggiunto
- Template OpenWISP 2 per DDNS via `nsupdate` (`openwisp/openwisp-ddns-template.json`, backend OpenWRT): spinge sui device OpenWrt lo script `update_nsupdate.sh`, la chiave TSIG, la sezione UCI `/etc/config/ddns` e uno script `uci-defaults` che installa `ddns-scripts`/`bind-client`/`curl` al primo apply
- Hostname per-device automatico tramite variabile predefinita `{{ name }}` (`router-<device>.<ddns_zone>`); parametri (zona, IP primary, segreto TSIG, intervalli) come `default_values` del template
- Documentazione in `openwisp/README.md` (import, variabili, note operative)
- `site.yml`: play finale di riepilogo delle variabili vault. Valori mostrati in chiaro di default (deploy su shell fidata); `-e reveal_secrets=false` per vedere solo nome e stato

### Corretto
- CI: rimosso `vault_password_file` macchina-specifico (`/git/.vault_pass`) da `ansible.cfg`, che faceva fallire il `--syntax-check` di `ansible-lint` sul runner. Il path del vault va impostato in locale via `ANSIBLE_VAULT_PASSWORD_FILE` o `--ask-vault-pass`
- `bind9_primary`: generazione delle zone ora idempotente. Il serial viene incrementato solo quando i record cambiano davvero (render col serial corrente + bump mirato), risolvendo il fallimento del test di idempotenza Molecule introdotto dal serial monotòno
- `bind9_primary`: usato `ansible_facts.date_time` al posto di `ansible_date_time` (deprecato, in rimozione in ansible-core 2.24) nei template di zona
- `ansible.cfg`: `interpreter_python = /usr/bin/python3` per evitare il warning di interpreter discovery

## [1.4.1] — 2026-06-18

### Corretto
- `bind9_primary`: le zone DDNS non vengono più sovrascritte ad ogni run. Il file di zona viene scritto solo al primo seed (`force: false`); i record restano gestiti dai client via `nsupdate`, evitando la perdita degli aggiornamenti dinamici e il conflitto col journal `.jnl`
- `bind9_primary`: serial SOA ora monotòno (letto dal server con `dig` e incrementato, mai sotto `YYYYMMDD01`), al posto del valore fisso `YYYYMMDD01` che impediva i trasferimenti ai secondari e poteva regredire rispetto al serial già incrementato dal DDNS

### Aggiunto
- `bind9_primary`: flag `dns_force_ddns_rewrite` per rigenerare la base di una zona DDNS da YAML con la sequenza corretta `rndc freeze` → scrittura → `rndc thaw`
- Suddivisione di `roles/bind9_primary/tasks` in `install.yml`, `keys.yml`, `options.yml`, `zones.yml`, `service.yml` per consentire run mirati sulle sole zone

### Modificato
- `playbooks/update-zones.yml` riscritto come wrapper della sola parte `zones` del ruolo: un solo comando aggiorna zone dirette statiche, DDNS e reverse, senza reinstallazione né restart del servizio (solo reload), con `flush_handlers` e verifica della propagazione del serial sui secondari (escluse le zone DDNS, il cui serial è guidato dagli update `nsupdate`)

## [1.4.0] — 2026-06-12

### Aggiunto
- Role `wireguard`: tunnel cifrato tra hidden primary (dietro NAT) e secondari pubblici
- Topologia roaming peer: il primary si connette ai secondari con PersistentKeepalive
- Trasferimenti di zona (AXFR) e NOTIFY viaggiano cifrati nel tunnel 10.99.0.0/24
- Monitoring (Prometheus + Grafana + Alertmanager) agganciato a site.yml
- Exporter (node, bind) raggiunti via tunnel WireGuard; dashboard DNS e sistema
- nftables: porta WireGuard e traffico fidato dentro wg0
- Inventory e group_vars di esempio (hosts.yml.example, main.yml.example)

### Modificato
- IP DNS (dns_primary_ip / dns_secondary_ips) spostati sugli indirizzi del tunnel
- group_vars spostato accanto all'inventory per il corretto caricamento
- Grafana aggiornato a 13.0.2 con metodo keyring moderno (signed-by)
- SSH: accesso root su porta 2400 con PermitOpen per i tunnel di monitoring

### Corretto
- rkhunter: update del database non bloccante
- dnssec-validation impostato su auto (era yes, richiedeva trust-anchor manuali)
- BIND: utente bind aggiunto al gruppo adm per scrivere i log
- cron aggiunto ai pacchetti base (mancante su VPS minimali)
- audit rules: rimossa modalità immutable (-e 2) che bloccava augenrules
- monitoring: rimossi software-properties-common e apt-key (deprecati su Trixie)
- acme_dns disabilitato sul primary nascosto

### Sicurezza
- Rimozione dati reali dal repo pubblico; il vault non è mai stato committato

## [1.3.0] — 2026-06-10

### Aggiunto
- Record A con `ip` multiplo (lista): genera A multipli sullo stesso nome (round-robin / multi-homing)
- Campo `ipv6` accetta anche lista di indirizzi
- Campo `aliases` sui record A: genera automaticamente CNAME verso il nome canonico
- Avviso in fase di deploy se un host mescola IP pubblici e privati sotto lo stesso nome (rischio irraggiungibilità da fuori rete)
- Template `mixed_ip_warnings.j2` per il rilevamento IP misti

## [1.2.0] — 2026-06-09

### Aggiunto
- Supporto IPv6 inline: campo `ipv6` sui record A genera automaticamente il record AAAA
- Zone reverse (PTR) generate automaticamente dai record A/AAAA, IPv4 e IPv6
- Variabile `dns_reverse_zones` in notazione CIDR (es. 203.0.113.0/24, 10.27.0.0/16, 2001:db8::/64)
- IPv4 reverse /8 /16 /24; IPv6 prefisso multiplo di 4. zone_name calcolato dal CIDR
- Template reverse_meta.j2, reverse_ptr_collect.j2, zone.reverse.db.j2 (puro Jinja2)
- Deduplicazione PTR: un solo PTR per IP

## [1.1.0] — 2026-06-08

### Aggiunto
- Role `proxmox_vm` — provisioning VM primary su Proxmox VE via API + cloud-init
- Playbook `proxmox.yml`, `proxmox-prepare-template.yml`, `proxmox-snapshot.yml`
- Gruppi `proxmox` e `openwrt_routers` nell'inventory
- Sezione README per uso VM OVH come secondari (firewall Edge, Anti-DDoS)
- Aggiunto requirements.txt per cache pip nella CI
- CI: fix cache pip (cache-dependency-path), molecule-plugins[docker]
- CI: immagine molecule geerlingguy/docker-debian13-ansible con systemd
- CI: check vault.yml corretto per file escluso da git
- Aggiunto vault.yml.example come template committabile (vault reale resta escluso)
- Moduli Proxmox migrati a community.proxmox (deprecati in community.general 15.0.0)
- Fix Molecule: ANSIBLE_ROLES_PATH per trovare i role dalla cartella scenario
- Fix bug lookup zone: dns_zones_dir_src punta alla root (site.yml falliva)
- molecule/default/requirements.yml per dependency Galaxy
- Fix: check versione BIND in packages reso condizionale (named non ancora installato)
- Fix: deploy chiavi TSIG/DDNS prima dei conf BIND (validate include falliva)
- Fix: filtro ljust inesistente sostituito con format in zone.db.j2 e playbook
- Fix: placeholder hex non validi (TLSA/SSHFP) in example.com.yml sostituiti con hex validi
- Fix: deploy frammenti nft prima del ruleset principale (validate include)
- Fix: set nftables con join invece di loop malformati (sintassi nft valida)
- Fix: include anti-amplification mancante + regole reali nel frammento
- Fix: include TSIG key in named.conf.local del secondary (validate isolata)
- Fix: test_sequence molecule idempotency -> idempotence (nome corretto)
- Fix: rimosso timestamp volatile da zone.db.j2 per garantire idempotenza
- Fix: verify.yml usa named.service (nome reale su Trixie) + scope corretto
- Fix: verify secondary controlla allow-transfer none (allow-update vietato in slave)

### Corretto
- Bug precedenza operatori nel calcolo serial SOA (update-zones.yml)
- Variabile riservata `action` rinominata in `snap_action` (proxmox-snapshot.yml)
- `hardening_ssh_alt_port` mancante nei defaults (usata da fail2ban)
- Template alert Prometheus avvolti in `{% raw %}` per evitare collisione Jinja2
- `ansible.cfg`: rimosso commento inline su vault_password_file
- Secret in main.yml e monitoring collegati al vault invece di placeholder
- `proxmox-prepare-template.yml`: hosts da variabile a gruppo inventory
- Aggiunti `changed_when` ai comandi qm/rndc, jinja spacing, name[template]
- Config ansible-lint e yamllint allineate al profilo production


## [1.0.0] — 2026-06-07

### Aggiunto
- Role `bind9_primary` — hidden master BIND 9.20 con zone YAML
- Role `bind9_secondary` — N secondari pubblici con AXFR TSIG
- Role `dnssec` — inline signing automatico con dnssec-policy Ed25519
- Role `acme_dns` — certificati wildcard via acme.sh DNS-01
- Role `ddns_openwrt` — configurazione DDNS per router OpenWrt
- Role `nftables` — firewall con profili primary/secondary, anti-amplification
- Role `hardening` — 11 moduli: SSH, sysctl, filesystem, auditd, fail2ban, rkhunter...
- Role `packages` — pacchetti base, utils, sicurezza
- Role `monitoring` — Prometheus + bind_exporter + node_exporter + Alertmanager + Grafana
- Playbook `update-zones.yml` — serial SOA automatico YYYYMMDDnn con diff e propagation check
- Playbook `dnssec-status.yml` — stato DNSSEC e DS records per registrar
- Molecule scenario con Debian Trixie + verify assertions
- GitHub Actions CI: lint + syntax + molecule + trivy + release automatica
- README.md completo in italiano (945 righe)

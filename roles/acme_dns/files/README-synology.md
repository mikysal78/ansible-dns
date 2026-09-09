# Deploy automatico del wildcard su Synology DSM (DS214play, DSM 7.1.1)

Il Synology (`10.27.22.2`) riceve il wildcard `ninux-nnxx.it` **automaticamente
ad ogni rinnovo**, come i CT, ma con un percorso diverso: DSM non usa
`/etc/ssl/acme` né systemctl, quindi il cert va importato nello store DSM
(`/usr/syno/etc/certificate/_archive/<ID>/` + `synow3tool --gen-all`).

## Come funziona
1. Al rinnovo di `ninux-nnxx.it`, acme.sh sul primary esegue
   `deploy-ninux-nnxx.it.sh` (generato da `templates/cert-deploy.sh.j2`).
2. La sezione `synology` del template (config in `acme_domains[].synology`)
   trasferisce `fullchain.pem`+`privkey.pem` via **ssh + cat** (il NAS non ha
   il subsystem SFTP → scp non funziona) nella dir di staging `/tmp/nnxx-cert-stage`.
3. Invoca via **sudo NOPASSWD** lo script installer `syno-cert-import.sh`, che
   splitta il fullchain, aggiorna la cartella archive `nnxxWc`, lancia
   `synow3tool --gen-all` e ricarica nginx.

## Setup una-tantum sul NAS (NON gestito da Ansible)
Il DS214play non è nell'inventory come host gestito; questi passi vanno fatti a
mano (fatti il 2026-09-09):

1. **Chiave SSH** del primary autorizzata per l'utente admin `michele`:
   la pubkey `acme-deploy@ns-primary` (`/root/.ssh/acme_deploy_id_ed25519.pub`)
   in `~michele/.ssh/authorized_keys` (0600, `.ssh` 0700).
2. **Installer** `syno-cert-import.sh` (questo file) copiato in
   `/usr/local/bin/syno-cert-import.sh`, `root:root 0755`.
3. **sudoers** `/etc/sudoers.d/nnxx-cert` (0440):
   `michele ALL=(root) NOPASSWD: /usr/local/bin/syno-cert-import.sh`
4. **Cartella archive** `nnxxWc` creata in `_archive/` con la voce corrispondente
   in `_archive/INFO` (`desc: "ninux-nnxx.it wildcard"`).

## Note
- Il cert è importato ma **l'assegnazione ai servizi** (DSM/Drive/Photos) si fa
  dalla GUI (*Pannello di controllo → Sicurezza → Certificato*). Una volta
  assegnato, l'installer ricarica nginx così i nuovi byte vengono serviti.
- Se cambia l'ID archive o l'host, aggiornare `ID=` nell'installer e
  `acme_domains[].synology` in `group_vars/all/main.yml`.

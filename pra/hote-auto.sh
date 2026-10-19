#!/usr/bin/env bash
# hote-auto.sh : remet sur la cible PRA_CIBLE (labo | secours) l'automatisation de l'hôte pve : scripts de /usr/local/sbin,
# unités systemd et minuteries, cron de sauvegarde, courriel sortant, fail2ban, mises à jour automatiques, état.
#   pra/hote-auto.sh              à sec
#   pra/hote-auto.sh --oui        fichiers en place, paquets installés, minuteries NON activées
#   pra/hote-auto.sh --demarrer   APRÈS la bascule : active les minuteries actives sur pve, fail2ban, postfix
#   pra/hote-auto.sh --arreter    RETOUR ARRIÈRE : désactive ces minuteries (pve reprend la main)
# L'archive contient des secrets (relais de courriel, rclone, clés de sauvegarde) : déchiffrée en flux, jamais affichée.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSAGE=2026-S42-fog
TIRAGE="$HOME/pra-tirage/$PASSAGE"
CLE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/infra-as-code/cle-gpg"
mode=sec
for a in "$@"; do case "$a" in --oui) mode=oui ;; --demarrer) mode=demarrer ;; --arreter) mode=arreter ;; *) echo "usage : $0 [--oui|--demarrer|--arreter]" >&2; exit 64 ;; esac; done
. "$DIR/lib-ssh-labo.sh"
CLAIR="$(sed -n 's/^dechiffrement_dir:[[:space:]]*//p' "$DIR/perimetre.yaml")"; CLAIR="${CLAIR%/}"

if [ "$mode" = demarrer ] || [ "$mode" = arreter ]; then
  ssh_labo bash -s -- "$mode" <<'CIBLE'
m="$1"; l=/etc/pra-hote-auto-minuteries.txt
[ -s "$l" ] || { echo "ARRÊT : $l absent (lancer --oui d'abord)"; exit 1; }
if [ "$m" = demarrer ]; then
  systemctl daemon-reload
  while read -r t; do systemctl enable --now "$t" </dev/null >/dev/null 2>&1 && echo "  minuterie active : $t" || echo "  ÉCHEC : $t"; done < "$l"
  [ -f /etc/pra-sauvegarde-hebdo.cron ] && cp /etc/pra-sauvegarde-hebdo.cron /etc/cron.d/sauvegarde-hebdo && echo "  cron de sauvegarde actif"
  systemctl enable --now fail2ban </dev/null >/dev/null 2>&1; systemctl restart postfix </dev/null
  echo "fail2ban $(systemctl is-active fail2ban), postfix $(systemctl is-active postfix)"
else
  while read -r t; do systemctl disable --now "$t" </dev/null >/dev/null 2>&1; done < "$l"
  rm -f /etc/cron.d/sauvegarde-hebdo
  echo "minuteries de l'hôte désactivées : $(wc -l < "$l")"
fi
CIBLE
  exit $?
fi

a="$(ls "$TIRAGE"/pve-hote-auto-*.tar.zst.gpg 2>/dev/null | tail -1)"
[ -n "$a" ] && ( cd "$TIRAGE" && sha256sum --status -c "$(basename "$a").sha256" ) || { echo "ARRÊT : archive pve-hote-auto absente ou empreinte fausse dans $TIRAGE" >&2; exit 1; }
if [ "$mode" = sec ]; then echo "À SEC ($PRA_CIBLE) : $(basename "$a") -> fichiers de l'hôte, minuteries non activées ; relancer avec --oui"; exit 3; fi
[ -s "$CLE" ] || { echo "clé absente : bash phrase-session.sh charger" >&2; exit 2; }
verifier_cible || { echo "REFUS : cible $PRA_CIBLE injoignable" >&2; exit 4; }

nom="$(basename "$a" .gpg)"
ssh_labo "mkdir -p $CLAIR"
gpg --batch --pinentry-mode loopback --passphrase-fd 3 -d "$a" 3<"$CLE" 2>/dev/null | ssh_labo "cat > $CLAIR/$nom"
ssh_labo "zstd -t -q $CLAIR/$nom" || { echo "ARRÊT : $nom illisible après déchiffrement" >&2; exit 1; }
ssh_labo "test -s $CLAIR/debs-partage.tar" || cat "$TIRAGE/debs-partage.tar" | ssh_labo "cat > $CLAIR/debs-partage.tar"

ssh_labo bash -s -- "$CLAIR" "$nom" <<'CIBLE'
set -euo pipefail
clair="$1"; nom="$2"
paquets="fail2ban unattended-upgrades postfix libsasl2-modules"
# une installation qui retire des paquets (ex. proxmox-ve pour une bibliothèque partagée) est refusée
sans_retrait() { if apt-get install -s -q "$@" </dev/null 2>/dev/null | grep "^Remv"; then echo "ARRÊT : apt retirerait les paquets ci-dessus"; exit 1; fi; }
manque=""; for p in $paquets; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || manque+=" $p"; done
if [ -n "$manque" ]; then
  sans_retrait $manque
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q $manque </dev/null >/tmp/apt-hote.log 2>&1 || {
    echo "pas d'Internet : paquets du passage, servis par un dépôt apt local"
    # dépôt local : apt choisit parmi les alternatives du lot, même sans aucune liste de paquets en ligne
    d=/root/pra/depot-debs; mkdir -p "$d"; tar -xf "$clair"/debs-partage.tar -C "$d"
    (cd "$d" && apt-ftparchive packages . > Packages)
    echo "deb [trusted=yes] file:$d ./" > /etc/apt/sources.list.d/pra-depot-debs.list
    apt-get update -q -o Dir::Etc::sourcelist=sources.list.d/pra-depot-debs.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 </dev/null >/tmp/apt-hote.log 2>&1
    sans_retrait --no-install-recommends $manque
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $manque </dev/null >>/tmp/apt-hote.log 2>&1 || { rm -f /etc/apt/sources.list.d/pra-depot-debs.list; tail -8 /tmp/apt-hote.log; exit 1; }
    rm -f /etc/apt/sources.list.d/pra-depot-debs.list
  }
fi
# fichiers remplacés : copie d'origine gardée à côté (*.avant-pra), au premier passage seulement
if [ ! -e /etc/pra-hote-auto-minuteries.txt ]; then
  tar -I zstd -tf "$clair/$nom" | grep -v '/$' | grep -v '^hote-auto-minuteries.txt$' | while read -r f; do
    [ -f "/$f" ] && [ ! -e "/$f.avant-pra" ] && cp -a "/$f" "/$f.avant-pra"; true
  done
fi
tar -I zstd -xf "$clair/$nom" -C / --exclude=hote-auto-minuteries.txt
tar -I zstd -xOf "$clair/$nom" hote-auto-minuteries.txt > /etc/pra-hote-auto-minuteries.txt
# le cron de sauvegarde n'est actif qu'après la bascule (--demarrer)
[ -f /etc/cron.d/sauvegarde-hebdo ] && mv /etc/cron.d/sauvegarde-hebdo /etc/pra-sauvegarde-hebdo.cron
postmap /etc/postfix/sasl_passwd 2>/dev/null || true
newaliases 2>/dev/null || true
systemctl daemon-reload
rm -f "$clair/$nom"
echo "scripts : $(ls /usr/local/sbin | grep -vc '\.avant-pra$') ; minuteries prêtes (non activées) : $(wc -l < /etc/pra-hote-auto-minuteries.txt) ; cron de sauvegarde en attente : $(test -f /etc/pra-sauvegarde-hebdo.cron && echo oui || echo non)"
echo "paquets : $(for p in $paquets; do printf '%s=%s ' "$p" "$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null || echo absent)"; done)"
CIBLE
echo "fait. Après la bascule : bash pra/hote-auto.sh --demarrer"

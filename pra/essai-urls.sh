#!/usr/bin/env bash
# essai-urls.sh : appelle les mêmes URL profondes depuis pve et depuis la cible PRA_CIBLE, compare code HTTP, taille et
# empreinte. Fichiers statiques (miroir, scripts, ISO) : empreinte identique exigée ; pages dynamiques : code identique.
#   pra/essai-urls.sh            exit 0 = tout conforme
# Le cache apt est essayé sur un paquet déjà en cache : sans Internet, il refuse les index (InRelease), revérifiés en amont.
# Une ligne de URLS : « statique|dynamique  url  [proxy] »
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URLS='statique  http://10.0.0.25/etat.txt
statique  http://10.0.0.25/mint/dists/
statique  http://10.0.0.25/scripts/SHA256SUMS
statique  http://10.0.0.25/scripts/firstboot/install-firstboot.sh
statique  http://10.0.0.25/scripts/fiche-pc.sh
statique  http://archive.ubuntu.com/ubuntu/pool/main/libm/libmtp/libmtp9t64_1.1.21-3.1ubuntu1_amd64.deb  http://10.0.0.25:3142
statique  http://10.0.0.19/
statique  http://10.0.0.11/fog/service/ipxe/boot.php
dynamique http://10.0.0.11/fog/management/index.php
dynamique http://10.0.0.20/doku.php?id=start
dynamique http://10.0.0.22/
dynamique http://10.0.0.23/login
dynamique https://10.0.0.24/alive
dynamique http://10.0.0.29/
dynamique http://10.0.0.31/i/
dynamique http://10.0.0.33/
dynamique http://10.0.0.34/
dynamique http://10.0.0.35:3000/
dynamique http://10.0.0.36/'
sonde() {
  cat <<SONDE
while read -r genre url proxy; do
  [ -n "\$url" ] || continue
  opt=""; [ -n "\${proxy:-}" ] && opt="-x \$proxy"
  f=\$(mktemp); c=\$(curl -sk --max-time 20 \$opt -o "\$f" -w '%{http_code}' "\$url"); s=\$(stat -c %s "\$f"); h=\$(sha256sum "\$f" | cut -c1-12); rm -f "\$f"
  echo "\$genre|\$url|\$c|\$s|\$h"
done <<'L'
$URLS
L
SONDE
}
. "$DIR/lib-ssh-labo.sh"
A="$(sonde | ssh pve bash -s)"; B="$(sonde | ssh_labo bash -s)"
ko=0
echo "URL profondes : pve contre $PRA_CIBLE — $(date -Is)"
while IFS='|' read -r g u c s h; do
  l="$(grep -F "|$u|" <<<"$B")"; IFS='|' read -r _ _ c2 s2 h2 <<<"$l"
  if [ "$g" = statique ]; then ok=$([ "$c" = "$c2" ] && [ "$h" = "$h2" ] && echo OK || echo KO)
  else ok=$([ "$c" = "$c2" ] && echo OK || echo KO); fi
  [ "$c" = 000 ] && ok=KO
  [ "$ok" = KO ] && ko=$((ko + 1))
  printf '[%s] %-9s %-62s pve %s %8s o %s | %s %s %8s o %s\n' "$ok" "$g" "$u" "$c" "$s" "$h" "$PRA_CIBLE" "$c2" "$s2" "$h2"
done <<<"$A"
echo "BILAN : $ko écart(s)"
[ "$ko" -eq 0 ]

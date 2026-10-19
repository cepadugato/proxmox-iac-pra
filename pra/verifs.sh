#!/usr/bin/env bash
# verifs.sh : contrôle applicatif des services restaurés (feuille 5.9) par comparaison avec la production.
#   pra/verifs.sh --reference      relève sur pve (lecture seule) la référence : ports TCP d'écoute de chaque invité et
#                                  titre HTML de chaque port web ; écrit pra/references-pve.tsv
#   pra/verifs.sh                  même relevé sur la cible (PRA_CIBLE=labo par défaut, ou secours) et comparaison ligne à ligne
# Exit 0 = chaque port et chaque titre de la référence se retrouvent sur la cible ; 1 = écart ; 2 = relevé impossible.
# Une ligne de la référence : <vmid> <port> <titre ou « - »>. Les invités arrêtés sur la cible sont signalés en écart.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$DIR/references-pve.tsv"
lire() { sed -n "s/^$1:[[:space:]]*//p" "$DIR/perimetre.yaml" | head -1; }
CTS="$(lire vague1) $(lire vague2) $(lire vague3)"; VMS="$(lire vm)"

# relevé exécuté sur l'hôte Proxmox (pve ou cible) : stdin = ce script, arguments = CT puis « -- » puis VM
RELEVE='
set -u
cts=(); vms=(); v=0
for a in "$@"; do [ "$a" = -- ] && { v=1; continue; }; [ $v = 0 ] && cts+=("$a") || vms+=("$a"); done
titre() { curl -sk -L --max-time 6 "$1" 2>/dev/null | tr "\n\r\t" "   " | sed -n "s/.*<title[^>]*>[[:space:]]*\([^<]*\)<\/title>.*/\1/Ip" | head -c 80 | sed "s/[[:space:]]*$//"; }
ip_ct() { pct config "$1" | sed -n "s/^net0:.*ip=\([0-9.]*\)\/.*/\1/p"; }
for i in "${cts[@]}"; do
  pct status "$i" 2>/dev/null | grep -q running || { echo -e "$i\tARRETE\t-"; continue; }
  ip="$(ip_ct "$i")"
  for p in $(pct exec "$i" -- ss -ltnH 2>/dev/null | awk "{print \$4}" | grep -vE "^(127\.|\[::1\]|::1)" | sed "s/.*://" | sort -un); do
    t="-"; case "$p" in 80|443|3000|3001|8000|8080|8081|8443|9091|17170) t="$(titre "$( [ "$p" = 443 ] || [ "$p" = 8443 ] && echo https || echo http )://$ip:$p/")"; [ -n "$t" ] || t="-" ;; esac
    echo -e "$i\t$p\t$t"
  done
done
for i in "${vms[@]}"; do
  qm status "$i" 2>/dev/null | grep -q running || { echo -e "$i\tARRETE\t-"; continue; }
  for p in 80 443; do
    code="$(curl -sk -o /dev/null -w "%{http_code}" --max-time 6 "$( [ $p = 443 ] && echo https || echo http )://10.0.0.23:$p/")"
    [ "$code" != 000 ] && { t="$(titre "$( [ $p = 443 ] && echo https || echo http )://10.0.0.23:$p/")"; echo -e "$i\t$p\t${t:--}"; }
  done
done
exit 0
'
args=($CTS -- $VMS)

if [ "${1:-}" = --reference ]; then
  ssh -o BatchMode=yes pve "bash -s -- ${args[*]}" <<<"$RELEVE" | sort -t$'\t' -k1,1n -k2,2n > "$REF.tmp" || { echo "relevé pve impossible" >&2; exit 2; }
  mv "$REF.tmp" "$REF"; echo "référence écrite : $REF ($(wc -l < "$REF") lignes, $(date -Is))"; exit 0
fi

[ -s "$REF" ] || { echo "référence absente : pra/verifs.sh --reference" >&2; exit 2; }
. "$DIR/lib-ssh-labo.sh"
verifier_cible || { echo "REFUS : cible $PRA_CIBLE non vérifiée" >&2; exit 2; }
obtenu="$(ssh_labo "bash -s -- ${args[*]}" <<<"$RELEVE" | sort -t$'\t' -k1,1n -k2,2n)" || { echo "relevé de la cible impossible" >&2; exit 2; }
ko=0; n=0
while IFS=$'\t' read -r i p t; do
  n=$((n + 1))
  ligne="$(awk -F'\t' -v i="$i" -v p="$p" '$1==i && $2==p' <<<"$obtenu")"
  if [ -z "$ligne" ]; then echo "[KO] $i port $p : absent sur $PRA_CIBLE"; ko=1; continue; fi
  t2="$(cut -f3 <<<"$ligne")"
  if [ "$t" = "$t2" ]; then echo "[OK] $i port $p${t:+ « $t »}"
  else echo "[KO] $i port $p : titre « $t2 » au lieu de « $t »"; ko=1; fi
done < "$REF"
grep -P '\tARRETE\t' <<<"$obtenu" | while IFS=$'\t' read -r i _ _; do echo "[KO] $i arrêté sur $PRA_CIBLE"; done
grep -qP '\tARRETE\t' <<<"$obtenu" && ko=1
echo "BILAN : $n contrôle(s) de la référence pve sur $PRA_CIBLE : $( [ $ko = 0 ] && echo vert || echo ROUGE ) ($(date -Is))"
exit "$ko"

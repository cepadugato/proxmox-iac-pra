#!/usr/bin/env bash
# comparer-pile.sh : compare toute la pile d'un Proxmox cible (PRA_CIBLE : labo | secours) à celle de pve.
#   pra/comparer-pile.sh --reference   relève pve et l'enregistre dans pra/reference-pile-pve.txt
#   pra/comparer-pile.sh               relève la cible et rend les écarts à la référence (exit 0 = aucun écart)
# Le même sondage tourne des deux côtés ; chaque ligne est « famille|objet|valeur » :
#   G invités et état · C configuration (stockage normalisé) · R services en marche dans chaque CT
#   F services en échec · P ports à l'écoute (hors ports éphémères ≥ 32768) · H services et minuteries de l'hôte · D dossiers liés (taille, fichiers)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$DIR/reference-pile-pve.txt"

sonde() {
cat <<'SONDE'
set -u
cles_ct='^(arch|cores|memory|swap|hostname|nameserver|searchdomain|unprivileged|features|onboot|startup|ostype|tags|net[0-9]+|mp[0-9]+|dev[0-9]+|lxc\.[a-z.]+)$'
cles_vm='^(cores|sockets|memory|cpu|machine|bios|agent|onboot|startup|ostype|net[0-9]+|ipconfig[0-9]+|scsihw|boot)$'
pct list | awk 'NR>1{print $1}' | while read -r i; do
  st="$(pct status "$i" | awk '{print $2}')"; echo "G|ct $i|$st"
  pct config "$i" | sed '/^\[/q' | while IFS= read -r l; do
    k="${l%%:*}"; v="${l#*: }"
    case "$k" in rootfs) echo "C|ct $i|rootfs size=$(sed -n 's/.*size=\([^,]*\).*/\1/p' <<<"$v")"; continue ;; esac
    # host-managed=0 est la valeur par défaut, écrite explicitement par OpenTofu
    [[ "$k" =~ $cles_ct ]] && echo "C|ct $i|$k=${v//,host-managed=0/}"
  done
  [ "$st" = running ] || continue
  pct exec "$i" -- sh -c 'systemctl list-units --type=service --state=running --plain --no-legend 2>/dev/null | awk "{print \$1}"' </dev/null 2>/dev/null \
    | grep -vE '^(user@|getty@|console-getty|container-getty@)' | sed "s/^/R|ct $i|/"
  pct exec "$i" -- sh -c 'systemctl --failed --plain --no-legend 2>/dev/null | awk "{print \$1}"' </dev/null 2>/dev/null | sed "s/^/F|ct $i|/"
  pct exec "$i" -- sh -c 'ss -Hltnu 2>/dev/null | awk "{n=split(\$5,a,\":\"); if (a[n]+0 < 32768) print \$1\"/\"a[n]}" | sort -u' </dev/null 2>/dev/null | sed "s/^/P|ct $i|/"
done
qm list | awk 'NR>1{print $1}' | while read -r i; do
  st="$(qm status "$i" | awk '{print $2}')"; echo "G|vm $i|$st"
  qm config "$i" | sed '/^\[/q' | while IFS= read -r l; do
    k="${l%%:*}"; v="${l#*: }"
    [[ "$k" =~ $cles_vm ]] && echo "C|vm $i|$k=$v"
    [[ "$k" =~ ^(scsi|virtio|sata)[0-9]+$ ]] && echo "C|vm $i|$k size=$(sed -n 's/.*size=\([^,]*\).*/\1/p' <<<"$v")"
  done
  [ "$st" = running ] || continue
  out="$(qm guest exec "$i" -- sh -c 'systemctl list-units --type=service --state=running --plain --no-legend | cut -d" " -f1; echo ===; systemctl --failed --plain --no-legend | cut -d" " -f1; echo ===; ss -Hltnu | awk "{n=split(\$5,a,\":\"); if (a[n]+0 < 32768) print \$1\"/\"a[n]}" | sort -u' </dev/null 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("out-data",""))' 2>/dev/null)"
  if [ -z "$out" ]; then echo "R|vm $i|(agent invité muet)"; continue; fi
  awk -v id="vm $i" 'BEGIN{f="R"} /^===$/{f=(f=="R")?"F":"P"; next} NF{print f"|"id"|"$1}' <<<"$out" | grep -vE '\|(user@|getty@|serial-getty@)'
done
systemctl list-units --type=service --state=running --plain --no-legend | awk '{print $1}' \
  | grep -vE '^(user@|getty@|serial-getty@)' | sed 's/^/H|hôte service|/'
systemctl list-timers --all --plain --no-legend 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /\.timer$/) print $i}' | sed 's/^/H|hôte minuterie|/'
ls /etc/cron.d 2>/dev/null | sed 's/^/H|hôte cron.d|/'
for d in /tank/miroir-apt /tank/scripts-http /tank/iso-netboot /tank/nbxyz-drivers /tank/partage; do
  if [ -d "$d" ]; then echo "D|$d|$(du -s --apparent-size --block-size=1M "$d" | cut -f1) Mo, $(find "$d" -type f | wc -l) fichiers"
  else echo "D|$d|absent"; fi
done
SONDE
}

if [ "${1:-}" = --reference ]; then
  sonde | ssh pve bash -s 2>/dev/null | LC_ALL=C sort -u > "$REF.nouveau" && mv "$REF.nouveau" "$REF"
  echo "référence pve : $(wc -l < "$REF") lignes -> $REF ($(date -Is))"; exit 0
fi
[ -s "$REF" ] || { echo "référence absente : pra/comparer-pile.sh --reference (pve allumé)" >&2; exit 2; }
. "$DIR/lib-ssh-labo.sh"
CIB="$(mktemp)"; PER="$(mktemp)"; trap 'rm -f "$CIB" "$PER"' EXIT
sonde | ssh_labo bash -s 2>/dev/null | LC_ALL=C sort -u > "$CIB"
# périmètre du PRA : CT des vagues, VM de la clé « vm », FOG (110) ; les autres invités des deux côtés sont ignorés
ids="$(sed -n 's/^\(vague[123]\|vm\):[[:space:]]*//p' "$DIR/perimetre.yaml") 110"
filtre() { awk -F'|' -v ids=" $ids " '{split($2,o," ")} (o[1]!="ct" && o[1]!="vm") || index(ids," "o[2]" ")' "$1"; }
filtre "$REF" > "$PER"; filtre "$CIB" > "$CIB.f"; mv "$CIB.f" "$CIB"; REF="$PER"
echo "pile de $PRA_CIBLE comparée à pve (référence du $(date -r "$DIR/reference-pile-pve.txt" '+%F %H:%M'), périmètre PRA) — $(date -Is)"
ecarts=0
for fam in G C R F P H D; do
  a="$(grep "^$fam|" "$REF")"; b="$(grep "^$fam|" "$CIB")"
  seul_pve="$(LC_ALL=C comm -23 <(echo "$a") <(echo "$b") | grep .)"; seul_cible="$(LC_ALL=C comm -13 <(echo "$a") <(echo "$b") | grep .)"
  communes="$(LC_ALL=C comm -12 <(echo "$a") <(echo "$b") | grep -c .)"
  n=$(( $(grep -c . <<<"$seul_pve") + $(grep -c . <<<"$seul_cible") ))
  echo "== $fam : $communes identiques, $n écart(s)"
  [ -n "$seul_pve" ] && sed 's/^/   pve seulement   : /' <<<"$seul_pve"
  [ -n "$seul_cible" ] && sed "s/^/   $PRA_CIBLE seulement : /" <<<"$seul_cible"
  ecarts=$((ecarts + n))
done
echo "TOTAL : $ecarts écart(s)"
[ "$ecarts" -eq 0 ]

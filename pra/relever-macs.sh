#!/usr/bin/env bash
# relever-macs.sh : relève sur une cible Proxmox la MAC de eth0 (et de eth1 si présente) de chaque CT du périmètre et écrit tofu/<cible>.macs.tfvars.
#   pra/relever-macs.sh <pve|labo> [--ecrire]
# Sans --ecrire : affiche le fichier qui serait écrit. tofu-cible.sh charge ce fichier s'il existe (sinon : MAC de pve).
# Usage typique : après « pct restore --unique » (MAC neuves) sur un Proxmox qui partage le LAN avec pve encore vivant,
# pour que le code décrive de nouveau la machine (plan sans changement). Un CT absent de la cible est signalé, pas inventé.
# Variable d'essai : RELEVER_MACS_SOURCE = commande qui rend la sortie de « pct config <vmid> » (reçoit le VMID en argument).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cible="${1:-}"; ecrire=0; [ "${2:-}" = --ecrire ] && ecrire=1
lire() { sed -n "s/^$1:[[:space:]]*//p" "$DIR/perimetre.yaml" | head -1; }
config() {
  if [ -n "${RELEVER_MACS_SOURCE:-}" ]; then $RELEVER_MACS_SOURCE "$1"; return; fi
  case "$cible" in
    pve)  ssh -o BatchMode=yes pve "pct config $1" ;;
    labo) bash "$DIR/poste-labo.sh" --verifier >/dev/null && bash "$DIR/lib-ssh-labo.sh" "pct config $1" ;;
    secours) PRA_CIBLE=secours bash "$DIR/lib-ssh-labo.sh" "pct config $1" ;;
  esac
}
case "$cible" in pve|labo|secours) ;; *) echo "usage : $0 <pve|labo|secours> [--ecrire]" >&2; exit 2 ;; esac
sortie="# MAC de eth0 relevées sur la cible $cible par pra/relever-macs.sh le $(date -Is). Ne pas éditer à la main.
macs = {"
manque=0
for i in $(lire vague1) $(lire vague2) $(lire vague3); do
  c="$(config "$i" 2>/dev/null)" || c=""
  mac="$(sed -n 's/^net0:.*hwaddr=\([0-9A-Fa-f:]\{17\}\).*/\1/p' <<<"$c" | tr 'a-f' 'A-F')"
  if [ -z "$mac" ]; then echo "CT $i : absent de $cible ou sans net0/hwaddr (non écrit)" >&2; manque=1; continue; fi
  sortie+=$'\n'"  \"$i\" = \"$mac\""
  mac1="$(sed -n 's/^net1:.*hwaddr=\([0-9A-Fa-f:]\{17\}\).*/\1/p' <<<"$c" | tr 'a-f' 'A-F')"
  [ -n "$mac1" ] && sortie+=$'\n'"  \"$i-eth1\" = \"$mac1\""
done
sortie+=$'\n'"}"
[ "$manque" -eq 0 ] || { echo "REFUS : relevé incomplet, rien n'est écrit" >&2; exit 1; }
if [ "$ecrire" -eq 1 ]; then printf '%s\n' "$sortie" > "$DIR/../tofu/$cible.macs.tfvars"; echo "écrit : tofu/$cible.macs.tfvars"
else printf '%s\n' "$sortie"; echo "(simulation : relancer avec --ecrire)"; fi

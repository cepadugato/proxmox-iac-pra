#!/usr/bin/env bash
# copier-donnees-liees-labo.sh : recopie de pve vers la cible PRA_CIBLE (labo par défaut, ou secours) le contenu des dossiers
# liés aux CT (miroir apt, scripts HTTP, ISO et pilotes de netbootxyz), propriétaires numériques conservés.
# Ces données ne sont dans aucune sauvegarde (re-téléchargeables, sauf les scripts HTTP, dans l'archive pve-hote-auto) :
# cette copie demande pve vivant.
#   labo    : flux pve -> poste -> labo (le labo n'est joignable que par le poste)
#   secours : flux direct pve -> secours sur le réseau local ; clé du secours prêtée par l'agent SSH du poste (ssh -A),
#             empreinte du secours imposée depuis le known_hosts du poste
set -uo pipefail
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PRA_CIBLE="${PRA_CIBLE:-labo}"
. "$PROJ/pra/lib-ssh-labo.sh"
LOG="$PROJ/recettes/preuve-donnees-liees-$PRA_CIBLE.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Is) copie des dossiers liés pve -> $PRA_CIBLE"
if [ "$PRA_CIBLE" = secours ]; then
  . "$HOME/.config/infra-as-code/secours.conf"
  KH="$HOME/.ssh/known_hosts-pra-secours"
  [ -s "$KH" ] || { echo "ARRÊT : $KH absent"; exit 1; }
  scp -q "$KH" pve:/tmp/known_hosts-pra-secours || exit 1
  ssh-add -l 2>/dev/null | grep -q pra-secours || ssh-add "$HOME/.ssh/pra-secours" || { echo "ARRÊT : clé pra-secours absente de l'agent"; exit 1; }
fi
for d in scripts-http nbxyz-drivers iso-netboot miroir-apt; do
  t0=$SECONDS
  if [ "$PRA_CIBLE" = secours ]; then
    ssh -n -A pve "tar -C /tank --numeric-owner -cf - $d | ssh -o UserKnownHostsFile=/tmp/known_hosts-pra-secours -o StrictHostKeyChecking=yes -o BatchMode=yes root@$SECOURS_IP 'mkdir -p /tank && tar -C /tank --numeric-owner -xf -'"
    echo "$d : rc=$?, $((SECONDS - t0)) s"
  else
    ssh -n pve "tar -C /tank --numeric-owner -cf - $d" | ssh_labo "mkdir -p /tank && tar -C /tank --numeric-owner -xf -"
    ps=("${PIPESTATUS[@]}"); echo "$d : tar pve=${ps[0]} $PRA_CIBLE=${ps[1]}, $((SECONDS - t0)) s"
  fi
  echo "  pve  : $(ssh -n pve "du -s --apparent-size /tank/$d | cut -f1; find /tank/$d | wc -l" | paste -sd' ')"
  echo "  $PRA_CIBLE : $(ssh_labo "du -s --apparent-size /tank/$d | cut -f1; find /tank/$d | wc -l" | paste -sd' ')"
done
echo "=== $(date -Is) FIN"

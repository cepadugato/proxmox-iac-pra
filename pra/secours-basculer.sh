#!/usr/bin/env bash
# secours-basculer.sh : bascule de production vers le Proxmox de secours (feuille 5.15, D27), APRÈS que pve a été
# débranché du réseau (geste de l'admin). Le serveur de secours garde son adresse d'installation (accès du poste, certificat)
# et prend EN PLUS 10.0.0.10/24, l'adresse de pve ; puis les services démarrent dans l'ordre de pra/perimetre.yaml.
#   pra/secours-basculer.sh          simulation : vérifie que 10.0.0.10 ne répond plus, rien n'est changé
#   pra/secours-basculer.sh --oui    ajoute 10.0.0.10 (persistant), labo_started = true, démarrage ordonné, plan tofu
#   pra/secours-basculer.sh --retour --oui   RETOUR ARRIÈRE : arrête les invités, retire 10.0.0.10 ; ensuite rebrancher pve
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJ="$(cd "$DIR/.." && pwd)"
export PRA_CIBLE=secours
. "$DIR/lib-ssh-labo.sh"
IP_PVE=10.0.0.10
oui=0; retour=0
for a in "$@"; do case "$a" in --oui) oui=1 ;; --retour) retour=1 ;; *) echo "option inconnue : $a" >&2; exit 2 ;; esac; done
verifier_cible || { echo "REFUS : serveur de secours injoignable" >&2; exit 4; }
lire() { sed -n "s/^$1:[[:space:]]*//p" "$DIR/perimetre.yaml" | head -1; }

if [ "$retour" -eq 1 ]; then
  [ "$oui" -eq 1 ] || { echo "[SIMUL] arrêt des invités du périmètre, retrait de $IP_PVE du secours ; relancer avec --retour --oui"; exit 0; }
  echo "== retour arrière : arrêt des invités (ordre inverse), puis retrait de $IP_PVE"
  ids="$(lire vm) $(lire vague3) $(lire vague2) $(lire vague1)"
  ssh_labo bash -s -- "$IP_PVE" $ids <<'SECOURS'
ip_pve="$1"; shift
for i in "$@"; do
  if qm status "$i" >/dev/null 2>&1; then qm shutdown "$i" --timeout 60 || qm stop "$i"
  elif pct status "$i" >/dev/null 2>&1; then pct shutdown "$i" --timeout 60 || pct stop "$i"; fi
done
grep -v "^[[:space:]]*address $ip_pve/24" /etc/network/interfaces > /etc/network/interfaces.nouveau && mv /etc/network/interfaces.nouveau /etc/network/interfaces
ifreload -a; ip -br a show vmbr0
SECOURS
  sed -i 's/^labo_started[[:space:]]*=.*/labo_started     = false # retour arrière (secours-basculer.sh --retour)/' "$PROJ/tofu/secours.tfvars"
  echo "fait : invités du secours arrêtés, $IP_PVE retirée. Rebrancher maintenant le câble de pve."
  exit 0
fi

echo "== 1. pve doit être débranché : $IP_PVE ne doit plus répondre sur le réseau"
if ssh_labo "ip -br a show vmbr0 | grep -q ' $IP_PVE/'"; then echo "le secours porte déjà $IP_PVE"
else
  r="$(ssh_labo "ip neigh flush to $IP_PVE dev vmbr0 2>/dev/null; ping -c 3 -W 1 $IP_PVE >/dev/null 2>&1 && echo REPOND || echo MUET; (command -v arping >/dev/null && arping -c 3 -w 4 -I vmbr0 $IP_PVE >/dev/null 2>&1 && echo ARP-REPOND) || true")"
  echo "$r"
  grep -qE 'REPOND|ARP-REPOND' <<<"$r" && grep -vq MUET <<<"$r" && { echo "ARRÊT : $IP_PVE répond encore : pve n'est pas débranché" >&2; exit 3; }
  grep -q ARP-REPOND <<<"$r" && { echo "ARRÊT : $IP_PVE répond en ARP : pve n'est pas débranché" >&2; exit 3; }
fi
[ "$oui" -eq 1 ] || { echo "à sec : relancer avec --oui pour prendre $IP_PVE et démarrer les services"; exit 0; }

echo "== 2. adresse de pve sur le secours (persistante)"
ssh_labo bash -s -- "$IP_PVE" <<'SECOURS'
set -e
ip_pve="$1"
# ajoutée APRÈS l'adresse d'installation, qui reste l'adresse principale du serveur
if ! grep -q "address $ip_pve/24" /etc/network/interfaces; then
  awk -v a="	address $ip_pve/24" '{print} /^iface vmbr0 inet static/{s=1} s && /^[[:space:]]+address /{print a; s=0}' /etc/network/interfaces > /etc/network/interfaces.nouveau
  grep -q "address $ip_pve/24" /etc/network/interfaces.nouveau && mv /etc/network/interfaces.nouveau /etc/network/interfaces
fi
ifreload -a; ip -br a show vmbr0
# annonce ARP gratuite : la box et les postes oublient tout de suite l'ancienne MAC de pve
command -v arping >/dev/null && arping -U -c 3 -I vmbr0 "$ip_pve" >/dev/null 2>&1 || true
SECOURS

echo "== 3. démarrage ordonné des services"
sed -i 's/^labo_started[[:space:]]*=.*/labo_started     = true # bascule faite (secours-basculer.sh)/' "$PROJ/tofu/secours.tfvars"
bash "$DIR/restaurer-labo.sh" --demarrer --oui

echo "== 4. le code décrit de nouveau la machine"
rc=0; out="$(cd "$PROJ" && ./tofu-cible.sh secours plan -no-color -detailed-exitcode 2>&1)" || rc=$?
grep -E "Plan:|No changes|Error" <<<"$out" || true; echo "plan rc=$rc (0 = le code décrit le secours)"
echo "ensuite : bash pra/verifs.sh (PRA_CIBLE=secours) ; services joignables à leurs adresses habituelles"

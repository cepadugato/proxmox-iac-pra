#!/usr/bin/env bash
# lib-ssh-labo.sh : SEULE voie du poste vers le labo PRA (feuille 5.14a, D24 (2)). Options ssh figées.
# Usage exécuté : pra/lib-ssh-labo.sh <commande distante...>   |   pra/lib-ssh-labo.sh --scp <args scp...>
# Usage sourcé  : . pra/lib-ssh-labo.sh ; ssh_labo <commande...> ; scp_labo <args...>
# Cible root@10.255.70.2. Clé ~/.ssh/pra-lab, empreinte dans ~/.ssh/known_hosts-pra-lab (relevée à la console, 5.14b).
# Aucun autre script de pra/ n'appelle ssh ou scp vers le labo (tests/test-poste-labo.sh).
# PRA_CIBLE=secours (feuille 5.15, D27) : même voie vers un vrai Proxmox de secours ; adresse et nœud lus dans
# ~/.config/infra-as-code/secours.conf (SECOURS_IP=, SECOURS_NOEUD=, écrit par pra/secours-preparer.sh), clé ~/.ssh/pra-secours,
# empreinte ~/.ssh/known_hosts-pra-secours. Sans PRA_CIBLE : le labo, comme avant.
PRA_CIBLE="${PRA_CIBLE:-labo}"
case "$PRA_CIBLE" in
  labo) LABO_IP="10.255.70.2"; CIBLE_NOEUD="pra-lab"; _cle="$HOME/.ssh/pra-lab"; _kh="$HOME/.ssh/known_hosts-pra-lab" ;;
  secours)
    _sc="$HOME/.config/infra-as-code/secours.conf"
    [ -r "$_sc" ] || { echo "cible secours non préparée : $_sc absent (pra/secours-preparer.sh)" >&2; return 2 2>/dev/null || exit 2; }
    LABO_IP="$(sed -n 's/^SECOURS_IP=\([0-9.]*\)$/\1/p' "$_sc" 2>/dev/null | head -1)"
    CIBLE_NOEUD="$(sed -n 's/^SECOURS_NOEUD=\([A-Za-z0-9-]*\)$/\1/p' "$_sc" 2>/dev/null | head -1)"
    [[ "$LABO_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && [ -n "$CIBLE_NOEUD" ] ||
      { echo "cible secours non préparée ou illisible : $_sc (pra/secours-preparer.sh)" >&2; return 2 2>/dev/null || exit 2; }
    _cle="$HOME/.ssh/pra-secours"; _kh="$HOME/.ssh/known_hosts-pra-secours" ;;
  *) echo "PRA_CIBLE inconnue : $PRA_CIBLE (labo|secours)" >&2; return 2 2>/dev/null || exit 2 ;;
esac
LABO_CIBLE="root@${LABO_IP}"
LABO_SSH_OPTS=(-F none -i "$_cle"
  -o IdentitiesOnly=yes -o BatchMode=yes -o ForwardAgent=no -o ForwardX11=no
  -o ClearAllForwardings=yes -o PermitLocalCommand=no -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$_kh")
ssh_labo() { ssh "${LABO_SSH_OPTS[@]}" "$LABO_CIBLE" "$@"; }
# garde avant toute écriture : labo = isolement prouvé (poste-labo.sh --verifier) ; secours = hôte joint avec l'empreinte ssh enregistrée
verifier_cible() {
  if [ "$PRA_CIBLE" = labo ]; then bash "$(dirname "${BASH_SOURCE[0]}")/poste-labo.sh" --verifier >/dev/null
  else ssh_labo true; fi
}
# fichier de variables OpenTofu de la cible (stockage, gabarit)
TFVARS_CIBLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tofu/$PRA_CIBLE.tfvars"
scp_labo() { scp "${LABO_SSH_OPTS[@]}" "$@"; }
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --scp) shift; scp_labo "$@" ;;
    "") echo "usage : lib-ssh-labo.sh <commande distante> | --scp <args>" >&2; exit 2 ;;
    *) ssh_labo "$@" ;;
  esac
  exit $?
fi

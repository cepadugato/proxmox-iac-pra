#!/usr/bin/env bash
# labo-jeton.sh : utilisateur et jeton OpenTofu du labo, mêmes droits que sur pve (feuille 5.6b, commandes de 3.2).
#   labo-jeton.sh            simulation : affiche ce qui serait fait
#   labo-jeton.sh --oui      rôle TofuCT (privilèges relus sur pve), tofu-rw@pve, jeton « ecriture » privsep=1,
#                            ACL sur /vms/<vmid> du périmètre, /storage/<datastore labo>, /storage/local,
#                            /sdn/zones/localnetwork, /nodes/pra-lab ; secret du jeton écrit dans labo.env (600)
#   labo-jeton.sh --acl      liste les ACL du labo et les compare à la liste attendue (exit 0 si identiques)
# Seule voie vers le labo : pra/lib-ssh-labo.sh, après « pra/poste-labo.sh --verifier ». Le secret ne s'affiche jamais :
# sortie JSON de pveum → jq → fichier temporaire 600 → labo.env. Idempotent : ce qui existe est laissé en place.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-ssh-labo.sh"
CONF="$HOME/.config/infra-as-code"; ENV="$CONF/$PRA_CIBLE.env"
T='tofu-rw@pve!ecriture'; U='tofu-rw@pve'; NOEUD="$CIBLE_NOEUD"
lire() { sed -n "s/^$1:[[:space:]]*//p" "$DIR/perimetre.yaml" | head -1; }
ds="$(sed -n 's/^datastore[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS_CIBLE")"
chemins=()
for i in $(lire vague1) $(lire vague2) $(lire vague3); do chemins+=("/vms/$i"); done
chemins+=("/storage/$ds" /storage/local /sdn/zones/localnetwork "/nodes/$NOEUD")
chemins=($(printf '%s\n' "${chemins[@]}" | awk '!v[$0]++'))

attendu() { for p in "${chemins[@]}"; do printf '%s user %s TofuCT\n%s token %s TofuCT\n' "$p" "$U" "$p" "$T"; done | sort; }
obtenu() {
  ssh_labo 'pveum acl list --output-format json' |
    jq -r '.[] | "\(.path) \(.type) \(.ugid) \(.roleid)"' | sort
}

case "${1:-}" in
  --acl)
    verifier_cible
    if diff <(attendu) <(obtenu); then echo "ACL du labo = attendu (${#chemins[@]} chemins, utilisateur + jeton)"; exit 0
    else echo "ACL du labo ≠ attendu (diff ci-dessus : < attendu, > labo)"; exit 1; fi ;;
  --oui) ;;
  "") echo "[SIMUL] rôle TofuCT, $U, jeton $T privsep=1, ACL : ${chemins[*]}, secret → $ENV"; echo "à sec : relancer avec --oui"; exit 0 ;;
  *) echo "usage : $0 [--oui|--acl]" >&2; exit 2 ;;
esac

verifier_cible || { echo "REFUS : cible $PRA_CIBLE non vérifiée" >&2; exit 4; }
privs="$(ssh -o BatchMode=yes pve 'pveum role list --output-format json' | jq -r '.[] | select(.roleid=="TofuCT") | .privs')"
[ -n "$privs" ] || { echo "rôle TofuCT introuvable sur pve" >&2; exit 1; }
echo "privilèges de TofuCT relus sur pve : $privs"

ssh_labo bash -s -- "$(printf '%q' "$privs")" "$(printf '%q' "$U")" <<'LABO'
set -euo pipefail
privs="$1"; U="$2"
if pveum role list --output-format json | grep -q '"TofuCT"'; then pveum role modify TofuCT --privs "$privs"; echo "rôle TofuCT : privilèges alignés"
else pveum role add TofuCT --privs "$privs"; echo "rôle TofuCT : créé"; fi
if pveum user list --output-format json | grep -q "\"$U\""; then echo "utilisateur $U : existe"
else pveum user add "$U" --comment 'OpenTofu ecriture limitee CT (feuille 5.6b, labo PRA)'; echo "utilisateur $U : créé"; fi
LABO

if ssh_labo "pveum user token list $U --output-format json" | jq -e '.[] | select(.tokenid=="ecriture")' >/dev/null; then
  if [ -s "$ENV" ]; then echo "jeton $T : existe, labo.env présent (conservé)"
  else echo "jeton $T existe dans le labo mais labo.env manque : secret perdu ; « pveum user token delete $U ecriture » puis relancer" >&2; exit 1; fi
else
  ( umask 077; mkdir -p "$CONF"
    tmp="$(mktemp "$CONF/.labo.XXXXXX")"; trap 'rm -f "$tmp"' EXIT
    ssh_labo "pveum user token add $U ecriture --privsep 1 --output-format json" | jq -r .value > "$tmp"
    grep -Eqx '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$tmp"
    { printf '%s' "PROXMOX_VE_API_TOKEN=$T="; cat "$tmp"; echo; } > "$ENV"
    chmod 600 "$ENV" )
  echo "jeton $T : créé, secret écrit dans $ENV (non affiché)"
fi

for p in "${chemins[@]}"; do
  ssh_labo "pveum acl modify $(printf '%q' "$p") --roles TofuCT --users $U && pveum acl modify $(printf '%q' "$p") --roles TofuCT --tokens $(printf '%q' "$T")"
done
echo "ACL posées sur ${#chemins[@]} chemins"
stat -c '%a %n' "$ENV"
ls -A "$CONF" | grep -c '^\.labo\.' || true

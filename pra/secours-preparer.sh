#!/usr/bin/env bash
# secours-preparer.sh : prépare un vrai Proxmox fraîchement installé comme cible « secours » du PRA (feuille 5.15, D27).
#   pra/secours-preparer.sh <ip>            simulation : contrôles en lecture, rien n'est écrit
#   pra/secours-preparer.sh <ip> --oui      écrit secours.conf, ponts vmbr1/vmbr2, dossiers des montages liés, gabarit,
#                                           jeton tofu-rw (labo-jeton.sh), CA, secours.tfvars, empreinte, init tofu
# Préalable (gestes de l'admin, PROCEDURE-PRA.md) : Proxmox installé ; clé ~/.ssh/pra-secours posée par
#   ssh-copy-id -i ~/.ssh/pra-secours.pub -o IdentitiesOnly=yes -o UserKnownHostsFile=~/.ssh/known_hosts-pra-secours root@<ip>
#   après avoir comparé l'empreinte proposée à celle lue à la console du serveur.
# Idempotent : ce qui existe est laissé en place.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJ="$(cd "$DIR/.." && pwd)"
CONF="$HOME/.config/infra-as-code"
TEMPLATE="${PRA_TEMPLATE:-$HOME/pra-tirage/template/debian-13-standard_13.6-1_amd64.tar.zst}"
ip="${1:-}"; oui=0; [ "${2:-}" = --oui ] && oui=1
[[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "usage : $0 <ip du serveur de secours> [--oui]" >&2; exit 2; }
case "$ip" in 10.255.70.2) [ "${PRA_REPETITION_LABO:-}" = 1 ] || { echo "REFUS : $ip est le labo (répétition : PRA_REPETITION_LABO=1)" >&2; exit 3; } ;;
  127.*|10.255.70.*) echo "REFUS : $ip est réservée (tunnel de pve ou labo)" >&2; exit 3 ;; esac
[ -r "$HOME/.ssh/pra-secours" ] && [ -s "$HOME/.ssh/known_hosts-pra-secours" ] ||
  { echo "clé ~/.ssh/pra-secours ou empreinte ~/.ssh/known_hosts-pra-secours absente : faire d'abord le geste ssh-copy-id (PROCEDURE-PRA.md)" >&2; exit 2; }
[ -s "$TEMPLATE" ] || { echo "gabarit absent : $TEMPLATE" >&2; exit 2; }

# connexion directe à l'adresse donnée (secours.conf pas encore écrit) : mêmes options figées que lib-ssh-labo.sh
SO=(-F none -i "$HOME/.ssh/pra-secours" -o IdentitiesOnly=yes -o BatchMode=yes -o ForwardAgent=no -o ForwardX11=no
    -o ClearAllForwardings=yes -o PermitLocalCommand=no -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$HOME/.ssh/known_hosts-pra-secours")
s() { ssh "${SO[@]}" "root@$ip" "$@"; }

echo "== 1. relevé du serveur $ip"
noeud="$(s hostname -s)"; echo "nœud : $noeud"
[[ "$noeud" =~ ^[A-Za-z0-9-]+$ ]] || { echo "nom de nœud inattendu : $noeud" >&2; exit 1; }
[ "$noeud" != pve ] || echo "ATTENTION : le serveur s'appelle « pve » comme la production ; recommandé : pve-secours"
s pveversion
stockages="$(s 'pvesm status --content rootdir' | awk 'NR>1 && $3=="active"{print $1}')"
echo "stockages acceptant les CT : $(tr '\n' ' ' <<<"$stockages")"
ds=""; for c in local-lvm local-zfs; do grep -qx "$c" <<<"$stockages" && { ds="$c"; break; }; done
[ -n "$ds" ] || ds="$(head -1 <<<"$stockages")"
[ -n "$ds" ] || { echo "aucun stockage actif pour les CT" >&2; exit 1; }
echo "stockage retenu : $ds"
s "pvesm status | awk 'NR==1 || \$1==\"$ds\" || \$1==\"local\"'; df -h /root | tail -1; free -g | sed -n 2p"
fp_ssh="$(s 'openssl x509 -noout -fingerprint -sha256 -in /etc/pve/local/pve-ssl.pem' | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')"
san="$(s 'openssl x509 -noout -ext subjectAltName -in /etc/pve/local/pve-ssl.pem' | tr -d ' \n')"
grep -q "IPAddress:$ip" <<<"$san" && echo "certificat : SAN contient $ip" || echo "ATTENTION : SAN sans $ip ($san) ; « pvecm updatecerts --force » sur le serveur puis relancer"

if [ "$oui" -ne 1 ]; then
  echo "[SIMUL] secours.conf (SECOURS_IP=$ip, SECOURS_NOEUD=$noeud) ; ponts vmbr1 vmbr2 ; dossiers /tank/miroir-apt /tank/scripts-http /tank/partage/Fiches /tank/iso-netboot /root/pra/clair"
  echo "[SIMUL] gabarit $(basename "$TEMPLATE") ; jeton tofu-rw@pve!ecriture ; CA → $CONF/secours-ca.pem ; tofu/secours.tfvars (datastore $ds, labo_started false) ; empreinte ; init"
  echo "à sec : relancer avec --oui"; exit 0
fi

echo "== 2. secours.conf"
mkdir -p "$CONF"; ( umask 077; printf 'SECOURS_IP=%s\nSECOURS_NOEUD=%s\n' "$ip" "$noeud" > "$CONF/secours.conf" ); cat "$CONF/secours.conf"

echo "== 3. réseau et dossiers à l'identique de pve"
s 'set -e
for b in vmbr1 vmbr2; do
  grep -qs "^auto $b" /etc/network/interfaces /etc/network/interfaces.d/* || printf "\nauto %s\niface %s inet manual\n\tbridge-ports none\n\tbridge-stp off\n\tbridge-fd 0\n" $b $b >> /etc/network/interfaces
done
ifreload -a; ip -br link show type bridge
mkdir -p /root/pra/clair'
# dossiers des montages liés, avec les propriétaires de pve (sinon un CT non privilégié n'y écrit pas : apt-cacher-ng du 115)
s "set -e; $(awk '$1 ~ /^\/tank\// {printf "mkdir -p %s && chown %s:%s %s && chmod %s %s; ", $1,$2,$3,$1,$4,$1}' "$DIR/montages-lies.tsv") printf \"Serveur de secours : dossiers liés de pve, VIDES ici (non sauvegardés, feuille 5.16).\\n\" > /tank/LISEZMOI-secours.txt; ls -ld /tank/*"

echo "== 4. gabarit des coquilles"
nom="$(basename "$TEMPLATE")"; h="$(sha256sum "$TEMPLATE" | cut -d' ' -f1)"
if [ "$(s "sha256sum /var/lib/vz/template/cache/$nom 2>/dev/null | cut -d' ' -f1")" = "$h" ]; then echo "gabarit déjà présent"
else scp "${SO[@]}" "$TEMPLATE" "root@$ip:/var/lib/vz/template/cache/$nom.partiel"
  s "cd /var/lib/vz/template/cache && echo '$h  $nom.partiel' | sha256sum -c --quiet && mv $nom.partiel $nom" || { echo "ARRÊT : gabarit non vérifié sur le serveur" >&2; exit 1; }
  echo "gabarit copié, sha256 vérifié"; fi

echo "== 5. CA du serveur et fichier de variables"
s 'cat /etc/pve/pve-root-ca.pem' > "$CONF/secours-ca.pem.tmp" && mv "$CONF/secours-ca.pem.tmp" "$CONF/secours-ca.pem"
cat > "$PROJ/tofu/secours.tfvars" <<EOF
# Cible secours (feuille 5.15, D27) : écrit par pra/secours-preparer.sh le $(date -Is). Aucun secret.
proxmox_endpoint = "https://$ip:8006/"
node             = "$noeud"
datastore        = "$ds"
labo_started     = false # services démarrés après la bascule d'adresse (PROCEDURE-PRA.md)
cible            = "secours"
template_file_id = "local:vztmpl/$nom"
features_root    = false # keyctl/fuse et montages liés : root@pam seulement ; remis par pct restore
EOF
echo "écrit : tofu/secours.tfvars (datastore $ds)"

echo "== 6. jeton OpenTofu (mêmes droits que sur pve)"
PRA_CIBLE=secours bash "$DIR/labo-jeton.sh" --oui | grep -v -i -E 'secret|value'

echo "== 7. empreinte du certificat (comparée à celle lue par ssh) et init"
srv="$(cd "$PROJ" && ./tofu-cible.sh secours empreinte)"
[ "$srv" = "$fp_ssh" ] || { echo "ARRÊT : empreinte servie ($srv) ≠ empreinte lue par ssh ($fp_ssh)" >&2; exit 3; }
[ -e "$CONF/empreinte-secours.sha256" ] && rm -f "$CONF/empreinte-secours.sha256"
(cd "$PROJ" && ./tofu-cible.sh secours enregistrer-empreinte)
(cd "$PROJ" && ./tofu-cible.sh secours init -input=false -no-color | tail -1)
echo "OK : cible secours prête ($ip, nœud $noeud, stockage $ds)"

#!/usr/bin/env bash
# secours.sh : PRA de bout en bout vers un Proxmox neuf, en UNE commande lancée par l'admin dans son terminal (feuille 5.15).
#   bash pra/secours.sh <ip>            accès, préparation, restauration (services arrêtés), puis bascule après débranchement
#                                       de pve, puis contrôle ; s'arrête et demande à chaque geste humain
#   bash pra/secours.sh --retour        retour arrière : arrête le secours, lui retire 10.0.0.10 ; rebrancher pve ensuite
# Reprise : relancer la même commande ; chaque étape déjà faite est sautée (scripts idempotents).
# Lancer la commande vaut accord pour les restaurations forcées des coquilles neuves créées par cette même commande.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJ="$(cd "$DIR/.." && pwd)"
cd "$PROJ" || exit 2
export PRA_CIBLE=secours
LOG="$PROJ/recettes/preuve-secours-$(date +%Y%m%d).log"
exec > >(tee -a "$LOG") 2>&1
T0=$(date +%s)
etape() { echo; echo "=== [$(date +%T), +$(( ($(date +%s) - T0) / 60 )) min] $*"; }
stop() { echo; echo "ARRÊT : $*"; echo "Corriger puis relancer la même commande (les étapes faites seront sautées)."; exit 1; }
demander() { local r; read -r -p "$1 (oui/non) : " r </dev/tty; [ "$r" = oui ]; }

if [ "${1:-}" = --retour ]; then
  . "$DIR/lib-ssh-labo.sh"
  bash "$DIR/hote-auto.sh" --arreter || true
  # FOG (.11) et le nom pve.local sont repris par pve au rebranchement : le secours les rend d'abord
  ssh_labo "systemctl disable --now pra-pve-smb smbd nmbd nfs-server 2>/dev/null; qm set 110 --onboot 0 >/dev/null 2>&1; qm shutdown 110 --timeout 60 2>/dev/null || qm stop 110 2>/dev/null; systemctl disable --now pra-pve-local 2>/dev/null; true"
  bash "$DIR/secours-basculer.sh" --retour --oui && echo "→ Tu peux rebrancher le câble de pve."; exit $?
fi
ip="${1:-}"
[[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "usage : bash pra/secours.sh <ip du serveur de secours> | --retour" >&2; exit 2; }
# répétition sur le labo imbriqué : seule 10.255.70.2 est admise, et seulement avec PRA_REPETITION_LABO=1
case "$ip" in 10.255.70.2) [ "${PRA_REPETITION_LABO:-}" = 1 ] || { echo "REFUS : $ip est le labo (répétition : PRA_REPETITION_LABO=1)" >&2; exit 3; } ;;
  127.*|10.255.70.*|10.0.0.10) echo "REFUS : $ip est réservée (pve, son tunnel ou le labo)" >&2; exit 3 ;; esac
echo "PRA vers le serveur de secours $ip — $(date -Is) — journal : $LOG"

etape "1/7 Accès du poste au serveur"
KH="$HOME/.ssh/known_hosts-pra-secours"
if ! ssh -F none -i "$HOME/.ssh/pra-secours" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$KH" "root@$ip" true 2>/dev/null; then
  echo "Comparer l'empreinte qui va s'afficher à celle lue à l'écran du serveur, puis taper le mot de passe root du serveur."
  ssh-copy-id -i "$HOME/.ssh/pra-secours.pub" -o IdentitiesOnly=yes -o "UserKnownHostsFile=$KH" "root@$ip" </dev/tty || stop "accès ssh non ouvert"
fi
bash phrase-session.sh etat >/dev/null 2>&1 || bash phrase-session.sh charger || stop "phrase d'état et clé GPG non chargées"

etape "2/7 Préparation du serveur"
bash "$DIR/secours-preparer.sh" "$ip" --oui || stop "préparation"
. "$DIR/lib-ssh-labo.sh"
echo "Dépôts apt : enterprise désactivé, pve-no-subscription (comme le labo), puis liste des paquets"
ssh_labo bash -s <<'APT' || stop "dépôts apt"
set -e
cd /etc/apt/sources.list.d
for f in pve-enterprise.sources ceph.sources; do
  [ -f "$f" ] && { grep -q '^Enabled: no' "$f" || echo 'Enabled: no' >> "$f"; }
done
[ -f proxmox.sources ] || printf '%s\n' 'Types: deb' 'URIs: http://download.proxmox.com/debian/pve' 'Suites: trixie' \
  'Components: pve-no-subscription' 'Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg' > proxmox.sources
apt-get update -q </dev/null >/tmp/apt-update.log 2>&1 && echo "apt-get update : OK" || { echo "AVERTISSEMENT : apt-get update en échec (pas d'Internet ?), paquets du passage en secours :"; tail -3 /tmp/apt-update.log; }
APT

ids_perimetre="$(sed -n 's/^vague[123]:[[:space:]]*//p' "$DIR/perimetre.yaml")"
tout_restaure=1; for i in $ids_perimetre; do [ "$i" = 9020 ] && continue; ssh_labo "test -e /root/pra/restaure-$i" || { tout_restaure=0; break; }; done
etape "3/7 Déchiffrement des archives vers le serveur (la clé reste sur le poste)"
if [ "$tout_restaure" = 1 ]; then echo "tous les CT sont déjà restaurés : déchiffrement sauté"
else
  bash "$DIR/perimetre.sh" | tail -4
  bash "$DIR/archives-vers-labo.sh" --oui | grep -E "bilan|comptage|clair|ARRÊT|VMID .* : OK"; [ "${PIPESTATUS[0]}" -eq 0 ] || stop "déchiffrement"
fi

etape "4/7 CT privilégié 9020 et VM 106"
. "$DIR/lib-ssh-labo.sh"
manque=""; for i in 9020 106; do ssh_labo "pct status $i >/dev/null 2>&1 || qm status $i >/dev/null 2>&1" || manque+=" $i"; done
[ -z "$manque" ] && echo "déjà restaurés" || { bash "$DIR/restaurer-labo.sh" --oui $manque || stop "restauration de$manque"; }
echo "FOG (VM 110) et partage de l'hôte :"
bash "$DIR/fog-partage.sh" --oui || stop "FOG ou partage"
echo "Automatisation de l'hôte (scripts, minuteries, courriel, sauvegarde) :"
bash "$DIR/hote-auto.sh" --oui || stop "automatisation de l'hôte"

etape "5/7 Coquilles des CT (OpenTofu), puis restauration de chacun, services arrêtés"
cp tofu/import-ct9020.tf.importe tofu/import-ct9020.tf
p="$(./tofu-cible.sh secours plan -no-color -out=secours.tfplan 2>&1)"; rc=$?; echo "$p" | grep -E "Plan:|No changes|Error|REFUS"
# une erreur ou un refus rend le plan inapplicable : rien n'est restauré sans les coquilles
if [ "$rc" -ne 0 ] || grep -qE "^Error|REFUS" <<<"$p"; then rm -f tofu/import-ct9020.tf tofu/secours.tfplan; stop "plan des coquilles en erreur (voir ci-dessus)"
elif grep -q "No changes" <<<"$p"; then echo "coquilles déjà créées"
elif grep -qE "Plan: (1 to import, )?[0-9]+ to add, 0 to change, 0 to destroy" <<<"$p"; then
  demander "Créer ces coquilles sur le serveur de secours ?" || { rm -f tofu/import-ct9020.tf tofu/secours.tfplan; stop "refusé par l'admin"; }
  a="$(./tofu-cible.sh secours apply -no-color secours.tfplan 2>&1)"; echo "$a" | grep -E "Apply complete|Error"
  grep -q "Apply complete" <<<"$a" || { rm -f tofu/import-ct9020.tf tofu/secours.tfplan; stop "création des coquilles en échec"; }
else rm -f tofu/import-ct9020.tf tofu/secours.tfplan; stop "plan inattendu (changement ou destruction) : ne rien appliquer, me le montrer"; fi
rm -f tofu/import-ct9020.tf tofu/secours.tfplan
ids=""; for i in $(sed -n 's/^vague[123]:[[:space:]]*//p' "$DIR/perimetre.yaml"); do
  [ "$i" = 9020 ] && continue
  # repère posé sur le serveur après chaque restauration réussie : une relance ne réécrase pas un CT déjà restauré
  ssh_labo "test -e /root/pra/restaure-$i" || ids+=" $i"
done
if [ -n "$ids" ]; then
  # AUTORISÉ-PAR-FRED : l'admin lance lui-même pra/secours.sh, qui ne force que les coquilles neuves créées à l'étape 5
  bash "$DIR/restaurer-labo.sh" --oui $ids || stop "restauration forcée"
  for i in $ids; do ssh_labo "touch /root/pra/restaure-$i"; done
else echo "CT déjà restaurés"; fi

echo "Ménage : archives en clair (tout est restauré), puis place libre pour les dossiers liés"
ssh_labo "find /root/pra/clair -type f -delete; df -BG --output=avail / | tail -1 | tr -dc 0-9" > /tmp/pra-libre.txt
libre="$(cat /tmp/pra-libre.txt)"; echo "place libre sur / : ${libre} Go (dossiers liés : ~28 Go)"
[ "${libre:-0}" -ge 32 ] || echo "AVERTISSEMENT : moins de 32 Go libres sur / : la copie du miroir apt risque de remplir le disque"
echo "Dossiers liés (miroir apt, ISO et pilotes netbootxyz, hors sauvegarde) : copie depuis pve tant qu'il est branché"
if [ "${PRA_REPETITION_LABO:-}" = 1 ]; then echo "répétition labo : copie sautée (le labo isolé est hors de portée de pve)"
elif ssh -n -o ConnectTimeout=8 -o BatchMode=yes pve true 2>/dev/null; then
  if ssh_labo "test -f /root/pra/donnees-liees-copiees"; then echo "déjà copiés"
  else bash "$DIR/copier-donnees-liees.sh" && ssh_labo "touch /root/pra/donnees-liees-copiees" || echo "AVERTISSEMENT : copie incomplète (relancer secours.sh avant de débrancher pve)"; fi
else echo "AVERTISSEMENT : pve injoignable : miroir apt, ISO netbootxyz restent vides (à re-télécharger)"; fi

etape "6/7 BASCULE"
echo "Tout est restauré et arrêté. Débranche MAINTENANT le câble réseau de pve (sans l'éteindre)."
demander "Câble de pve débranché ?" || stop "bascule reportée : relancer quand pve sera débranché"
bash "$DIR/secours-basculer.sh" --oui || stop "bascule (pve répond encore ? rien n'a été changé)"
bash "$DIR/fog-partage.sh" --demarrer || stop "démarrage de FOG ou publication de pve.local"
bash "$DIR/hote-auto.sh" --demarrer || stop "activation des minuteries de l'hôte"

etape "7/7 Contrôle des services contre la référence de pve"
sleep 60; bash "$DIR/verifs.sh" | grep -vE "^\[OK\] [0-9]+ port 22 "
echo; echo "Pile complète comparée à pve (invités, configurations, services, ports, minuteries, dossiers liés) :"
bash "$DIR/comparer-pile.sh" | grep -E "^==|seulement|TOTAL"
etape "FIN : durée $(( ($(date +%s) - T0) / 60 )) min. Tester au navigateur depuis un PC de l'asso. Retour arrière : bash pra/secours.sh --retour"
echo "Ménage des archives en clair sur le serveur : PRA_CIBLE=secours bash pra/lib-ssh-labo.sh 'find /root/pra/clair -type f -delete'"

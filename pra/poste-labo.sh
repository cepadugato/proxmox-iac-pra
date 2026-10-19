#!/usr/bin/env bash
# poste-labo.sh : lien poste <-> labo PRA, 10.255.70.0/30 sur virbr-pra (feuille 5.14a, D23, D24 (2)).
#   poste-labo.sh --oui                      pose (root : sudo de l'admin) : sysctls, table nft, arping -D, adresse, --verifier
#   poste-labo.sh --retirer --oui            retrait inverse : adresse, table, sysctls
#   poste-labo.sh --verifier                 garde SANS root : adresse, route, canari TCP et UDP tenté depuis le labo
#   poste-labo.sh --rouge-sans-table --oui   preuve 5.14b SEULEMENT : adresse SANS la table (la sonde doit voir un port ouvert)
# Sans --oui : exit 2, rien n'est lancé. Refus de pose : exit 3. Garde rouge : exit 4 « REFUS isolement : <raison> ».
# Rien de persistant. Variables d'essai : PRA_SANS_ROOT=1 (tests à sec), PRA_CACHE (défaut ~/.cache/pra).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IF="virbr-pra"; ADR="10.255.70.1/30"; IP_POSTE="10.255.70.1"; IP_LABO="10.255.70.2"
NFT="$DIR/pra_poste.nft"; TABLE="pra_poste"
SYSCTLS=("net.ipv4.conf.${IF}.arp_ignore=1" "net.ipv6.conf.${IF}.disable_ipv6=1")
CACHE="${PRA_CACHE:-$HOME/.cache/pra}"; AVANT="$CACHE/sysctl-avant"

mode=pose; oui=0
for a in "$@"; do
  case "$a" in
    --oui) oui=1 ;;
    --retirer) mode=retirer ;;
    --verifier) mode=verifier ;;
    --rouge-sans-table) mode=rouge ;;
    *) echo "option inconnue : $a" >&2; exit 2 ;;
  esac
done

msg() { echo "poste-labo : $*"; }
refus3() { echo "REFUS pose : $*" >&2; }

# ---------- --verifier (sans root) ----------
verifier() {
  . "$DIR/lib-ssh-labo.sh"
  local br; br="$(ip -br a)"
  local sur_if autres
  sur_if="$(grep -E "^${IF}[[:space:]]" <<<"$br" | grep -c "${IP_POSTE}/30")"
  autres="$(grep -v "^${IF}[[:space:]]" <<<"$br" | grep -c "${IP_POSTE}/")"
  if [ "$sur_if" -ne 1 ] || [ "$autres" -ne 0 ]; then
    echo "REFUS isolement : adresse (${ADR} doit être sur ${IF} et nulle part ailleurs)" >&2; return 4
  fi
  if ! ip r get "$IP_LABO" 2>/dev/null | grep -q "dev ${IF}\b"; then
    echo "REFUS isolement : route (${IP_LABO} ne sort pas par ${IF})" >&2; return 4
  fi
  # canari : écouteur TCP et UDP non privilégié, le labo tente de s'y connecter
  local w; w="$(mktemp -d)"
  python3 - "$w/evts" "$w/port" 12 <<'PY' &
import random, select, socket, sys, time
evts, portf, duree = sys.argv[1], sys.argv[2], float(sys.argv[3])
for _ in range(100):
    p = random.randint(40000, 60000)
    t = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        t.bind(("0.0.0.0", p)); u.bind(("0.0.0.0", p)); break
    except OSError:
        t.close(); u.close()
else:
    sys.exit(1)
t.listen(5)
open(portf, "w").write(str(p))
fin = time.time() + duree
while time.time() < fin:
    r, _, _ = select.select([t, u], [], [], 0.2)
    for s in r:
        if s is t:
            c, _ = t.accept(); c.close(); open(evts, "a").write("tcp\n")
        else:
            u.recvfrom(64); open(evts, "a").write("udp\n")
PY
  local lp=$!; local i=0
  while [ ! -s "$w/port" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
  local port; port="$(cat "$w/port" 2>/dev/null)"
  local rc=0 raison="" sortie_tcp rc_tcp
  if [ -z "$port" ]; then
    echo "REFUS isolement : canari-tcp (écouteur du canari impossible à lancer)" >&2; rc=4
  else
    sortie_tcp="$(timeout 20 bash -c '. "$1"; ssh_labo "timeout 3 bash -c \"</dev/tcp/'"$IP_POSTE"'/$2\" 2>/dev/null && echo OUVERT || echo FERME"' _ "$DIR/lib-ssh-labo.sh" "$port" 2>/dev/null)"; rc_tcp=$?
    timeout 20 bash -c '. "$1"; ssh_labo "echo canari >/dev/udp/'"$IP_POSTE"'/$2"' _ "$DIR/lib-ssh-labo.sh" "$port" >/dev/null 2>&1
    sleep 1
    if [ "$rc_tcp" -ne 0 ] || ! grep -q FERME <<<"$sortie_tcp" || grep -q OUVERT <<<"$sortie_tcp"; then
      if grep -q OUVERT <<<"$sortie_tcp"; then raison="canari-tcp (le labo se connecte à ${IP_POSTE})"
      else raison="canari-tcp (preuve impossible : canal ssh vers le labo en échec, rc=$rc_tcp)"; fi
    elif grep -q '^tcp$' "$w/evts" 2>/dev/null; then raison="canari-tcp (l'écouteur a reçu une connexion)"
    elif grep -q '^udp$' "$w/evts" 2>/dev/null; then raison="canari-udp (l'écouteur a reçu un datagramme)"
    fi
    [ -n "$raison" ] && { echo "REFUS isolement : $raison" >&2; rc=4; }
  fi
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  find "$w" -delete 2>/dev/null
  [ "$rc" -eq 0 ] && msg "isolement vérifié (adresse, route, canari TCP et UDP muets)"
  return "$rc"
}

if [ "$mode" = verifier ]; then verifier; exit $?; fi

# ---------- gestes qui modifient : --oui et root exigés ----------
if [ "$oui" -ne 1 ]; then
  echo "à sec : rien n'est fait. Relancer avec --oui (en root, geste de l'admin) : poste-labo.sh [--retirer|--rouge-sans-table] --oui" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ] && [ -z "${PRA_SANS_ROOT:-}" ]; then
  echo "root requis pour poser ou retirer le lien (geste de l'admin)." >&2; exit 2
fi

verifier_utilisateur() { # --verifier sans les droits root : en tant que l'utilisateur d'origine si on est root
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    local h; h="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    runuser -u "$SUDO_USER" -- env HOME="$h" bash "$DIR/poste-labo.sh" --verifier
  else
    bash "$DIR/poste-labo.sh" --verifier
  fi
}

sysctls_poser() {
  mkdir -p "$CACHE"
  if [ ! -e "$AVANT" ]; then
    : > "$AVANT"
    for s in "${SYSCTLS[@]}"; do n="${s%%=*}"; echo "${n}=$(sysctl -n "$n" 2>/dev/null || echo 0)" >> "$AVANT"; done
  fi
  for s in "${SYSCTLS[@]}"; do sysctl -w "$s" >/dev/null; done
}
sysctls_restaurer() {
  [ -e "$AVANT" ] || return 0
  while IFS= read -r l; do [ -n "$l" ] && sysctl -w "$l" >/dev/null; done < "$AVANT"
  rm -f "$AVANT"
}
table_presente() { nft list table inet "$TABLE" >/dev/null 2>&1; }
table_retirer() { table_presente && nft delete table inet "$TABLE"; return 0; }
adresse_presente() { ip -br a | grep -E "^${IF}[[:space:]]" | grep -q "${IP_POSTE}/30"; }
adresse_retirer() { adresse_presente && ip addr del "$ADR" dev "$IF"; return 0; }

retirer() {
  adresse_retirer
  table_retirer
  sysctls_restaurer
  msg "lien retiré (adresse, table, sysctls)"
}
if [ "$mode" = retirer ]; then retirer; exit 0; fi

# ---------- pose : contrôles en lecture seule d'abord (exit 3) ----------
command -v arping >/dev/null 2>&1 || { refus3 "arping absent (sudo apt install iputils-arping)"; exit 3; }
br="$(ip -br a)"
grep -qE "^${IF}[[:space:]]" <<<"$br" || { refus3 "${IF} absente (réseau libvirt lab-pra non démarré ?)"; exit 3; }
grep -E "^${IF}[[:space:]]" <<<"$br" | grep -q "192\.168\.1\." && { refus3 "${IF} porte une adresse 10.0.0.x (conflit avec le Wi-Fi du domicile)"; exit 3; }
grep -E "^${IF}[[:space:]]" <<<"$br" | grep -q "${IP_POSTE}/" && { refus3 "adresse ${ADR} déjà présente sur ${IF} (retirer d'abord)"; exit 3; }
grep -v "^${IF}[[:space:]]" <<<"$br" | grep -q "10\.255\.70\." && { refus3 "10.255.70.0/30 déjà portée par une autre interface"; exit 3; }
ip r | grep "10\.255\.70\." | grep -qv "dev ${IF}\b" && { refus3 "10.255.70.0/30 déjà routée par une autre interface"; exit 3; }

annuler() { # retour arrière d'une pose refusée : table puis sysctls (l'adresse n'est pas encore posée)
  table_retirer; sysctls_restaurer
}

sysctls_poser
if [ "$mode" = pose ]; then
  nft -c -f "$NFT" || { annuler; refus3 "nft -c a refusé $NFT (rien appliqué)"; exit 3; }
  nft -f "$NFT" || { annuler; refus3 "nft -f a échoué"; exit 3; }
  nft list table inet "$TABLE" >/dev/null || { annuler; refus3 "table $TABLE absente après nft -f"; exit 3; }
else
  msg "ATTENTION : mode rouge, adresse posée SANS table (preuve 5.14b). Aucune protection. Retirer aussitôt : --retirer --oui"
fi
if ! arping -D -c 2 -I "$IF" "$IP_POSTE"; then
  annuler; refus3 "arping -D : quelqu'un répond pour ${IP_POSTE} sur ${IF} (adresse dupliquée)"; exit 3
fi
ip addr add "$ADR" dev "$IF" || { annuler; refus3 "ip addr add a échoué"; exit 3; }
if [ "$mode" = rouge ]; then msg "adresse ${ADR} posée sans table (pas de --verifier : il doit être rouge)"; exit 0; fi
verifier_utilisateur; rc=$?
if [ "$rc" -ne 0 ]; then
  msg "garde rouge après pose : retour arrière complet"
  retirer >/dev/null
  exit "$rc"
fi
msg "lien posé : ${ADR} sur ${IF}, table inet ${TABLE}, garde verte"
exit 0

#!/usr/bin/env bash
# Test de pra/poste-labo.sh et pra/lib-ssh-labo.sh (feuille 5.14a, D23/D24) : TOUT À SEC.
# Doubles de ip, nft, sysctl, arping, ssh, scp en tête de PATH ; PATH réduit à ces doubles et à des liens vers les
# outils de base (ni sudo, ni vrai ip/nft/ssh/arping accessibles). Seul effet réseau réel : les écouteurs canari
# du script, sur 0.0.0.0 du poste, et un connect/sendto sur 127.0.0.1 par le double ssh (scénarios « ouvert »).
# Aucun secret, aucun hôte distant. Critères : recettes/criteres-lot5-D24.md § 5.14a.
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; fail=0
trap 'find "$tmp" -delete 2>/dev/null' EXIT
ok() { echo "OK   $1"; }; ko() { echo "FAIL $1"; fail=1; }
P="$d/pra/poste-labo.sh"; L="$d/pra/lib-ssh-labo.sh"

if [ ! -f "$P" ] || [ ! -f "$L" ]; then
  ko "script absent : $( [ -f "$P" ] || echo pra/poste-labo.sh ) $( [ -f "$L" ] || echo pra/lib-ssh-labo.sh )"
  exit 1
fi

# --- outils de base (liens) et doubles ---
UT="$tmp/utils"; DBL="$tmp/dbl"; DBX="$tmp/dbl-sans-arping"; mkdir -p "$UT" "$DBL" "$DBX"
for c in bash grep sed cat mkdir rm date python3 env timeout cut awk tr head sort dirname basename wc id tee ls sleep kill cp mv touch readlink printf true false tail uniq cmp mktemp find; do
  p="$(command -v "$c" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$UT/$c"
done
ecrit() { cat > "$DBL/$1"; chmod +x "$DBL/$1"; }
ecrit ip <<'DBL'
#!/usr/bin/env bash
S="$STUB_DIR"; echo "ip $*" >> "$S/journal"
case "$*" in
  "-br a"|"-br addr") cat "$S/addr.txt" ;;
  "r"|"route") cat "$S/route.txt" ;;
  "r get "*)
    dev=wlan0
    grep -q '^virbr-pra .*10\.255\.70\.1/30' "$S/addr.txt" && dev=virbr-pra
    [ -n "${STUB_ROUTE_DEV:-}" ] && dev="$STUB_ROUTE_DEV"
    echo "$3 dev $dev src 10.255.70.1 uid 1000" ;;
  "addr add "*)
    [ -e "$S/table" ] && echo table=oui > "$S/etat-add" || echo table=non > "$S/etat-add"
    sed -i "s|^\($5 .*\)\$|\1 $3|" "$S/addr.txt"
    echo "10.255.70.0/30 dev $5 proto kernel scope link src 10.255.70.1" >> "$S/route.txt" ;;
  "addr del "*)
    sed -i "s| $3||" "$S/addr.txt"; sed -i '/^10\.255\.70\.0\/30 dev virbr-pra proto kernel/d' "$S/route.txt" ;;
  *) echo "ip double : commande inattendue $*" >&2; exit 99 ;;
esac
DBL
ecrit nft <<'DBL'
#!/usr/bin/env bash
S="$STUB_DIR"; echo "nft $*" >> "$S/journal"
case "$1" in
  -c) exit "${STUB_NFT_C_RC:-0}" ;;
  -f) touch "$S/table" ;;
  list) [ -e "$S/table" ] && { echo "table inet pra_poste {}"; exit 0; } || { echo "Error: No such file or directory" >&2; exit 1; } ;;
  delete)
    grep -q '^virbr-pra .*10\.255\.70\.1/30' "$S/addr.txt" && echo addr=oui > "$S/etat-delete" || echo addr=non > "$S/etat-delete"
    rm -f "$S/table" ;;
  *) echo "nft double : commande inattendue $*" >&2; exit 99 ;;
esac
DBL
ecrit sysctl <<'DBL'
#!/usr/bin/env bash
S="$STUB_DIR"; echo "sysctl $*" >> "$S/journal"
case "$1" in
  -n) cat "$S/sysctl-$2" 2>/dev/null || echo 0 ;;
  -w) n="${2%%=*}"; v="${2#*=}"; echo "$v" > "$S/sysctl-$n"; echo "$n = $v" ;;
  *) exit 99 ;;
esac
DBL
ecrit arping <<'DBL'
#!/usr/bin/env bash
echo "arping $*" >> "$STUB_DIR/journal"; exit "${STUB_ARPING_RC:-0}"
DBL
ecrit ssh <<'DBL'
#!/usr/bin/env bash
echo "ssh $*" >> "$STUB_DIR/journal"
[ -n "${STUB_SSH_RC:-}" ] && exit "$STUB_SSH_RC"
cmd="${@: -1}"
case "${STUB_SSH:-ferme}" in
  tcp-ouvert) case "$cmd" in *'/dev/tcp/'*) bash -c "$(sed 's/10\.255\.70\.1/127.0.0.1/g' <<<"$cmd")"; exit $? ;; esac ;;
  udp-recu)   case "$cmd" in *'/dev/udp/'*) bash -c "$(sed 's/10\.255\.70\.1/127.0.0.1/g' <<<"$cmd")"; exit $? ;; esac ;;
esac
case "$cmd" in *'/dev/tcp/'*) echo FERME ;; esac
exit 0
DBL
ecrit scp <<'DBL'
#!/usr/bin/env bash
echo "scp $*" >> "$STUB_DIR/journal"; exit "${STUB_SSH_RC:-0}"
DBL
cp "$DBL"/* "$DBX"/; rm -f "$DBX/arping"

# --- scénarios (un répertoire d'état neuf à chaque fois) ---
n=0; S=""; H=""
nouveau() { # poste sans lien
  n=$((n + 1)); S="$tmp/etat$n"; H="$tmp/home$n"; mkdir -p "$S" "$H/.cache"
  printf '%s\n' 'lo UNKNOWN 127.0.0.1/8' 'wlan0 UP 10.0.0.21/24' 'virbr0 UP 192.168.100.1/24' 'virbr-pra UP' > "$S/addr.txt"
  echo 'default via 10.0.0.254 dev wlan0' > "$S/route.txt"
  : > "$S/journal"
}
lance() { # lance <args> : poste-labo.sh, doubles seuls dans le PATH ; rc dans $rc, sortie dans $S/sortie
  local chemin="$DBL:$UT"; [ -n "${PATH_SANS_ARPING:-}" ] && chemin="$DBX:$UT"
  env -i PATH="$chemin" HOME="$H" STUB_DIR="$S" PRA_SANS_ROOT=1 PRA_CACHE="$H/.cache/pra" \
    ${STUB_SSH:+STUB_SSH="$STUB_SSH"} ${STUB_NFT_C_RC:+STUB_NFT_C_RC="$STUB_NFT_C_RC"} \
    ${STUB_ARPING_RC:+STUB_ARPING_RC="$STUB_ARPING_RC"} ${STUB_ROUTE_DEV:+STUB_ROUTE_DEV="$STUB_ROUTE_DEV"} \
    ${STUB_SSH_RC:+STUB_SSH_RC="$STUB_SSH_RC"} \
    bash "$P" "$@" > "$S/sortie" 2>&1
  rc=$?
}
J() { cat "$S/journal"; }
a_modif() { grep -qE '^(ip addr (add|del)|sysctl -w|nft (-f|delete))' "$S/journal"; }
ordre() { # ordre <motif>... : première occurrence de chaque motif, dans l'ordre strict du journal
  local last=0 m p
  for p in "$@"; do
    m="$(grep -n -F -- "$p" "$S/journal" | awk -F: -v l="$last" '$1>l{print $1; exit}')"
    [ -n "$m" ] || { echo "   motif absent ou hors ordre : $p"; return 1; }
    last="$m"
  done
}
NFT="$d/pra/pra_poste.nft"
[ -f "$NFT" ] && ok "règles pra/pra_poste.nft présentes" || ko "pra/pra_poste.nft absent"

# (1) refus sans --oui : exit 2, aucune commande lancée
for a in "" "--retirer" "--rouge-sans-table"; do
  nouveau; lance $a
  [ "$rc" -eq 2 ] && [ ! -s "$S/journal" ] && ok "sans --oui ('$a') : exit 2, aucune commande lancée" || ko "sans --oui ('$a') rc=$rc journal=$(wc -l < "$S/journal")"
done
nouveau; lance --inconnue --oui; [ "$rc" -eq 2 ] && ok "option inconnue : exit 2" || ko "option inconnue rc=$rc"

# (2) pose : ordre
nouveau; lance --oui
[ "$rc" -eq 0 ] && ok "pose --oui : exit 0" || { ko "pose --oui rc=$rc"; cat "$S/sortie"; }
if ordre "sysctl -n net.ipv4.conf.virbr-pra.arp_ignore" "sysctl -w net.ipv4.conf.virbr-pra.arp_ignore=1" \
   "sysctl -w net.ipv6.conf.virbr-pra.disable_ipv6=1" "nft -c -f $NFT" "nft -f $NFT" "nft list table inet pra_poste" \
   "arping -D -c 2 -I virbr-pra 10.255.70.1" "ip addr add 10.255.70.1/30 dev virbr-pra" "ssh "; then
  ok "ordre : sysctls (anciennes valeurs lues) -> nft -c -> nft -f -> list -> arping -D -> adresse -> --verifier (ssh)"
else ko "ordre de pose"; J | sed 's/^/   | /'; fi
grep -q 'table=oui' "$S/etat-add" 2>/dev/null && ok "l'adresse est posée alors que la table existe" || ko "adresse posée sans table"
grep -q '^net.ipv4.conf.virbr-pra.arp_ignore=0$' "$H/.cache/pra/sysctl-avant" && grep -q '^net.ipv6.conf.virbr-pra.disable_ipv6=0$' "$H/.cache/pra/sysctl-avant" \
  && ok "anciennes valeurs gardées dans sysctl-avant" || ko "sysctl-avant absent ou incomplet"
! grep -qE '(^| )sudo( |$)' "$S/journal" && ok "aucun sudo dans le journal des doubles" || ko "sudo appelé"
STUB_SSH=ferme lance --verifier; [ "$rc" -eq 0 ] && ok "--verifier après pose : exit 0" || ko "--verifier après pose rc=$rc"

# retrait : ordre inverse
: > "$S/journal"; lance --retirer --oui
[ "$rc" -eq 0 ] && ok "--retirer --oui : exit 0" || ko "--retirer rc=$rc"
ordre "ip addr del 10.255.70.1/30 dev virbr-pra" "nft delete table inet pra_poste" "sysctl -w net.ipv4.conf.virbr-pra.arp_ignore=0" \
  && ok "retrait inverse : adresse -> table -> sysctls restaurés" || { ko "ordre de retrait"; J | sed 's/^/   | /'; }
grep -q 'addr=non' "$S/etat-delete" 2>/dev/null && ok "la table n'est retirée qu'une fois l'adresse partie" || ko "table retirée avec l'adresse encore là"
{ ! grep -q '10.255.70.1/30' "$S/addr.txt" && [ ! -e "$S/table" ] && [ "$(cat "$S/sysctl-net.ipv4.conf.virbr-pra.arp_ignore")" = 0 ] && [ ! -e "$H/.cache/pra/sysctl-avant" ]; } \
  && ok "état final = état initial (adresse, table, sysctls)" || ko "état final différent"

# (3) refus exit 3, un rouge par raison
refus3() { # <libellé> <mot attendu dans la sortie> <rien modifié ? oui|non>
  local lib="$1" mot="$2" mod="$3"
  if [ "$rc" -eq 3 ] && grep -qi -- "$mot" "$S/sortie"; then ok "refus 3 : $lib"; else ko "refus 3 : $lib (rc=$rc)"; sed 's/^/   | /' "$S/sortie"; fi
  ! grep -q '^ip addr add' "$S/journal" && ok "  ... aucune adresse posée ($lib)" || ko "  ... adresse posée malgré le refus ($lib)"
  if [ "$mod" = oui ]; then ! a_modif && ok "  ... rien modifié ($lib)" || ko "  ... état modifié avant refus ($lib)"; fi
}
nouveau; STUB_NFT_C_RC=1 lance --oui
refus3 "nft -c rouge" "nft -c" non
! grep -q '^nft -f' "$S/journal" && ok "  ... nft -f jamais lancé après nft -c rouge" || ko "  ... nft -f lancé"
[ "$(cat "$S/sysctl-net.ipv4.conf.virbr-pra.arp_ignore")" = 0 ] && ok "  ... sysctls ramenés à l'état d'avant" || ko "  ... sysctls non restaurés"
nouveau; STUB_ARPING_RC=1 lance --oui
refus3 "réponse ARP (arping -D code 1)" "arping" non
[ ! -e "$S/table" ] && ok "  ... table retirée après réponse ARP (rollback)" || ko "  ... table restée"
nouveau; sed -i 's|^wlan0 UP .*|& 10.255.70.5/30|' "$S/addr.txt"; lance --oui
refus3 "/30 porté par une autre interface" "10.255.70" oui
nouveau; echo '10.255.70.0/30 dev wlan0 scope link' >> "$S/route.txt"; lance --oui
refus3 "/30 routé par une autre interface" "10.255.70" oui
nouveau; sed -i 's|^virbr-pra UP.*|virbr-pra UP 10.0.0.30/24|' "$S/addr.txt"; lance --oui
refus3 "10.0.0.x sur virbr-pra" "192.168.1" oui
nouveau; PATH_SANS_ARPING=1 lance --oui
refus3 "arping absent" "arping" oui
nouveau; sed -i '/^virbr-pra/d' "$S/addr.txt"; lance --oui
refus3 "virbr-pra absente" "virbr-pra" oui
nouveau; sed -i 's|^virbr-pra UP.*|virbr-pra UP 10.255.70.1/30|' "$S/addr.txt"; lance --oui
refus3 "adresse déjà posée" "déjà" oui

# pose dont la garde finale refuse : exit 4 et retour arrière complet
nouveau; STUB_SSH=tcp-ouvert lance --oui
{ [ "$rc" -eq 4 ] && grep -q 'REFUS isolement : canari-tcp' "$S/sortie"; } && ok "pose + canari rouge : exit 4" || { ko "pose + canari rouge rc=$rc"; cat "$S/sortie"; }
{ ! grep -q '10.255.70.1/30' "$S/addr.txt" && [ ! -e "$S/table" ]; } && ok "  ... adresse et table retirées (rien ne reste)" || ko "  ... lien resté après refus 4"

# (4) --verifier : un rouge par raison
verif() { # <libellé> <raison>
  if [ "$rc" -eq 4 ] && grep -q "REFUS isolement : $2" "$S/sortie"; then ok "--verifier rouge : $1"; else ko "--verifier $1 (rc=$rc)"; sed 's/^/   | /' "$S/sortie"; fi
}
pose_etat() { nouveau; sed -i 's|^virbr-pra UP.*|virbr-pra UP 10.255.70.1/30|' "$S/addr.txt"; echo '10.255.70.0/30 dev virbr-pra proto kernel scope link src 10.255.70.1' >> "$S/route.txt"; }
pose_etat; env -i PATH="$DBL:$UT" HOME="$H" STUB_DIR="$S" bash "$P" --verifier > "$S/sortie" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--verifier vert, sans root (ni PRA_SANS_ROOT)" || { ko "--verifier vert rc=$rc"; cat "$S/sortie"; }
grep -q 'ssh -F none -i' "$S/journal" && ok "  ... canari tenté via la bibliothèque ssh (options figées)" || ko "  ... pas d'appel ssh"
grep -q '/dev/tcp/10.255.70.1/' "$S/journal" && grep -q '/dev/udp/10.255.70.1/' "$S/journal" && ok "  ... tentative TCP et UDP depuis le labo vers 10.255.70.1" || ko "  ... tentatives TCP/UDP absentes"
p="$(grep -o '/dev/tcp/10.255.70.1/[0-9]*' "$S/journal" | head -1 | grep -o '[0-9]*$')"
{ [ "${p:-0}" -ge 40000 ] && [ "$p" -le 60000 ]; } && ok "  ... port du canari tiré entre 40000 et 60000 ($p)" || ko "  ... port hors plage ($p)"
nouveau; lance --verifier; verif "adresse absente" adresse
nouveau; sed -i 's|^wlan0 UP.*|& 10.255.70.1/30|' "$S/addr.txt"; lance --verifier; verif "adresse sur une autre interface" adresse
pose_etat; STUB_ROUTE_DEV=wlan0 lance --verifier; verif "route par une autre interface" route
pose_etat; STUB_SSH=tcp-ouvert lance --verifier; verif "canari TCP joignable" canari-tcp
pose_etat; STUB_SSH=udp-recu lance --verifier; verif "canari UDP reçu" canari-udp
pose_etat; STUB_SSH_RC=255 lance --verifier; verif "labo injoignable (preuve impossible = refus)" canari-tcp

# (N1) mode rouge sans table, puis retrait, à sec
nouveau; lance --rouge-sans-table --oui
[ "$rc" -eq 0 ] && ok "--rouge-sans-table --oui : exit 0" || { ko "--rouge-sans-table rc=$rc"; cat "$S/sortie"; }
grep -q '^ip addr add 10.255.70.1/30 dev virbr-pra' "$S/journal" && ! grep -qE '^nft (-c|-f)' "$S/journal" && [ ! -e "$S/table" ] \
  && ok "  ... adresse posée SANS table (aucun nft -c/-f)" || ko "  ... mode rouge a posé une table ou pas d'adresse"
grep -q 'table=non' "$S/etat-add" 2>/dev/null && ok "  ... l'adresse existe sans la table (mode de preuve 5.14b, seul cas)" || ko "  ... état-add"
grep -qi 'sans table' "$S/sortie" && ok "  ... avertissement affiché" || ko "  ... pas d'avertissement"
STUB_SSH=tcp-ouvert lance --verifier; verif "adresse sans table + port ouvert vu : la sonde sait voir" canari-tcp
STUB_SSH=udp-recu lance --verifier; verif "adresse sans table + datagramme UDP reçu" canari-udp
: > "$S/journal"; lance --retirer --oui
{ [ "$rc" -eq 0 ] && ! grep -q 'delete table' "$S/journal" && grep -q '^ip addr del' "$S/journal" && ! grep -q '10.255.70.1/30' "$S/addr.txt"; } \
  && ok "--retirer après rouge : adresse retirée, pas de nft delete (table absente)" || { ko "--retirer après rouge rc=$rc"; J | sed 's/^/   | /'; }
[ ! -e "$H/.cache/pra/sysctl-avant" ] && [ "$(cat "$S/sysctl-net.ipv6.conf.virbr-pra.disable_ipv6")" = 0 ] && ok "  ... sysctls restaurés" || ko "  ... sysctls non restaurés"

# (5) bibliothèque ssh : options figées
attendu() { EXPECT="ssh -F none -i $H/.ssh/pra-lab -o IdentitiesOnly=yes -o BatchMode=yes -o ForwardAgent=no -o ForwardX11=no -o ClearAllForwardings=yes -o PermitLocalCommand=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$H/.ssh/known_hosts-pra-lab root@10.255.70.2"; }
nouveau; attendu
env -i PATH="$DBL:$UT" HOME="$H" STUB_DIR="$S" bash "$L" true > "$S/sortie" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(head -1 "$S/journal")" = "$EXPECT true" ] && ok "lib-ssh-labo.sh : options figées et cible root@10.255.70.2" || { ko "lib-ssh-labo.sh ligne ssh"; head -1 "$S/journal" | sed 's/^/   | /'; }
nouveau; attendu; env -i PATH="$DBL:$UT" HOME="$H" STUB_DIR="$S" bash -c ". '$L'; ssh_labo uname -a" > "$S/sortie" 2>&1
[ "$(head -1 "$S/journal")" = "$EXPECT uname -a" ] && ok "ssh_labo (source) : même ligne" || ko "ssh_labo source"
nouveau; env -i PATH="$DBL:$UT" HOME="$H" STUB_DIR="$S" STUB_SSH_RC=7 bash "$L" true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "code de retour de ssh propagé" || ko "rc ssh non propagé ($rc)"
nouveau; attendu; env -i PATH="$DBL:$UT" HOME="$H" STUB_DIR="$S" bash "$L" --scp /x/a root@10.255.70.2:/y/ > "$S/sortie" 2>&1
OPTS="${EXPECT#ssh }"; OPTS="${OPTS% root@10.255.70.2}"
[ "$(head -1 "$S/journal")" = "scp $OPTS /x/a root@10.255.70.2:/y/" ] && ok "scp : mêmes options figées" || { ko "scp options"; head -1 "$S/journal" | sed 's/^/   | /'; }

# aucun ssh/scp direct vers 10.255.70.2 hors bibliothèque (le détecteur est lui-même éprouvé)
direct() { # fichiers... : lignes (hors commentaires) qui lancent ssh/scp vers le labo
  grep -nE '(^|[;&|(`[:space:]])(ssh|scp)[[:space:]]' "$@" 2>/dev/null | grep -vE '^([^:]*:)?[0-9]+:[[:space:]]*#' | grep -E '10\.255\.70\.2|root@10\.255|LABO_CIBLE'
}
printf '%s\n' '#!/bin/bash' 'ssh -o X root@10.255.70.2 true' > "$tmp/mauvais.sh"
printf '%s\n' '#!/bin/bash' '# ssh root@10.255.70.2 (commentaire)' 'ssh root@10.0.0.5 true' 'ssh_labo true' > "$tmp/bon.sh"
direct "$tmp/mauvais.sh" >/dev/null && ok "détecteur : ssh direct vers le labo repéré (rouge)" || ko "détecteur sourd"
direct "$tmp/bon.sh" >/dev/null && ko "détecteur : faux positif (pve, commentaire, ssh_labo)" || ok "détecteur : pve, commentaire et ssh_labo tolérés (vert)"
mapfile -t autres < <(ls "$d"/pra/*.sh | grep -v '/lib-ssh-labo.sh$')
if direct "${autres[@]}"; then ko "ssh/scp direct vers 10.255.70.2 dans pra/*.sh hors bibliothèque"; else ok "aucun ssh/scp direct vers 10.255.70.2 dans pra/*.sh hors bibliothèque"; fi

exit "$fail"

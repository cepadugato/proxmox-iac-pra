#!/usr/bin/env bash
# scan-poste.sh : sonde d'isolement lancée DEPUIS le labo vers le poste, par pra/lib-ssh-labo.sh (feuille 5.14b).
#   scan-poste.sh --balayage   TCP 1-65535 sur 10.255.70.1 ; ports `ss -lntu` + canari TCP/UDP sur chaque autre adresse du poste
#   scan-poste.sh --transit    route par défaut temporaire du labo via 10.255.70.1 : Internet et LAN doivent rester injoignables
# Sortie : une ligne par constat ; dernière ligne « BILAN ok » (exit 0) ou « BILAN fuite : <détail> » (exit 4).
# Tout ce qui est posé dans le labo (voisins statiques, routes, route par défaut) est retiré à la fin, même en cas d'erreur.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-ssh-labo.sh"
IF="virbr-pra"; IP_POSTE="10.255.70.1"
PARALLELE=128; DELAI=0.5

mode="${1:-}"
case "$mode" in --balayage|--transit) ;; *) echo "usage : $0 --balayage|--transit" >&2; exit 2 ;; esac
bash "$DIR/poste-labo.sh" --verifier >/dev/null || { echo "BILAN refus : garde --verifier rouge, rien n'est sondé" >&2; exit 4; }

if [ "$mode" = --transit ]; then
  ssh_labo bash -s <<'LABO'
set -u
avant="$(ip route show default)"; avant_lan=""
remettre() { ip route del default 2>/dev/null; [ -n "$avant" ] && ip route add $avant; for a in $avant_lan; do ip route del "$a/32" 2>/dev/null; done; avant_lan=""; }
trap remettre EXIT
ip route replace default via 10.255.70.1 dev vmbr0
echo "route par défaut temporaire : $(ip route show default)"
# le labo porte 10.0.0.0/24 en direct : sans /32 via le poste, ses essais vers le LAN ne transiteraient pas par lui
lan="10.0.0.10 10.0.0.254"
for a in $lan; do ip route replace "$a/32" via 10.255.70.1 dev vmbr0; avant_lan="$avant_lan $a"; done
fuite=""
for a in 1.1.1.1 $lan; do
  r="$(ip route get "$a" | head -1)"
  case "$r" in *"via 10.255.70.1 "*) ;; *) echo "route $a : ne passe pas par le poste [$r]"; fuite="$fuite route-$a" ;; esac
  if ping -c2 -W1 "$a" >/dev/null 2>&1; then echo "ping $a [$r] : RÉPOND"; fuite="$fuite ping-$a"; else echo "ping $a [$r] : muet"; fi
done
for u in http://1.1.1.1 https://10.0.0.10:8006 http://10.0.0.254; do
  if curl -sk -m 5 -o /dev/null "$u"; then echo "curl $u : RÉPOND"; fuite="$fuite curl-$u"; else echo "curl $u : échec (rc=$?, 28 = délai : paquet avalé)"; fi
done
remettre; trap - EXIT
echo "route par défaut remise : ${avant:-aucune}"
[ -z "$fuite" ] && { echo "BILAN ok"; exit 0; }
echo "BILAN fuite :$fuite"; exit 4
LABO
  exit $?
fi

# --balayage : relevés du poste, écrits dans la sortie
mac="$(cat /sys/class/net/$IF/address)"
cibles="$(ip -br a | grep -v "^${IF}[[:space:]]" | tr -s ' ' '\n' | grep -E '^[0-9a-f.:]+/[0-9]+$' |
  cut -d/ -f1 | grep -Ev '^(127\.|::1$|fe80:)' | sort -u | tr '\n' ' ')"
ports="$(ss -lntuH | awk '{n=split($5,a,":"); print $1":"a[n]}' | sort -u | tr '\n' ' ')"
echo "MAC de $IF : $mac"
echo "adresses visées (hors $IF) : $cibles"
echo "ports à l'écoute (ss -lntu) : $ports"
echo "IPv6 de $IF : [$(ip -6 -br addr show dev "$IF" 2>/dev/null | tr -s ' ')]"

w="$(mktemp -d)"
python3 - "$w/evts" "$w/port" 900 <<'PY' &
import random, select, socket, sys, time
evts, portf, duree = sys.argv[1], sys.argv[2], float(sys.argv[3])
for _ in range(100):
    p = random.randint(40000, 60000)
    t4, u4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM), socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    t6, u6 = socket.socket(socket.AF_INET6, socket.SOCK_STREAM), socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    try:
        for s in (t6, u6): s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        t4.bind(("0.0.0.0", p)); u4.bind(("0.0.0.0", p)); t6.bind(("::", p)); u6.bind(("::", p)); break
    except OSError:
        for s in (t4, u4, t6, u6): s.close()
else:
    sys.exit(1)
t4.listen(16); t6.listen(16)
open(portf, "w").write(str(p))
fin = time.time() + duree
while time.time() < fin:
    r, _, _ = select.select([t4, u4, t6, u6], [], [], 0.2)
    for s in r:
        if s in (t4, t6):
            c, a = s.accept(); c.close(); open(evts, "a").write("tcp %s\n" % a[0])
        else:
            _, a = s.recvfrom(64); open(evts, "a").write("udp %s\n" % a[0])
PY
lp=$!; i=0
while [ ! -s "$w/port" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
canari="$(cat "$w/port" 2>/dev/null)"
[ -n "$canari" ] || { echo "BILAN refus : canari impossible à lancer"; kill "$lp"; exit 4; }
echo "canari du poste : TCP et UDP $canari"

# les valeurs passent en tête du script distant (printf %q), pas en arguments : ssh recolle ses arguments en une ligne
{ printf 'mac=%q; canari=%q; par=%q; delai=%q; cibles=%q; ports=%q\n' "$mac" "$canari" "$PARALLELE" "$DELAI" "$cibles" "$ports"
  cat <<'LABO'
set -u
poses=()
nettoyer() {
  for a in "${poses[@]}"; do
    case "$a" in *:*) ip -6 route del "$a/128" dev vmbr0 2>/dev/null; ip -6 neigh del "$a" dev vmbr0 2>/dev/null ;;
                 *)   ip route del "$a/32" dev vmbr0 2>/dev/null; ip neigh del "$a" dev vmbr0 2>/dev/null ;; esac
  done
}
trap nettoyer EXIT
temoin="$(printf '%s\n' 22 | xargs -P "$par" -I{} timeout "$delai" bash -c 'exec 3<>/dev/tcp/10.255.70.2/{} && echo {}' 2>/dev/null)"
echo "témoin positif (même sonde vers le sshd du labo 10.255.70.2:22) : [${temoin}]"
ouverts="$(seq 1 65535 | xargs -P "$par" -I{} timeout "$delai" bash -c 'exec 3<>/dev/tcp/10.255.70.1/{} && echo {}' 2>/dev/null | sort -n | tr '\n' ' ')"
echo "TCP 1-65535 sur 10.255.70.1 : ouverts=[${ouverts}]"
for a in $cibles; do
  case "$a" in
    *:*) ip -6 neigh replace "$a" lladdr "$mac" dev vmbr0 nud permanent && ip -6 route replace "$a/128" dev vmbr0 ;;
    *)   ip neigh replace "$a" lladdr "$mac" dev vmbr0 nud permanent && ip route replace "$a/32" dev vmbr0 ;;
  esac && poses+=("$a")
  r="$(ip route get "$a" 2>/dev/null | head -1)"; n="$(ip neigh show "$a" dev vmbr0)"
  case "$r $n" in *"dev vmbr0"*PERMANENT*) ;; *) echo "adresse $a : VOISIN OU ROUTE ABSENT [$r] [$n]"; continue ;; esac
  ok=""
  for pp in $ports "tcp:$canari" "udp:$canari"; do
    proto="${pp%%:*}"; p="${pp##*:}"
    if [ "$proto" = tcp ]; then
      timeout "$delai" bash -c "exec 3<>/dev/tcp/$a/$p" 2>/dev/null && ok="$ok tcp/$p"
    else
      echo canari >"/dev/udp/$a/$p" 2>/dev/null
    fi
  done
  echo "adresse $a : TCP ouverts=[${ok# }]"
done
echo "ping -6 ff02::1%vmbr0 (MAC du poste attendue absente) :"
ping -6 -c2 -W1 "ff02::1%vmbr0" 2>/dev/null | grep -o 'from [^ ]*' | sort -u | while read -r _ src; do
  a="${src%%%*}"; a="${a%:}"; m="$(ip -6 neigh show "$a" dev vmbr0 | grep -o 'lladdr [^ ]*' | cut -d' ' -f2)"
  echo "  répondant $a lladdr=${m:-?}"
done
LABO
} | ssh_labo bash -s | tee "$w/labo"
rc_ssh=${PIPESTATUS[1]}
sleep 2
kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
evts="$(cat "$w/evts" 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
echo "canari reçu par le poste : [${evts}]"
fuite=""
[ "$rc_ssh" -eq 0 ] || fuite="$fuite ssh-rc=$rc_ssh"
grep -q '^témoin positif .*: \[22\]$' "$w/labo" || fuite="$fuite temoin-absent"
grep -q 'VOISIN OU ROUTE ABSENT' "$w/labo" && fuite="$fuite voisin-absent"
grep -q '^TCP 1-65535 sur 10.255.70.1 : ouverts=\[\]$' "$w/labo" || fuite="$fuite balayage-10.255.70.1"
grep '^adresse ' "$w/labo" | grep -qv 'ouverts=\[\]$' && fuite="$fuite port-ouvert-ailleurs"
grep -qi "lladdr=$mac" "$w/labo" && fuite="$fuite ipv6-repond"
[ -n "$evts" ] && fuite="$fuite canari-recu"
find "$w" -delete 2>/dev/null
[ -z "$fuite" ] && { echo "BILAN ok"; exit 0; }
echo "BILAN fuite :$fuite"; exit 4

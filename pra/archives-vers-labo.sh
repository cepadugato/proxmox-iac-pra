#!/usr/bin/env bash
# archives-vers-labo.sh : déchiffre SUR LE POSTE, en flux, les archives .gpg du périmètre PRA et les écrit EN CLAIR
# dans le labo seulement (feuille 5.12b, D24 (1)). La clé ne quitte pas le poste ; le clair n'existe que dans un tube.
#   archives-vers-labo.sh            à sec (défaut) : contrôles locaux, plan affiché, rien n'est déchiffré ni envoyé ; exit 3
#   archives-vers-labo.sh --oui      exécute : --verifier d'abord, puis une archive par VMID du périmètre
# Exit : 0 tout vert ; 1 un écart (arrêt à la première archive en défaut) ; 2 clé GPG absente ou expirée ;
#        3 refus (--oui absent) ; 4 garde d'isolement rouge (poste-labo.sh --verifier).
# Clé : fichier de phrase en mémoire de session (phrase-session.sh charger), lu ici, passé à gpg par le descripteur 3.
#   Jamais en argument, ni à l'écran, ni dans un journal. Le statut gpg (--status-fd 4) va dans un fichier jetable.
# Variables d'essai (tests/test-archives-vers-labo.sh) : PRA_TIRAGE (dossier du passage), PRA_PERIMETRE, PRA_POSTE_LABO,
#   PRA_CLE_DIR. gpg et ssh se prennent dans le PATH ; ssh passe par pra/lib-ssh-labo.sh (ssh_labo), seule voie vers le labo.
set -euo pipefail
set +x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Crochets d'essai : actifs seulement avec PRA_TEST=1 et des chemins sous tests/.tmp-* du projet (modèle de tofu-cible.sh).
PROJ="$(cd "$DIR/.." && pwd)"
if [ -n "${PRA_TIRAGE:-}${PRA_PERIMETRE:-}${PRA_POSTE_LABO:-}${PRA_CLE_DIR:-}" ]; then
  [ "${PRA_TEST:-}" = 1 ] || { echo "REFUS crochet d'essai (PRA_TIRAGE, PRA_PERIMETRE, PRA_POSTE_LABO, PRA_CLE_DIR) sans PRA_TEST=1" >&2; exit 3; }
  for _c in "${PRA_TIRAGE:-}" "${PRA_PERIMETRE:-}" "${PRA_POSTE_LABO:-}" "${PRA_CLE_DIR:-}"; do
    [ -z "$_c" ] && continue
    case "$(realpath -m -- "$_c")" in "$PROJ"/tests/.tmp-*) ;; *) echo "REFUS crochet d'essai hors de $PROJ/tests/.tmp-* : $_c" >&2; exit 3 ;; esac
  done
fi
PERIMETRE="${PRA_PERIMETRE:-$DIR/perimetre.yaml}"
POSTE_LABO="${PRA_POSTE_LABO:-$DIR/poste-labo.sh}"
CLE_DIR="${PRA_CLE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/infra-as-code}"
CLE="$CLE_DIR/cle-gpg"; EXPIRE="$CLE_DIR/phrase.expire"

oui=0
for a in "$@"; do
  case "$a" in
    --oui) oui=1 ;;
    *) echo "usage : $0 [--oui]" >&2; exit 64 ;;
  esac
done

lire() { sed -n "s/^$1:[[:space:]]*//p" "$PERIMETRE" | head -1; }
passage="$(lire passage)"; vmids="$(lire vague1) $(lire vague2) $(lire vague3) $(lire vm)"; cible="$(lire dechiffrement_dir)"
# type d'archive par VMID : les VMID de la clé « vm » sont des VM (vzdump-qemu-*.vma.zst), les autres des CT
declare -A TYPE; for id in $vmids; do TYPE[$id]=lxc; done; for id in $(lire vm); do TYPE[$id]=qemu; done
ext() { [ "${TYPE[$1]}" = qemu ] && echo vma.zst || echo tar.zst; }
[ -n "$passage" ] && [ -n "$cible" ] && [ -n "$(tr -d ' ' <<<"$vmids")" ] || { echo "périmètre illisible : $PERIMETRE" >&2; exit 1; }
case "$cible" in /*/) ;; *) echo "dechiffrement_dir doit être un chemin absolu terminé par / : $cible" >&2; exit 1 ;; esac
case "$cible" in *[!A-Za-z0-9/._-]*|*..*) echo "dechiffrement_dir : caractères hors [A-Za-z0-9/._-] ou '..' : refusé" >&2; exit 1 ;; esac
TIRAGE="${PRA_TIRAGE:-$HOME/pra-tirage/$passage}"
MANIF="$(ls "$TIRAGE"/MANIFESTE-*.txt 2>/dev/null | head -1 || true)"

nb=0; ok_n=0; saute_n=0; ko_n=0
bilan() {
  echo "bilan : $nb VMID du périmètre ; $ok_n envoyée(s), $saute_n sautée(s), $ko_n en défaut"
  if [ "$((ok_n + saute_n))" -eq "$(wc -w <<<"$vmids")" ] && [ "$ko_n" -eq 0 ]; then echo "comptage = périmètre : OUI"; else echo "comptage = périmètre : NON"; fi
}
arret() { ko_n=$((ko_n + 1)); echo "ARRÊT : $*" >&2; bilan >&2; exit "${CODE:-1}"; }

# --- contrôles locaux (à sec aussi) : MANIFESTE, archive, .sha256 ---
[ -n "$MANIF" ] && [ -f "$MANIF" ] || { echo "ARRÊT : MANIFESTE absent de $TIRAGE" >&2; exit 1; }
declare -A ARCH
for id in $vmids; do
  nb=$((nb + 1))
  case "$id" in ''|*[!0-9]*) arret "VMID invalide : $id" ;; esac
  e="$(ext "$id")"; ee="${e//./\\.}"
  grep -Eq "vzdump-${TYPE[$id]}-${id}-[0-9_-]+\.${ee}\.gpg" "$MANIF" || arret "VMID $id absent du MANIFESTE ($(basename "$MANIF"))"
  f="$(ls "$TIRAGE"/vzdump-"${TYPE[$id]}"-"${id}"-*."$e".gpg 2>/dev/null | head -1 || true)"
  [ -n "$f" ] || arret "VMID $id : .gpg absent de $TIRAGE"
  [ -f "$f.sha256" ] || arret "VMID $id : $(basename "$f").sha256 absent"
  ( cd "$TIRAGE" && sha256sum --status -c "$(basename "$f").sha256" ) || arret "VMID $id : sha256 du .gpg NON conforme"
  case "$(basename "$f")" in *[!A-Za-z0-9._-]*) arret "VMID $id : nom d'archive suspect" ;; esac
  ARCH[$id]="$f"
done
nb=0

if [ "$oui" -ne 1 ]; then
  echo "À SEC : $(wc -w <<<"$vmids") VMID, contrôles locaux verts (MANIFESTE, .gpg, .sha256)."
  for id in $vmids; do echo "  VMID $id : $(basename "${ARCH[$id]}") -> ${cible}$(basename "${ARCH[$id]}" .gpg)"; done
  echo "REFUS : --oui requis pour déchiffrer et envoyer (rien n'a été lancé)." >&2
  exit 3
fi

# --- clé de session : présente, non vide, non expirée ---
exp="$(cat "$EXPIRE" 2>/dev/null || true)"
case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
if [ ! -s "$CLE" ] || [ "$exp" -le "$(date +%s)" ]; then
  echo "clé absente : bash phrase-session.sh charger" >&2; exit 2
fi

# --- garde d'isolement, puis la seule voie vers le labo ---
if [ "${PRA_CIBLE:-labo}" = labo ]; then
  rc=0; bash "$POSTE_LABO" --verifier >/dev/null || rc=$?
  [ "$rc" -eq 0 ] || { echo "REFUS isolement : poste-labo.sh --verifier exit $rc" >&2; exit 4; }
fi
. "$DIR/lib-ssh-labo.sh"
[ "$PRA_CIBLE" = labo ] || verifier_cible || { echo "REFUS : cible $PRA_CIBLE injoignable ou empreinte de l hôte inconnue" >&2; exit 4; }

W="$(mktemp -d)"
trap 'find "$W" -delete 2>/dev/null || true' EXIT
t0=$SECONDS

q() { printf '%q' "$1"; }
for id in $vmids; do
  nb=$((nb + 1))
  f="${ARCH[$id]}"; nom="$(basename "$f" .gpg)"; dest="${cible}${nom}"; part="$dest.partiel"
  qd="$(q "$dest")"; qp="$(q "$part")"; qs="$(q "$dest.sha256")"
  # idempotence : déjà présente, sha256 identique à celui consigné lors d'un envoi vérifié, et lisible
  if ssh_labo "test -s $qd -a -s $qs" 2>/dev/null; then
    attendu="$(ssh_labo "cut -d' ' -f1 $qs")" || attendu=""
    present="$(ssh_labo "sha256sum $qd" | cut -d' ' -f1)" || present=""
    if [ -n "$attendu" ] && [ "$attendu" = "$present" ] && ssh_labo "zstd -t -q $qd" 2>/dev/null; then
      echo "VMID $id : déjà présente au bon sha256 (${present:0:12}), sautée"; saute_n=$((saute_n + 1)); continue
    fi
  fi
  nettoyer() { ssh_labo "rm -f $qp" >/dev/null 2>&1 || true; }
  # ancien résidu (nom final sans empreinte valide) retiré avant d'écrire : le nom final ne réapparaît qu'après les contrôles
  ssh_labo "rm -f $qd $qs $qp" || arret "VMID $id : résidu distant non retiré"
  : > "$W/statut"; : > "$W/somme"
  echo "VMID $id : déchiffrement en flux de $(basename "$f") vers ${nom}.partiel"
  set +e
  gpg --batch --pinentry-mode loopback --passphrase-fd 3 --status-fd 4 -d "$f" 3<"$CLE" 4>"$W/statut" 2>/dev/null \
    | tee >(sha256sum | cut -d' ' -f1 > "$W/somme") \
    | ssh_labo "cat > $qp"
  ps=("${PIPESTATUS[@]}")
  set -e
  wait 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$W/somme" ] && break; sleep 0.2; done
  if [ "${ps[0]}" -ne 0 ] || [ "${ps[1]}" -ne 0 ] || [ "${ps[2]}" -ne 0 ]; then
    nettoyer; arret "VMID $id : tube en défaut (gpg=${ps[0]} tee=${ps[1]} ssh=${ps[2]})"
  fi
  if grep -qE 'DECRYPTION_FAILED|BADMDC' "$W/statut" || ! grep -q 'DECRYPTION_OKAY' "$W/statut" || ! grep -q 'GOODMDC' "$W/statut"; then
    nettoyer; arret "VMID $id : statut gpg sans DECRYPTION_OKAY + GOODMDC (ou DECRYPTION_FAILED / BADMDC)"
  fi
  local_sha="$(cat "$W/somme")"
  [ "${#local_sha}" -eq 64 ] || { nettoyer; arret "VMID $id : sha256 du clair non calculé côté poste"; }
  distant_sha="$(ssh_labo "sha256sum $qp" | cut -d' ' -f1)" || { nettoyer; arret "VMID $id : sha256 distant illisible"; }
  [ "$local_sha" = "$distant_sha" ] || { nettoyer; arret "VMID $id : sha256 du clair différent (poste ${local_sha:0:12} / labo ${distant_sha:0:12})"; }
  ssh_labo "zstd -t -q $qp" || { nettoyer; arret "VMID $id : zstd -t rouge dans le labo"; }
  if [ "${TYPE[$id]}" = qemu ]; then
    [ "$(ssh_labo "zstd -dcq $qp | head -c 3")" = VMA ] || { nettoyer; arret "VMID $id : en-tête VMA absent de l'archive"; }
  else
    ssh_labo "tar -I zstd -tf $qp ./etc/vzdump/pct.conf >/dev/null" || { nettoyer; arret "VMID $id : ./etc/vzdump/pct.conf absent de l'archive"; }
  fi
  ssh_labo "mv $qp $qd" || { nettoyer; arret "VMID $id : renommage final impossible"; }
  ssh_labo "printf '%s  %s\n' $(q "$local_sha") $(q "$nom") > $qs" || arret "VMID $id : empreinte non consignée"
  taille="$(ssh_labo "stat -c %s $qd")" || taille="?"
  echo "VMID $id : OK sha256 ${local_sha:0:12} des deux côtés, zstd -t vert, contenu reconnu (${TYPE[$id]}), $taille octets"
  ok_n=$((ok_n + 1))
done

# --- aucun clair sur le poste ---
restes="$(find "$W" "$TIRAGE" -type f \( -name '*.tar' -o -name '*.tar.zst' -o -name '*.vma' -o -name '*.vma.zst' \) 2>/dev/null | head -3)"
[ -z "$restes" ] || { echo "ARRÊT : clair trouvé sur le poste : $restes" >&2; ko_n=$((ko_n + 1)); bilan >&2; exit 1; }
echo "aucun clair sur le poste (find) ; durée $((SECONDS - t0)) s"
bilan
[ "$ko_n" -eq 0 ]

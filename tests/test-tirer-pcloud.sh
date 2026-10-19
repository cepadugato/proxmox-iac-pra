#!/usr/bin/env bash
# Liste blanche de pra/tirer-pcloud.sh (feuille 5.13) : sous-commandes rclone autorisées et sens de copie.
# Vert sur le vrai script ; rouge sur deux copies piégées (une sous-commande interdite, une copie VERS pcloud-pra:).
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
S="$d/pra/tirer-pcloud.sh"
ko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }

controle() { # fichier : exit 0 si conforme
  local f="$1" err=0 ligne sous src dst
  while IFS= read -r ligne; do
    case "$ligne" in \#*) continue ;; esac
    # chaque appel « rclone <mot> » hors commentaire
    while read -r sous; do
      case "$sous" in lsf|copy|copyto|check|version) ;; *) echo "  interdit : rclone $sous"; err=1 ;; esac
    done < <(grep -oE '(^|[^-[:alnum:]_])rclone([[:space:]]+[^[:space:]]+)?' <<<"${ligne%%#*}" | awk '{print ($NF=="rclone" ? "(rien)" : $NF)}')
    # rclone hors appel direct (variable, alias, ligne coupée) : refusé
    if grep -qE '[=$][^ ]*rclone|rclone[^ ]*=|\\$' <<<"${ligne%%#*}" && grep -q rclone <<<"${ligne%%#*}"; then echo "  appel indirect ou ligne coupée : $ligne"; err=1; fi
    if grep -qE 'rclone[[:space:]]+(copy|copyto)[[:space:]]' <<<"$ligne"; then
      read -r src dst < <(sed -E 's/.*rclone[[:space:]]+(copy|copyto)[[:space:]]+//' <<<"$ligne" | awk '{print $1, $2}')
      case "$src" in *pcloud-pra:*|*'$REMOTE'*|*'"$REMOTE'*) ;; *) echo "  source hors pcloud-pra : $src"; err=1 ;; esac
      case "$dst" in *pcloud-pra:*|*REMOTE*) echo "  destination pcloud-pra : $dst"; err=1 ;; esac
    fi
  done < "$f"
  grep -q 'REMOTE="pcloud-pra:' "$f" || { echo "  REMOTE ne pointe pas sur pcloud-pra:"; err=1; }
  return "$err"
}

[ -f "$S" ] || { echo "KO   script absent"; exit 1; }
controle "$S" && ok "liste blanche : vrai script conforme" || ko "liste blanche : vrai script NON conforme"

t="$(mktemp -d)"
cp "$S" "$t/a.sh"; sed -i 's/^  --version) rclone version ;;/  --version) rclone sync "$REMOTE" \/tmp\/x ;;/' "$t/a.sh"
grep -q 'rclone sync' "$t/a.sh" || ko "piège 1 non posé"
controle "$t/a.sh" >/dev/null && ko "piège 1 (sous-commande sync) NON détecté" || ok "piège 1 (sous-commande sync) détecté"
cp "$S" "$t/b.sh"; sed -i 's/^  --version) rclone version ;;/  --version) rclone copy \/x pcloud-pra:y ;;/' "$t/b.sh"
grep -q 'rclone copy /x pcloud-pra:y' "$t/b.sh" || ko "piège 2 non posé"
controle "$t/b.sh" >/dev/null && ko "piège 2 (copie vers pcloud-pra:) NON détecté" || ok "piège 2 (copie vers pcloud-pra:) détecté"
cp "$S" "$t/c.sh"; sed -i 's/^  --version) rclone version ;;/  --version) rclone -v sync "$REMOTE" \/tmp\/x ;;/' "$t/c.sh"
controle "$t/c.sh" >/dev/null && ko "piège 3 (option avant sync) NON détecté" || ok "piège 3 (option avant sync) détecté"
cp "$S" "$t/d.sh"; sed -i 's/^  --version) rclone version ;;/  --version) r=rclone; $r sync a b ;;/' "$t/d.sh"
controle "$t/d.sh" >/dev/null && ko "piège 4 (appel par variable) NON détecté" || ok "piège 4 (appel par variable) détecté"
find "$t" -delete
exit "$ko"

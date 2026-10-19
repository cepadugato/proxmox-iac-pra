#!/usr/bin/env bash
# Test de verifier.sh : dérive simulée => exit 2 ; erreur => exit 1 ; propre => exit 0.
# Aucun appel à pve : la commande OpenTofu est remplacée par un faux (variable VERIFIER_TOFU).
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
fail=0
faux="$tmp/faux-tofu.sh"
journal="$tmp/appels.log"
cat > "$faux" <<'EOF'
#!/usr/bin/env bash
# Faux outil : le code de sortie de chaque sous-commande vient de STUB_FMT / STUB_VALIDATE / STUB_PLAN.
echo "$1" >> "$STUB_JOURNAL"
case "$1" in
  fmt) exit "${STUB_FMT:-0}" ;;
  validate) exit "${STUB_VALIDATE:-0}" ;;
  plan) exit "${STUB_PLAN:-0}" ;;
esac
exit 99
EOF
chmod +x "$faux"
export VERIFIER_TOFU="$faux" VERIFIER_SANS_ENV=1 VERIFIER_SANS_TUNNEL=1 STUB_JOURNAL="$journal"

lance() { # <fmt> <validate> <plan> -> code de sortie de verifier.sh
  : > "$journal"
  STUB_FMT="$1" STUB_VALIDATE="$2" STUB_PLAN="$3" bash "$d/verifier.sh" >/dev/null 2>&1
}
attend() { # <libellé> <attendu> <obtenu>
  [ "$2" = "$3" ] || { echo "ROUGE: $1 (attendu $2, obtenu $3)"; fail=1; }
}

lance 0 0 0; attend "rien à faire => 0" 0 $?
lance 0 0 2; attend "dérive simulée => 2" 2 $?
lance 0 0 1; attend "erreur du plan => 1" 1 $?
lance 3 0 0; attend "format non conforme => 1" 1 $?
grep -qx plan "$journal" && { echo "ROUGE: plan lancé malgré l'échec statique"; fail=1; }
lance 0 1 0; attend "validate en échec => 1" 1 $?
grep -qx plan "$journal" && { echo "ROUGE: plan lancé malgré validate en échec"; fail=1; }
lance 0 0 0; grep -qx apply "$journal" && { echo "ROUGE: apply appelé"; fail=1; }
if grep -vE '^\s*#' "$d/verifier.sh" | grep -qE '(^|[[:space:]])(apply|destroy)([[:space:]]|$)'; then
  echo "ROUGE: verifier.sh contient apply/destroy hors commentaire"; fail=1
fi

find "$tmp" -type f -delete; rmdir "$tmp"
[ $fail -eq 0 ] && echo "OK test-verifier"
exit $fail

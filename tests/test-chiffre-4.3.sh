#!/usr/bin/env bash
# Test de recettes/chiffre-4.3.sh sur une COPIE JETABLE (ressource terraform_data, aucun réseau, aucun pve) :
# à sec sans écriture ; migrer ; relance refusée ; retour ; état clair retrouvé. Phrase aléatoire de test, jamais affichée.
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
command -v tofu >/dev/null || { echo "SKIP: tofu absent"; exit 0; }
tmp="$(mktemp -d)"; fail=0
trap 'find "$tmp" -delete' EXIT
ok() { echo "OK   $1"; }; ko() { echo "FAIL $1"; fail=1; }
mkdir -p "$tmp/tofu"
printf 'terraform {\n  required_version = "~> 1.13"\n}\n\nresource "terraform_data" "a" {\n  input = "x"\n}\n' > "$tmp/tofu/main.tf"
( cd "$tmp/tofu" && tofu init -no-color >/dev/null 2>&1 && tofu apply -auto-approve -no-color >/dev/null 2>&1 ) || { echo "SKIP: init/apply de la copie impossible"; exit 0; }
export CHIFFRE_DIR="$tmp/tofu" CHIFFRE_SAUV="$tmp/sauv" LOG="$tmp/log.txt" CHIFFRE_SANS_TESTS=1
export CHIFFRE_PLAN_CMD="tofu -chdir=$tmp/tofu plan -detailed-exitcode -input=false -lock=false -no-color"
export TF_VAR_tofu_enc_passphrase; TF_VAR_tofu_enc_passphrase="$(head -c 48 /dev/urandom | base64 | tr -d '=+/\n' | head -c 40)"
bash "$d/recettes/chiffre-4.3.sh" migrer >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && [ ! -e "$tmp/tofu/etat" ] && [ ! -e "$tmp/sauv" ]; } && ok "à sec : rc 0, rien écrit" || ko "à sec a écrit ou échoué (rc $rc)"
bash "$d/recettes/chiffre-4.3.sh" migrer --oui >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "migrer --oui : rc 0 (preuves P1 à P6 vertes)" || ko "migrer --oui rc $rc"
[ "$(grep -c encrypted_data "$tmp/tofu/etat/pve.tfstate")" -ge 1 ] && [ ! -e "$tmp/tofu/terraform.tfstate" ] && ok "état chiffré, clair retiré de tofu/" || ko "état non chiffré ou clair resté"
bash "$d/recettes/chiffre-4.3.sh" migrer --oui >/dev/null 2>&1 && ko "relance acceptée sur un état déjà chiffré" || ok "relance refusée (déjà chiffré)"
bash "$d/recettes/chiffre-4.3.sh" retour --oui >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c encrypted_data "$tmp/tofu/terraform.tfstate")" -eq 0 ] && ok "retour : état en clair rétabli" || ko "retour rc $rc"
exit "$fail"

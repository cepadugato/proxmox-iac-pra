#!/usr/bin/env bash
# Verrou de cible (D25, tofu/verrou.tf), prouvé HORS LIGNE : module jetable avec le seul terraform_data, état local jetable.
# Attendu : l'état créé avec cible=pve refuse un plan cible=labo (prevent_destroy) et un endpoint du labo avec cible=pve
# (précondition) ; un plan conforme rend « No changes ».
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
command -v tofu >/dev/null || { echo "SAUTÉ  tofu absent"; exit 0; }
t="$(mktemp -d)"; trap 'find "$t" -delete 2>/dev/null' EXIT
printf 'variable "cible" { type = string }\nvariable "proxmox_endpoint" { type = string }\nvariable "repetition_labo" {\n  type    = bool\n  default = false\n}\n' > "$t/main.tf"
sed -n '/^locals/,$p' "$d/tofu/verrou.tf" >> "$t/main.tf"
ko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }
EP_PVE="https://127.0.0.1:8006/"; EP_LABO="https://10.255.70.2:8006/"
tf() { (cd "$t" && TF_IN_AUTOMATION=1 tofu "$@" -input=false -no-color 2>&1); }
(cd "$t" && tofu init -input=false -no-color >/dev/null 2>&1) || { echo "KO   init du module jetable"; exit 1; }

s="$(tf apply -auto-approve -var cible=pve -var proxmox_endpoint=$EP_PVE)"
grep -q "1 added" <<<"$s" && ok "état créé avec cible=pve" || ko "création de l'état : $s"
s="$(tf plan -var cible=pve -var proxmox_endpoint=$EP_PVE)"
grep -q "No changes" <<<"$s" && ok "plan conforme (pve, endpoint pve) : No changes" || ko "plan conforme : $s"
s="$(tf plan -var cible=labo -var proxmox_endpoint=$EP_LABO)"
grep -q "cannot be destroyed" <<<"$s" && ok "état pve + cible labo : refusé (prevent_destroy)" || ko "état pve + cible labo NON refusé"
s="$(tf plan -var cible=pve -var proxmox_endpoint=$EP_LABO)"
grep -q "REFUS : l'endpoint ne correspond pas" <<<"$s" && ok "cible pve + endpoint labo : refusé (précondition)" || ko "cible pve + endpoint labo NON refusé"
s="$(tf plan -var cible=labo -var proxmox_endpoint=$EP_PVE)"
grep -qE "cannot be destroyed|REFUS : l'endpoint" <<<"$s" && ok "cible labo + endpoint pve : refusé" || ko "cible labo + endpoint pve NON refusé"
s="$(tf plan -var cible=secours -var proxmox_endpoint=https://10.0.0.50:8006/)"
grep -q "cannot be destroyed" <<<"$s" && ok "état pve + cible secours : refusé (prevent_destroy)" || ko "état pve + cible secours NON refusé"
# état jetable propre à secours : endpoint libre accepté, endpoints de pve et du labo refusés
rm -f "$t/terraform.tfstate" "$t/terraform.tfstate.backup"
s="$(tf plan -var cible=secours -var proxmox_endpoint=https://10.0.0.50:8006/)"
grep -q "1 to add" <<<"$s" && ok "cible secours + endpoint libre : accepté" || ko "cible secours + endpoint libre refusé : $s"
for e in "$EP_PVE" "$EP_LABO"; do
  s="$(tf plan -var cible=secours -var proxmox_endpoint=$e)"
  grep -q "REFUS : l'endpoint ne correspond pas" <<<"$s" && ok "cible secours + endpoint $e : refusé" || ko "cible secours + endpoint $e NON refusé"
done
# répétition sur le labo : l'endpoint du labo seul est admis
s="$(tf plan -var cible=secours -var repetition_labo=true -var proxmox_endpoint=$EP_LABO)"
grep -q "1 to add" <<<"$s" && ok "répétition + endpoint labo : accepté" || ko "répétition + endpoint labo refusé : $s"
for e in "$EP_PVE" "https://10.0.0.50:8006/"; do
  s="$(tf plan -var cible=secours -var repetition_labo=true -var proxmox_endpoint=$e)"
  grep -q "REFUS : l'endpoint ne correspond pas" <<<"$s" && ok "répétition + endpoint $e : refusé" || ko "répétition + endpoint $e NON refusé"
done
exit "$ko"

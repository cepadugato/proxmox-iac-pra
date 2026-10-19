#!/usr/bin/env bash
# MAC en variable (choix de l'admin, 2026-10-18) : chaque CT prend var.macs ; pra/relever-macs.sh écrit un relevé complet
# ou refuse ; tofu-cible.sh charge <cible>.macs.tfvars s'il existe.
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
ko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }
n_ct="$(ls "$d"/tofu/ct[0-9]*.tf | wc -l)"
n_var="$(grep -l 'mac_address = var.macs\["' "$d"/tofu/ct[0-9]*.tf | wc -l)"
[ "$n_ct" -eq "$n_var" ] && ok "les $n_ct CT prennent leur MAC dans var.macs" || ko "$n_var/$n_ct CT seulement utilisent var.macs"
grep -rqE 'mac_address = "' "$d"/tofu/*.tf && ko "MAC écrite en dur dans tofu/" || ok "aucune MAC en dur dans les .tf"
for i in $(sed -n 's/^vague[123]:[[:space:]]*//p' "$d/pra/perimetre.yaml"); do
  grep -qE "\"$i\"[[:space:]]+= \"BC:" "$d/tofu/variables.tf" || ko "défaut de var.macs sans le CT $i"
done
grep -q 'macs.tfvars' "$d/tofu-cible.sh" && ok "tofu-cible.sh charge <cible>.macs.tfvars" || ko "tofu-cible.sh ignore <cible>.macs.tfvars"

t="$(mktemp -d)"; trap 'find "$t" -delete 2>/dev/null' EXIT
cat > "$t/source-ok.sh" <<'EOF'
printf 'hostname: ct%s\nnet0: name=eth0,bridge=vmbr0,hwaddr=bc:24:11:00:00:%02x,ip=dhcp,type=veth\n' "$1" "$(( $1 % 256 ))"
[ "$1" = 117 ] && printf 'net1: name=eth1,bridge=vmbr2,hwaddr=02:00:00:00:00:01,ip=10.10.20.1/24,type=veth\n'
exit 0
EOF
cat > "$t/source-manque.sh" <<'EOF'
[ "$1" = 123 ] && exit 2
printf 'net0: name=eth0,bridge=vmbr0,hwaddr=02:00:00:00:00:02,type=veth\n'
EOF
s="$(RELEVER_MACS_SOURCE="sh $t/source-ok.sh" bash "$d/pra/relever-macs.sh" labo 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '"114" = "02:00:00:00:00:03"' <<<"$s" && ok "relevé complet : MAC en majuscules, une par CT" || ko "relevé complet : $s"
grep -q '"117-eth1" = "02:00:00:00:00:01"' <<<"$s" && ! grep -q '"104-eth1"' <<<"$s" && ok "seconde carte relevée seulement si présente" || ko "eth1 : $s"
s="$(RELEVER_MACS_SOURCE="sh $t/source-manque.sh" bash "$d/pra/relever-macs.sh" labo 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "REFUS : relevé incomplet" <<<"$s" && ok "CT absent : refus, rien n'est écrit" || ko "CT absent non refusé"
[ -f "$d/tofu/labo.macs.tfvars" ] && grep -q "00:00:01" "$d/tofu/labo.macs.tfvars" && ko "un relevé d'essai a été écrit dans tofu/"
exit "$ko"

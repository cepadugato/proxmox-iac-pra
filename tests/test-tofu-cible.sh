#!/usr/bin/env bash
# Test de tofu-cible.sh (feuille 5.6a, D24) : TOUT EN LOCAL. API Proxmox factice en HTTPS sur 127.0.0.1
# (certificat jetable), faux tofu, faux poste-labo --verifier. Aucun appel à pve ni au labo, aucun secret réel.
# Critère : recettes/criteres-lot5-D24.md § 5.6a. Les trois gardes sont testées isolément (une seule condition fausse)
# et l'assertion porte sur la RAISON affichée (endpoint | noeud | empreinte).
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
S="$d/tofu-cible.sh"
tmp="$(mktemp -d "$d/tests/.tmp-XXXXXX")"; fail=0; pids=()
trap 'for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; find "$tmp" -delete 2>/dev/null' EXIT
ok() { echo "OK   $1"; }; ko() { echo "FAIL $1"; fail=1; }
FAUX_JETON="faux@pve!essai=jeton-factice-pas-un-secret"

if [ ! -f "$S" ]; then ko "tofu-cible.sh absent"; exit 1; fi

# --- certificat jetable + API factice ---
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/k.pem" -out "$tmp/c.pem" -days 1 -subj "/CN=127.0.0.1" \
  -addext "subjectAltName=IP:127.0.0.1" >/dev/null 2>&1 || { ko "openssl : certificat jetable impossible"; exit 1; }
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/k2.pem" -out "$tmp/c2.pem" -days 1 -subj "/CN=autre" >/dev/null 2>&1
FP="$(openssl x509 -in "$tmp/c.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
FP2="$(openssl x509 -in "$tmp/c2.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
port_libre() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
demarre_api() { # <noeud> <journal> -> port
  local p; p="$(port_libre)"
  python3 "$d/tests/outils/api-factice.py" "$p" "$tmp/c.pem" "$tmp/k.pem" "$1" "$2" >"$tmp/api-$p.out" 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 50); do grep -q prêt "$tmp/api-$p.out" 2>/dev/null && break; sleep 0.1; done
  echo "$p"
}
touch "$tmp/req-pve.log" "$tmp/req-autre.log" "$tmp/req-labo.log"
P_PVE="$(demarre_api pve "$tmp/req-pve.log")"
P_AUTRE="$(demarre_api autrenoeud "$tmp/req-autre.log")"
P_LABO="$(demarre_api pra-lab "$tmp/req-labo.log")"

# --- faux tofu : journalise argv (sans le jeton), l'environnement utile, sort 0 ---
cat > "$tmp/faux-tofu.sh" <<'EOT'
#!/usr/bin/env bash
{ echo "ARGV: $*"; echo "TF_DATA_DIR=${TF_DATA_DIR:-}"; echo "SSL_CERT_FILE=${SSL_CERT_FILE:-}"
  echo "JETON_PRESENT=$([ -n "${PROXMOX_VE_API_TOKEN:-}" ] && echo oui || echo non)"
  echo "CLI_ARGS=${TF_CLI_ARGS:-}|${TF_CLI_ARGS_plan:-}"; echo "VAR_AUTRE=${TF_VAR_autre:-}"; echo "PHRASE_PRESENTE=$([ -n "${TF_VAR_tofu_enc_passphrase:-}" ] && echo oui || echo non)"
  echo "TF_VAR_ENDPOINT_PRESENT=$([ -n "${TF_VAR_proxmox_endpoint:-}" ] && echo oui || echo non)"; } >> "$FAUX_JOURNAL"
exit "${FAUX_RC:-0}"
EOT
chmod +x "$tmp/faux-tofu.sh"
cat > "$tmp/faux-verif-0.sh" <<'EOT'
#!/usr/bin/env bash
echo "verifier $*" >> "$FAUX_JOURNAL"; exit 0
EOT
cat > "$tmp/faux-verif-4.sh" <<'EOT'
#!/usr/bin/env bash
echo "verifier $*" >> "$FAUX_JOURNAL"; echo "REFUS isolement: double de test" >&2; exit 4
EOT
chmod +x "$tmp"/faux-verif-*.sh

# --- scénario : fabrique conf + dossier tofu + lance ---
# nouveau <nom> : prépare $tmp/<nom>/{conf,tofu} ; tfvars de pve ET labo pointent vers l'API factice
nouveau() {
  local n="$1" port="$2"
  mkdir -p "$tmp/$n/conf" "$tmp/$n/tofu/etat"
  for c in pve labo; do
    printf 'proxmox_endpoint = "https://127.0.0.1:%s/"\nnode = "%s"\ndatastore = "x"\nlabo_started = false\ncible = "%s"\n' \
      "$port" "$([ $c = pve ] && echo pve || echo pra-lab)" "$c" > "$tmp/$n/tofu/$c.tfvars"
  done
  printf 'PROXMOX_VE_API_TOKEN=%s\n' "$FAUX_JETON" | tee "$tmp/$n/conf/ro.env" > "$tmp/$n/conf/labo.env"
  cp "$tmp/c.pem" "$tmp/$n/conf/pve-root-ca.pem"; cp "$tmp/c.pem" "$tmp/$n/conf/labo-ca.pem"
  printf '%s\n' "$FP" > "$tmp/$n/conf/empreinte-pve.sha256"; cp "$tmp/$n/conf/empreinte-pve.sha256" "$tmp/$n/conf/empreinte-labo.sha256"
  mkdir -p "$tmp/$n/tofu/.terraform" "$tmp/$n/tofu/.terraform-labo"
  echo '{"backend":{"type":"local","config":{"path":"etat/pve.tfstate"}}}' > "$tmp/$n/tofu/.terraform/terraform.tfstate"
  echo '{"backend":{"type":"local","config":{"path":"etat/labo.tfstate"}}}' > "$tmp/$n/tofu/.terraform-labo/terraform.tfstate"
  : > "$tmp/$n/journal"
}
lance() { # <nom> <cible> <verif> [args...] -> code ; sortie dans $tmp/<nom>/out
  local n="$1" c="$2" v="$3"; shift 3
  env -i PATH="$PATH" HOME="$tmp/$n" ${MODE_TEST:+TOFU_CIBLE_TEST=1} IAC_CONF_DIR="$tmp/$n/conf" TOFU_CIBLE_TOFU_DIR="$tmp/$n/tofu" \
    TOFU_BIN="$tmp/faux-tofu.sh" TOFU_CIBLE_VERIFIER="$tmp/faux-verif-$v.sh" FAUX_JOURNAL="$tmp/$n/journal" \
    TOFU_CIBLE_ENDPOINT_ATTENDU="https://127.0.0.1:$PORT_ATT" "${EXTRA[@]}" \
    bash "$S" "$c" "$@" >"$tmp/$n/out" 2>&1
  echo $?
}
EXTRA=(ZZ=1); MODE_TEST=1
PORT_ATT="$P_PVE"
attend() { # <libellé> <attendu> <obtenu>
  if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (attendu $2, obtenu $3)"; fi
}
tofu_non_appele() { ! grep -q '^ARGV:' "$tmp/$1/journal"; }
raison() { grep -m1 "REFUS cible=$2" "$tmp/$1/out"; }

# 1. tout vrai : pve plan => 0, tofu appelé avec var-file, TF_DATA_DIR, sans jeton en argv ni sortie
nouveau t1 "$P_PVE"; rc="$(lance t1 pve 0 plan -input=false)"
attend "pve tout vrai => exit 0" 0 "$rc"
grep -q 'ARGV: plan .*-var-file=pve.tfvars' "$tmp/t1/journal" && ok "tofu appelé avec -var-file=pve.tfvars" || ko "var-file pve absent de l'appel tofu"
grep -q 'TF_DATA_DIR=.terraform$' "$tmp/t1/journal" && ok "TF_DATA_DIR=.terraform (pve)" || ko "TF_DATA_DIR pve"
grep -q 'JETON_PRESENT=oui' "$tmp/t1/journal" && ok "jeton transmis par l'environnement" || ko "jeton non transmis à tofu"
grep -q 'TF_VAR_ENDPOINT_PRESENT=non' "$tmp/t1/journal" && ok "aucun TF_VAR_proxmox_endpoint hérité" || ko "TF_VAR_proxmox_endpoint présent"
! grep -rq "jeton-factice" "$tmp/t1/out" "$tmp/t1/journal" && ok "valeur du jeton absente des sorties et d'argv" || ko "valeur du jeton visible"
grep -q 'GET /api2/json/nodes auth=oui' "$tmp/req-pve.log" && ok "nœud lu par GET /api2/json/nodes avec le jeton" || ko "GET nodes non vu par l'API factice"

# 2. endpoint faux (une seule condition) : tfvars pointe ailleurs que l'attendu
nouveau t2 "$P_PVE"; sed -i "s|127.0.0.1:$P_PVE|127.0.0.1:1|" "$tmp/t2/tofu/pve.tfvars"
rc="$(lance t2 pve 0 plan)"; attend "endpoint faux => exit 3" 3 "$rc"
raison t2 pve | grep -q 'endpoint' && ok "raison affichée : endpoint" || ko "raison endpoint absente : $(cat "$tmp/t2/out")"
tofu_non_appele t2 && ok "endpoint faux : tofu non lancé" || ko "tofu lancé malgré endpoint faux"

# 3. nœud faux : l'API répond un autre nœud
nouveau t3 "$P_AUTRE"; PORT_ATT="$P_AUTRE"
rc="$(lance t3 pve 0 plan)"; attend "noeud faux => exit 3" 3 "$rc"
raison t3 pve | grep -q 'noeud' && ok "raison affichée : noeud" || ko "raison noeud absente : $(cat "$tmp/t3/out")"
tofu_non_appele t3 && ok "noeud faux : tofu non lancé" || ko "tofu lancé malgré noeud faux"
PORT_ATT="$P_PVE"

# 4. empreinte fausse
nouveau t4 "$P_PVE"; printf '%s\n' "$FP2" > "$tmp/t4/conf/empreinte-pve.sha256"
before=$(wc -l < "$tmp/req-pve.log")
rc="$(lance t4 pve 0 plan)"; attend "empreinte fausse => exit 3" 3 "$rc"
raison t4 pve | grep -q 'empreinte' && ok "raison affichée : empreinte" || ko "raison empreinte absente : $(cat "$tmp/t4/out")"
tofu_non_appele t4 && ok "empreinte fausse : tofu non lancé" || ko "tofu lancé malgré empreinte fausse"
[ "$(wc -l < "$tmp/req-pve.log")" = "$before" ] && ok "empreinte fausse : le jeton n'est pas envoyé au serveur" || ko "requête authentifiée envoyée malgré empreinte fausse"
# 4 bis. empreinte non enregistrée
nouveau t4b "$P_PVE"; rm "$tmp/t4b/conf/empreinte-pve.sha256"
rc="$(lance t4b pve 0 plan)"; attend "empreinte non enregistrée => exit 3" 3 "$rc"
raison t4b pve | grep -q 'empreinte' && ok "raison affichée : empreinte (absente)" || ko "raison absente : $(cat "$tmp/t4b/out")"

# 5. état : le backend initialisé ne pointe pas sur etat/<cible>.tfstate
nouveau t5 "$P_PVE"; echo '{"backend":{"type":"local","config":{"path":"etat/labo.tfstate"}}}' > "$tmp/t5/tofu/.terraform/terraform.tfstate"
rc="$(lance t5 pve 0 plan)"; attend "backend pve pointant sur l'état du labo => exit 3" 3 "$rc"
raison t5 pve | grep -q 'etat' && ok "raison affichée : etat" || ko "raison etat absente : $(cat "$tmp/t5/out")"
tofu_non_appele t5 && ok "etat faux : tofu non lancé" || ko "tofu lancé malgré état faux"

# 6. labo : double de --verifier en exit 4 => exit 4, tofu non lancé, aucune requête à l'API
nouveau t6 "$P_PVE"; before=$(wc -l < "$tmp/req-pve.log")
rc="$(lance t6 labo 4 plan)"; attend "labo : --verifier rouge => exit 4" 4 "$rc"
grep -q '^verifier --verifier' "$tmp/t6/journal" && ok "labo : poste-labo.sh --verifier appelé" || ko "--verifier non appelé"
tofu_non_appele t6 && ok "labo : tofu non lancé après refus du lien" || ko "tofu lancé malgré lien refusé"
[ "$(wc -l < "$tmp/req-pve.log")" = "$before" ] && ok "labo : aucune requête API après refus du lien" || ko "API contactée malgré lien refusé"

# 7. labo.env absent => exit 2, message distinct de REFUS cible
nouveau t7 "$P_PVE"; rm "$tmp/t7/conf/labo.env"
rc="$(lance t7 labo 0 plan)"; attend "labo.env absent => exit 2" 2 "$rc"
! grep -q 'REFUS cible' "$tmp/t7/out" && ok "labo.env absent : message distinct des refus de garde" || ko "message REFUS cible pour des identifiants absents"
tofu_non_appele t7 && ok "labo.env absent : tofu non lancé" || ko "tofu lancé sans identifiants"
# 7 bis. pve : ro.env absent => exit 2 ; et pve n'appelle jamais --verifier
nouveau t7b "$P_PVE"; rm "$tmp/t7b/conf/ro.env"
rc="$(lance t7b pve 4 plan)"; attend "pve : ro.env absent => exit 2" 2 "$rc"
! grep -q '^verifier' "$tmp/t7b/journal" && ok "pve : --verifier jamais appelé" || ko "pve a appelé --verifier"

# 8. labo tout vrai => 0 : verifier une fois, TF_DATA_DIR labo, var-file labo, CA du labo
nouveau t8 "$P_LABO"; PORT_ATT="$P_LABO"; rc="$(lance t8 labo 0 plan -input=false)"
attend "labo tout vrai => exit 0" 0 "$rc"
[ "$(grep -c '^verifier --verifier' "$tmp/t8/journal")" = 1 ] && ok "labo : --verifier appelé une fois" || ko "--verifier : nombre d'appels"
grep -q 'TF_DATA_DIR=.terraform-labo$' "$tmp/t8/journal" && ok "labo : TF_DATA_DIR=.terraform-labo" || ko "TF_DATA_DIR labo"
grep -q 'ARGV: plan .*-var-file=labo.tfvars' "$tmp/t8/journal" && ok "labo : -var-file=labo.tfvars" || ko "var-file labo"
grep -q "SSL_CERT_FILE=$tmp/t8/conf/labo-ca.pem" "$tmp/t8/journal" && ok "labo : SSL_CERT_FILE = CA du labo" || ko "SSL_CERT_FILE labo"

# 9. init du labo : partage de l'état par cible (-backend-config), jamais le chemin de pve
nouveau t9 "$P_LABO"; rc="$(lance t9 labo 0 init -input=false)"; PORT_ATT="$P_PVE"
attend "labo init => exit 0" 0 "$rc"
grep -q 'ARGV: init .*-backend-config=path=etat/labo.tfstate' "$tmp/t9/journal" && ok "labo init : -backend-config=path=etat/labo.tfstate" || ko "backend-config labo absent"
# 10. un TF_VAR_proxmox_endpoint de l'environnement n'atteint jamais tofu
nouveau t10 "$P_PVE"; EXTRA=(TF_VAR_proxmox_endpoint=https://10.255.70.2:8006/)
rc="$(lance t10 pve 0 plan)"; EXTRA=(ZZ=1)
grep -q 'TF_VAR_ENDPOINT_PRESENT=non' "$tmp/t10/journal" && ok "TF_VAR_proxmox_endpoint hérité retiré" || ko "TF_VAR_proxmox_endpoint transmis"
# 11. cible inconnue / absente => exit 2
nouveau t11 "$P_PVE"; rc="$(lance t11 prod 0 plan)"; attend "cible inconnue => exit 2" 2 "$rc"

# --- code réel : variables, tfvars, features ---
v="$d/tofu/variables.tf"
for var in node datastore labo_started; do grep -q "variable \"$var\"" "$v" && ok "variables.tf : $var" || ko "variables.tf : $var absente"; done
grep -qE '^proxmox_endpoint *= *"https://10\.255\.70\.2:8006/?"' "$d/tofu/labo.tfvars" 2>/dev/null && ok "labo.tfvars : endpoint 10.255.70.2:8006" || ko "labo.tfvars : endpoint"
grep -qE '^node *= *"pra-lab"' "$d/tofu/labo.tfvars" 2>/dev/null && ok "labo.tfvars : node pra-lab" || ko "labo.tfvars : node"
grep -qE '^datastore *= *"local-lvm"' "$d/tofu/labo.tfvars" 2>/dev/null && ok "labo.tfvars : datastore local-lvm (lvmthin, rootdir ; essai 1 de 5.7)" || ko "labo.tfvars : datastore"
grep -qE '^labo_started *= *(true|false)' "$d/tofu/labo.tfvars" 2>/dev/null && ok "labo.tfvars : labo_started présent" || ko "labo.tfvars : labo_started"
grep -qE '^proxmox_endpoint *= *"https://127\.0\.0\.1:8006/?"' "$d/tofu/pve.tfvars" 2>/dev/null && ok "pve.tfvars : endpoint 127.0.0.1:8006" || ko "pve.tfvars : endpoint"
grep -qE '^node *= *"pve"' "$d/tofu/pve.tfvars" 2>/dev/null && ok "pve.tfvars : node pve" || ko "pve.tfvars : node"
grep -qE '^datastore *= *"tank"' "$d/tofu/pve.tfvars" 2>/dev/null && ok "pve.tfvars : datastore tank" || ko "pve.tfvars : datastore"
for ct in ct100 ct101 ct122; do
  f="$d/tofu/$ct.tf"
  grep -qE 'node_name *= *var\.node' "$f" && ok "$ct.tf : node_name = var.node" || ko "$ct.tf : node_name littéral"
  grep -qE 'datastore_id *= *var\.datastore' "$f" && ok "$ct.tf : datastore_id = var.datastore" || ko "$ct.tf : datastore littéral"
  grep -qE 'started *= *var\.labo_started' "$f" && ok "$ct.tf : started = var.labo_started" || ko "$ct.tf : started littéral"
  awk '/ignore_changes/{f=1} f&&/features/{ok=1} END{exit !ok}' "$f" && ok "$ct.tf : features en ignore_changes (D17)" || ko "$ct.tf : features hors ignore_changes"
done
# pve garde son comportement : valeurs par défaut = valeurs d'avant
grep -A3 'variable "node"' "$v" | grep -q 'default *= *"pve"' && ok "node : défaut pve" || ko "node : défaut"
grep -A3 'variable "datastore"' "$v" | grep -q 'default *= *"tank"' && ok "datastore : défaut tank" || ko "datastore : défaut"
grep -A3 'variable "labo_started"' "$v" | grep -q 'default *= *true' && ok "labo_started : défaut true (pve inchangé)" || ko "labo_started : défaut"
# le script ne lance jamais tofu sans passer par les gardes : pas d'appel direct hors fonction
grep -q 'poste-labo.sh' "$S" && ok "tofu-cible.sh référence poste-labo.sh (--verifier)" || ko "poste-labo.sh non référencé"


# ===== Corrections du juge (NO-GO 2026-10-18) =====
# R1 : crochets d'essai refusés hors mode test explicite, et hors de tests/ même en mode test
nouveau r1 "$P_LABO"; PORT_ATT="$P_LABO"; MODE_TEST=
rc="$(lance r1 labo 0 plan)"; MODE_TEST=1
attend "R1 crochet TOFU_CIBLE_VERIFIER sans mode test => exit 3" 3 "$rc"
grep -q 'REFUS cible=labo : crochet' "$tmp/r1/out" && ok "R1 raison affichée : crochet" || ko "R1 raison crochet absente : $(cat "$tmp/r1/out")"
tofu_non_appele r1 && ok "R1 : tofu non lancé" || ko "R1 : tofu lancé"
! grep -q '^verifier' "$tmp/r1/journal" && ok "R1 : faux verifier non appelé non plus" || ko "R1 : verifier de crochet appelé"
nouveau r1b "$P_LABO"; cp "$tmp/faux-verif-0.sh" /tmp/verif-hors-tests-$$.sh 2>/dev/null
env -i PATH="$PATH" HOME="$tmp/r1b" TOFU_CIBLE_TEST=1 IAC_CONF_DIR="$tmp/r1b/conf" TOFU_CIBLE_TOFU_DIR="$tmp/r1b/tofu" TOFU_BIN="$tmp/faux-tofu.sh" \
  TOFU_CIBLE_VERIFIER=/bin/true FAUX_JOURNAL="$tmp/r1b/journal" TOFU_CIBLE_ENDPOINT_ATTENDU="https://127.0.0.1:$P_LABO" bash "$S" labo plan >"$tmp/r1b/out" 2>&1; rc=$?
attend "R1 crochet hors tests/ même en mode test => exit 3" 3 "$rc"
tofu_non_appele r1b && ok "R1 hors tests/ : tofu non lancé" || ko "R1 hors tests/ : tofu lancé"
rm -f /tmp/verif-hors-tests-$$.sh
for hook in TOFU_BIN IAC_CONF_DIR TOFU_CIBLE_TOFU_DIR TOFU_CIBLE_ENDPOINT_ATTENDU; do
  nouveau r1c "$P_PVE"; PORT_ATT="$P_PVE"; MODE_TEST=; rc="$(lance r1c pve 0 plan)"; MODE_TEST=1
  attend "R1 $hook sans mode test => exit 3" 3 "$rc"
done
# R2 : environnement hérité retiré
nouveau r2 "$P_PVE"; PORT_ATT="$P_PVE"
EXTRA=(TF_CLI_ARGS="-var-file=/ailleurs.tfvars" TF_CLI_ARGS_plan="-state=x" TF_DATA_DIR=.terraform-labo TF_VAR_autre=intrus TF_VAR_tofu_enc_passphrase=phrase-factice-de-test)
rc="$(lance r2 pve 0 plan)"; EXTRA=(ZZ=1)
attend "R2 env hérité : exit 0" 0 "$rc"
grep -q '^CLI_ARGS=|$' "$tmp/r2/journal" && ok "R2 TF_CLI_ARGS* retirés" || ko "R2 TF_CLI_ARGS transmis : $(grep CLI_ARGS "$tmp/r2/journal")"
grep -q '^TF_DATA_DIR=.terraform$' "$tmp/r2/journal" && ok "R2 TF_DATA_DIR hérité écrasé" || ko "R2 TF_DATA_DIR hérité"
grep -q '^VAR_AUTRE=$' "$tmp/r2/journal" && ok "R2 TF_VAR_* hérité retiré" || ko "R2 TF_VAR_autre transmis"
grep -q '^PHRASE_PRESENTE=oui' "$tmp/r2/journal" && ok "R2 la phrase d'état (TF_VAR_tofu_enc_passphrase) reste transmise" || ko "R2 phrase d'état perdue"
! grep -rq "phrase-factice" "$tmp/r2/out" && ok "R2 phrase jamais affichée" || ko "R2 phrase affichée"
# R2 : options utilisateur refusées
for opt in "-var=cible=labo" "-var-file=/ailleurs.tfvars" "-var-file" "-chdir=/x" "-state=etat/pve.tfstate" "-state-out=/x" "-backend-config=path=/x" "-lock=false" "--var-file=/x" "-backup=/x"; do
  nouveau r2o "$P_PVE"; PORT_ATT="$P_PVE"; rc="$(lance r2o pve 0 plan -input=false $opt)"
  if [ "$rc" = 3 ] && grep -q 'REFUS cible=pve : option' "$tmp/r2o/out" && tofu_non_appele r2o; then ok "R2 option refusée : $opt"; else ko "R2 option $opt (rc=$rc) : $(cat "$tmp/r2o/out")"; fi
done
nouveau r2p "$P_PVE"; rc="$(lance r2p pve 0 -chdir=/x plan)"; attend "R2 option en place de sous-commande => exit 3" 3 "$rc"
nouveau r2q "$P_PVE"; rc="$(lance r2q pve 0 plan -input=false -lock-timeout=5s)"; attend "R2 options légitimes (-input, -lock-timeout) passent" 0 "$rc"
nouveau r2r "$P_PVE"; rc="$(lance r2r pve 0 plan -out=plan.bin -detailed-exitcode)"; attend "R2 -out et -detailed-exitcode passent" 0 "$rc"
# D25 : le .tfvars doit déclarer la bonne cible
nouveau d25 "$P_PVE"; PORT_ATT="$P_PVE"; sed -i 's/^cible = .*/cible = "labo"/' "$tmp/d25/tofu/pve.tfvars"
rc="$(lance d25 pve 0 plan)"; attend "D25 pve.tfvars déclarant cible=labo => exit 3" 3 "$rc"
grep -q 'REFUS cible=pve : cible' "$tmp/d25/out" && ok "D25 raison affichée : cible" || ko "D25 raison cible absente : $(cat "$tmp/d25/out")"
tofu_non_appele d25 && ok "D25 : tofu non lancé" || ko "D25 : tofu lancé"
# D25 : code réel
grep -q 'variable "cible"' "$v" && ok "variables.tf : cible" || ko "variables.tf : cible absente"
grep -A12 'variable "cible"' "$v" | grep -q 'default *= *"pve"' && ok "cible : défaut pve" || ko "cible : défaut"
grep -A12 'variable "cible"' "$v" | grep -q 'validation' && ok "cible : validation" || ko "cible : validation"
grep -qE '^cible *= *"pve"' "$d/tofu/pve.tfvars" && ok "pve.tfvars : cible pve" || ko "pve.tfvars : cible"
grep -qE '^cible *= *"labo"' "$d/tofu/labo.tfvars" && ok "labo.tfvars : cible labo" || ko "labo.tfvars : cible"
grep -q 'resource "terraform_data" "verrou_cible"' "$d"/tofu/*.tf && grep -q 'triggers_replace *= *var\.cible' "$d"/tofu/*.tf && ok "verrou_cible (triggers_replace = var.cible)" || ko "verrou_cible absent"
grep -A8 'verrou_cible' "$d"/tofu/*.tf | grep -q 'prevent_destroy *= *true' && ok "verrou_cible : prevent_destroy" || ko "verrou_cible : prevent_destroy"

[ $fail -eq 0 ] && echo "OK test-tofu-cible"
exit $fail

#!/usr/bin/env bash
# Feuille 2.3 : contrôle de conformité (équivalent de --check). Lecture seule, jamais d'écriture sur pve.
#   Étape 1 (statique, sans réseau) : fmt -check puis validate.
#   Étape 2 (réseau, jeton lecture seule, tunnel-pve actif) : plan -detailed-exitcode.
# Codes : 0 rien à faire, 2 dérive (le plan propose des changements), 1 erreur.
# Variables de test : VERIFIER_TOFU (commande substituable), VERIFIER_SANS_ENV=1, VERIFIER_SANS_TUNNEL=1.
set -u
d="$(cd "$(dirname "$0")" && pwd)"; cfg="$HOME/.config/infra-as-code"
outil="${VERIFIER_TOFU:-tofu}"
flt() { sed -E 's/(PVEAPIToken=)[^ ]+/\1***/g'; }
cd "$d/tofu" || { echo "ERREUR: dossier tofu/ introuvable"; exit 1; }

echo "== étape 1 : statique (sans réseau)"
"$outil" fmt -check -recursive -no-color 2>&1 | flt | tail -n 20; rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] || { echo "ERREUR: fmt -check rc=$rc (lancer le formatage à la main)"; exit 1; }
"$outil" validate -no-color 2>&1 | flt | tail -n 20; rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] || { echo "ERREUR: validate rc=$rc"; exit 1; }
echo "étape 1 : OK"

echo "== étape 2 : plan -detailed-exitcode (lecture seule)"
if [ "${VERIFIER_SANS_ENV:-0}" != 1 ]; then
  [ -r "$cfg/ro.env" ] || { echo "ERREUR: $cfg/ro.env illisible"; exit 1; }
  set -a; . "$cfg/ro.env"; set +a
  export TF_VAR_proxmox_endpoint="https://127.0.0.1:8006/" SSL_CERT_FILE="$cfg/pve-root-ca.pem"
fi
if [ "${VERIFIER_SANS_TUNNEL:-0}" != 1 ]; then
  (exec 3<>/dev/tcp/127.0.0.1/8006) 2>/dev/null || { echo "ERREUR: tunnel-pve inactif (127.0.0.1:8006 ne répond pas)"; exit 1; }
fi
"$outil" plan -input=false -no-color -lock=false -detailed-exitcode 2>&1 | flt | grep -E '^Plan|^No changes|^Error|^ +[-+~] ' | tail -n 40; rc=${PIPESTATUS[0]}
case "$rc" in
  0) echo "CONFORME : rien à faire (exit 0)"; exit 0 ;;
  2) echo "DÉRIVE : le plan propose des changements (exit 2)"; exit 2 ;;
  *) echo "ERREUR: plan rc=$rc"; exit 1 ;;
esac

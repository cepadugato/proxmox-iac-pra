#!/usr/bin/env bash
# tofu-cible.sh — feuille 5.6a (D24) : SEUL point d'entrée de tofu vers pve ou vers le labo imbriqué.
# Usage : ./tofu-cible.sh <pve|labo|secours> <sous-commande tofu> [options...]
#         ./tofu-cible.sh <pve|labo> empreinte               affiche l'empreinte SHA-256 du certificat servi (sans jeton)
#         ./tofu-cible.sh <pve|labo> enregistrer-empreinte   l'enregistre si aucune n'existe (geste de confiance : à lire avant)
# Fixe, par cible : TF_DATA_DIR (.terraform | .terraform-labo), -var-file (<cible>.tfvars), l'état (etat/<cible>.tfstate,
# chiffré par tofu/chiffrement.tf avec la MÊME phrase TF_VAR_tofu_enc_passphrase, jamais lue ni affichée ici), le fichier
# d'identifiants (pve : ro.env pour plan, rw.env sinon ; labo : labo.env) et la CA (pve-root-ca.pem | labo-ca.pem, SSL_CERT_FILE).
# Gardes avant TOUTE sous-commande (hors empreinte) ; écart = exit 3 « REFUS cible=<c> : <raison> » :
#   endpoint   l'endpoint du .tfvars n'est pas l'attendu (pve = 127.0.0.1:8006 tunnel 1.7 ; labo = 10.255.70.2:8006) ni le nœud
#   empreinte  le SHA-256 du certificat servi diffère de celui enregistré (absent = refus). Contrôlée AVANT l'envoi du jeton :
#              le jeton ne part jamais vers un serveur qu'on n'a pas reconnu (ordre 1-3-2 par rapport au critère, même effet)
#   noeud      GET /api2/json/nodes (jeton de la cible) ne renvoie pas le nœud attendu (pve | pra-lab)
#   etat       le backend initialisé dans TF_DATA_DIR ne pointe pas sur etat/<cible>.tfstate (sauf init, qui le fixe)
# Labo : d'abord « pra/poste-labo.sh --verifier » (5.14a) ; exit 4 = refus, tofu n'est pas lancé.
# Codes : 0 ok / code de tofu ; 2 usage ou identifiants absents ; 3 garde de cible ; 4 lien du labo refusé.
# Variables de test (jamais nécessaires en usage réel) : IAC_CONF_DIR, TOFU_CIBLE_TOFU_DIR, TOFU_BIN, TOFU_CIBLE_VERIFIER,
# TOFU_CIBLE_ENDPOINT_ATTENDU.
set -u
# Environnement hérité : rien de ce qui peut changer la cible, les variables ou l'état ne traverse (juge 2026-10-18, R2).
# Seule la phrase d'état TF_VAR_tofu_enc_passphrase est conservée (jamais lue ni affichée ici).
for _v in $(compgen -e); do
  case "$_v" in
    TF_VAR_tofu_enc_passphrase) ;;
    TF_CLI_ARGS*|TF_DATA_DIR|TF_WORKSPACE|TF_VAR_*) unset "$_v" ;;
  esac
done
# Phrase absente de l'environnement : celle chargée en mémoire par phrase-session.sh, si elle n'a pas expiré.
_pd="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/infra-as-code"
if [ -z "${TF_VAR_tofu_enc_passphrase:-}" ] && [ -s "$_pd/phrase" ] && [ -s "$_pd/phrase.expire" ] &&
   [ "$(date +%s)" -lt "$(cat "$_pd/phrase.expire")" ]; then
  TF_VAR_tofu_enc_passphrase="$(cat "$_pd/phrase")"; export TF_VAR_tofu_enc_passphrase
fi
unset _pd
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Crochets d'essai (R1) : actifs seulement avec TOFU_CIBLE_TEST=1, et leurs chemins doivent résider sous tests/ du projet.
_crochets="${IAC_CONF_DIR:-}${TOFU_CIBLE_TOFU_DIR:-}${TOFU_BIN:-}${TOFU_CIBLE_VERIFIER:-}${TOFU_CIBLE_ENDPOINT_ATTENDU:-}"
CONF="${IAC_CONF_DIR:-$HOME/.config/infra-as-code}"
TD="${TOFU_CIBLE_TOFU_DIR:-$PROJ/tofu}"
TOFU="${TOFU_BIN:-tofu}"
VERIF="${TOFU_CIBLE_VERIFIER:-$PROJ/pra/poste-labo.sh}"

cible="${1:-}"; shift 2>/dev/null || true
sub="${1:-}"
case "$cible" in
  pve)  ATT_EP="https://127.0.0.1:8006"; ATT_NODE="pve";     DATADIR=".terraform";      CA="$CONF/pve-root-ca.pem" ;;
  labo) ATT_EP="https://10.255.70.2:8006"; ATT_NODE="pra-lab"; DATADIR=".terraform-labo"; CA="$CONF/labo-ca.pem" ;;
  secours)
    # vrai Proxmox de secours (5.15, D27) : adresse et nœud écrits par pra/secours-preparer.sh, jamais dans le dépôt
    _sc="$CONF/secours.conf"
    _ip="$(sed -n 's/^SECOURS_IP=\([0-9.]*\)$/\1/p' "$_sc" 2>/dev/null | head -1)"
    _nd="$(sed -n 's/^SECOURS_NOEUD=\([A-Za-z0-9-]*\)$/\1/p' "$_sc" 2>/dev/null | head -1)"
    [[ "$_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && [ -n "$_nd" ] || { echo "cible secours non préparée : $_sc illisible (pra/secours-preparer.sh)" >&2; exit 2; }
    case "$_ip" in 10.255.70.2) [ "${PRA_REPETITION_LABO:-}" = 1 ] || { echo "REFUS cible=secours : $_ip est le labo (répétition : PRA_REPETITION_LABO=1)" >&2; exit 3; } ;;
      127.*|10.255.70.*) echo "REFUS cible=secours : adresse réservée à pve (tunnel) ou au labo : $_ip" >&2; exit 3 ;; esac
    ATT_EP="https://$_ip:8006"; ATT_NODE="$_nd"; DATADIR=".terraform-secours"; CA="$CONF/secours-ca.pem"
    # le verrou de tofu/verrou.tf n'admet alors que l'endpoint du labo
    [ "$_ip" = 10.255.70.2 ] && { TF_VAR_repetition_labo=true; export TF_VAR_repetition_labo; } ;;
  *) echo "usage : $0 <pve|labo|secours> <sous-commande tofu|empreinte|enregistrer-empreinte> [options]" >&2; exit 2 ;;
esac
[ -n "$sub" ] || { echo "usage : $0 $cible <sous-commande tofu> [options]" >&2; exit 2; }
ATT_EP="${TOFU_CIBLE_ENDPOINT_ATTENDU:-$ATT_EP}"
FPFILE="$CONF/empreinte-$cible.sha256"
refus() { echo "REFUS cible=$cible : $1" >&2; exit 3; }
if [ -n "$_crochets" ]; then
  [ "${TOFU_CIBLE_TEST:-}" = 1 ] || refus "crochet d'essai (IAC_CONF_DIR, TOFU_CIBLE_*, TOFU_BIN) sans TOFU_CIBLE_TEST=1"
  for _c in "${IAC_CONF_DIR:-}" "${TOFU_CIBLE_TOFU_DIR:-}" "${TOFU_BIN:-}" "${TOFU_CIBLE_VERIFIER:-}"; do
    [ -z "$_c" ] && continue
    _r="$(realpath -m -- "$_c" 2>/dev/null)"
    case "$_r" in "$PROJ"/tests/*) ;; *) refus "crochet d'essai hors de $PROJ/tests/ : $_c" ;; esac
  done
  # le double de --verifier vit dans un dossier jetable des tests, jamais un script du dépôt
  if [ -n "${TOFU_CIBLE_VERIFIER:-}" ]; then
    case "$(realpath -m -- "$TOFU_CIBLE_VERIFIER")" in
      "$PROJ"/tests/.tmp-*) ;;
      *) refus "crochet d'essai : TOFU_CIBLE_VERIFIER hors de tests/.tmp-*" ;;
    esac
  fi
fi
# Options utilisateur interdites (R2) : elles contourneraient var-file, état, verrou ou dossier de la cible.
for _a in "$sub" "${@:2}"; do
  case "$_a" in
    -*) case "$_a" in
          -input=*|-input|-detailed-exitcode|-out=*|-no-color|-json|-lock-timeout=*|-parallelism=*|-refresh=*|-refresh-only|-compact-warnings|-replace=*|-reconfigure|-upgrade|-lockfile=*|-plugin-dir=*|-concise|-generate-config-out=*|-out|-destroy) ;;
          -lock=true|-lock=1) ;;
          *) refus "option interdite après la sous-commande : ${_a%%=*} (var, var-file, chdir, state, backend-config, lock=false et inconnues refusés)" ;;
        esac ;;
  esac
done

# --- lien du labo (5.14a) : avant tout, y compris avant de lire des identifiants ---
if [ "$cible" = labo ]; then
  bash "$VERIF" --verifier; rc=$?
  if [ "$rc" -ne 0 ]; then echo "REFUS cible=labo : lien (poste-labo.sh --verifier a rendu $rc) ; tofu n'est pas lancé" >&2; exit 4; fi
fi

PY='
import hashlib, json, os, socket, ssl, sys, urllib.request
mode, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
if mode == "fp":
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection((host, port), timeout=10) as s, ctx.wrap_socket(s, server_hostname=host) as t:
        print(hashlib.sha256(t.getpeercert(binary_form=True)).hexdigest())
elif mode == "nodes":
    ctx = ssl.create_default_context(cafile=sys.argv[4])
    rq = urllib.request.Request("https://%s:%d/api2/json/nodes" % (host, port),
                                headers={"Authorization": "PVEAPIToken=" + os.environ["PROXMOX_VE_API_TOKEN"]})
    with urllib.request.urlopen(rq, timeout=10, context=ctx) as r:
        for n in json.load(r)["data"]:
            print(n["node"])
'
# hôte et port d'un endpoint https://h:p[/]
hp() { local e="${1#https://}"; e="${e%%/*}"; echo "${e%%:*} ${e##*:}"; }
norm() { local e="$1"; e="${e%/}"; echo "$e"; }

# --- identifiants (exit 2 : message distinct des refus de garde) ---
if [ "$sub" = empreinte ] || [ "$sub" = enregistrer-empreinte ]; then :
else
  if [ "$cible" = pve ]; then [ "$sub" = plan ] && ENVF="$CONF/ro.env" || ENVF="$CONF/rw.env"; else ENVF="$CONF/$cible.env"; fi
  [ -r "$ENVF" ] || { echo "identifiants absents ou illisibles : $ENVF (cible $cible)" >&2; exit 2; }
  PROXMOX_VE_API_TOKEN=""; set -a; . "$ENVF"; set +a
  [ -n "${PROXMOX_VE_API_TOKEN:-}" ] || { echo "PROXMOX_VE_API_TOKEN absent de $ENVF" >&2; exit 2; }
fi
TFV="$TD/$cible.tfvars"
[ -r "$TFV" ] || { echo "fichier de variables absent : $TFV" >&2; exit 2; }

# --- empreinte seule ---
read -r H P <<<"$(hp "$ATT_EP")"
if [ "$sub" = empreinte ]; then python3 -I -c "$PY" fp "$H" "$P" || { echo "certificat illisible sur $H:$P" >&2; exit 2; }; exit 0; fi
if [ "$sub" = enregistrer-empreinte ]; then
  [ ! -e "$FPFILE" ] || { echo "déjà enregistrée : $FPFILE (la supprimer à la main pour la remplacer)" >&2; exit 2; }
  fp="$(python3 -I -c "$PY" fp "$H" "$P")" || { echo "certificat illisible sur $H:$P" >&2; exit 2; }
  mkdir -p "$CONF"; ( umask 077; printf '%s\n' "$fp" > "$FPFILE" ); echo "empreinte de $cible enregistrée : $fp"; exit 0
fi

# --- garde 1 : endpoint (et nœud déclaré) du .tfvars ---
val() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$TFV" | head -n 1; }
ep="$(val proxmox_endpoint)"; nd="$(val node)"
[ "$(norm "$ep")" = "$(norm "$ATT_EP")" ] || refus "endpoint ($TFV : « $ep », attendu « $ATT_EP »)"
cb="$(val cible)"
[ "$cb" = "$cible" ] || refus "cible (déclarée « $cb » dans $TFV, attendue « $cible » : verrou D25)"
[ "$nd" = "$ATT_NODE" ] || refus "noeud déclaré dans $TFV : « $nd », attendu « $ATT_NODE »"

# --- garde 3 : empreinte du certificat servi (avant que le jeton ne parte) ---
[ -r "$FPFILE" ] || refus "empreinte non enregistrée ($FPFILE ; ./tofu-cible.sh $cible enregistrer-empreinte)"
att_fp="$(tr -d ': \n' < "$FPFILE" | tr 'A-F' 'a-f')"
srv_fp="$(python3 -I -c "$PY" fp "$H" "$P" 2>/dev/null)" || refus "empreinte : certificat illisible sur $H:$P"
[ "$srv_fp" = "$att_fp" ] || refus "empreinte (servie $srv_fp, enregistrée $att_fp)"

# --- garde 2 : nœud lu par l'API avec le jeton de la cible ---
export SSL_CERT_FILE="$CA"
noeuds="$(python3 -I -c "$PY" nodes "$H" "$P" "$CA" 2>/dev/null)" || refus "noeud : GET /api2/json/nodes en échec (jeton ou CA de la cible)"
[ "$noeuds" = "$ATT_NODE" ] || refus "noeud (l'API répond « $(echo "$noeuds" | tr '\n' ' ') », attendu « $ATT_NODE »)"

# --- garde 4 : l'état du backend initialisé est celui de la cible ---
if [ "$sub" != init ]; then
  chemin="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["backend"]["config"]["path"])' "$TD/$DATADIR/terraform.tfstate" 2>/dev/null)" \
    || refus "etat : $TD/$DATADIR non initialisé (./tofu-cible.sh $cible init)"
  [ "$chemin" = "etat/$cible.tfstate" ] || refus "etat (backend sur « $chemin », attendu « etat/$cible.tfstate »)"
fi

# --- lancement ---
unset TF_VAR_proxmox_endpoint TF_VAR_node TF_VAR_datastore TF_VAR_labo_started TF_DATA_DIR
export TF_DATA_DIR="$DATADIR"
inj=()
case "$sub" in
  init) inj=("-backend-config=path=etat/$cible.tfstate") ;;
  plan|apply|import|destroy|refresh|console)
    inj=("-var-file=$cible.tfvars")
    # MAC relevées sur la cible par pra/relever-macs.sh (absent : celles de pve, défaut de var.macs)
    [ -f "$TD/$cible.macs.tfvars" ] && inj+=("-var-file=$cible.macs.tfvars") ;;
esac
cd "$TD" || exit 2
"$TOFU" "$sub" "${inj[@]}" "${@:2}"
exit $?

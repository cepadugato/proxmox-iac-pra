#!/usr/bin/env bash
# phrase-session.sh : garde EN MÉMOIRE, le temps d'une session, la phrase d'état OpenTofu et la clé GPG des sauvegardes
# de pve (geste de l'admin, une saisie du mot de passe maître).
#   phrase-session.sh charger [heures]   lit dans le noyau KeePassXC la phrase d'état et la pièce jointe .sauvegarde-pve.key,
#                                        les écrit dans /run/user/<uid>/infra-as-code/ (tmpfs, 600) ; expiration 8 h par défaut
#   phrase-session.sh etat               dit ce qui est chargé et jusqu'à quand (jamais les valeurs)
#   phrase-session.sh retirer            efface tout de la mémoire
# tofu-cible.sh lit la phrase si TF_VAR_tofu_enc_passphrase est vide ; pra/archives-vers-labo.sh lit la clé GPG.
# Rien n'est écrit sur disque ; la déconnexion efface tout.
set -u
set +x
D="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/infra-as-code"
F="$D/phrase"; G="$D/cle-gpg"; E="$D/phrase.expire"
K="$HOME/noyau-amorcage-ip/noyau-amorcage-ip.kdbx"
ENTREE="03-Sauvegardes/Phrase d'état OpenTofu (infra-as-code)"
ENTREE_GPG="03-Sauvegardes/Clé de chiffrement — sauvegardes de l'INFRASTRUCTURE"
PJ_GPG=".sauvegarde-pve.key"

valide() { [ -s "$1" ] && [ -s "$E" ] && [ "$(date +%s)" -lt "$(cat "$E")" ]; }
case "${1:-}" in
  charger)
    h="${2:-8}"; case "$h" in ''|*[!0-9]*) echo "durée en heures entières" >&2; exit 2 ;; esac
    { : </dev/tty; } 2>/dev/null || { echo "à lancer dans un vrai terminal" >&2; exit 1; }
    findmnt -no FSTYPE --target "${D%/*}" | grep -qx tmpfs || { echo "REFUS : ${D%/*} n'est pas en mémoire (tmpfs)" >&2; exit 1; }
    ( umask 077; mkdir -p "$D"
      IFS= read -r -s -p "Mot de passe du noyau KeePassXC ($(basename "$K")) : " PW </dev/tty; echo >/dev/tty
      kpx() { printf '%s\n' "$PW" | keepassxc-cli "$@" -q; }
      t="$(mktemp "$D/.p.XXXXXX")"; u="$(mktemp "$D/.g.XXXXXX")"
      trap 'rm -f "$t" "$u"; unset PW' EXIT
      kpx show -s -a password "$K" "$ENTREE" > "$t" || { echo "lecture de la phrase refusée" >&2; exit 1; }
      [ "$(tr -d '\n' < "$t" | wc -c)" -ge 32 ] || { echo "phrase absente ou trop courte" >&2; exit 1; }
      kpx attachment-export --stdout "$K" "$ENTREE_GPG" "$PJ_GPG" > "$u" || { echo "lecture de la clé GPG refusée" >&2; exit 1; }
      [ -s "$u" ] || { echo "clé GPG vide" >&2; exit 1; }
      tr -d '\n' < "$t" > "$F"; cp "$u" "$G"
      echo $(( $(date +%s) + h * 3600 )) > "$E" ) || exit 1
    valide "$F" && valide "$G" && echo "phrase d'état et clé GPG chargées en mémoire jusqu'à $(date -d "@$(cat "$E")" '+%H:%M') (jamais affichées)" ;;
  etat)
    ok=0
    valide "$F" && { echo "phrase d'état chargée, valable jusqu'à $(date -d "@$(cat "$E")" '+%H:%M')"; ok=1; } || echo "aucune phrase d'état valide en mémoire"
    valide "$G" && echo "clé GPG des sauvegardes chargée (empreinte $(sha256sum < "$G" | cut -c1-12))" || echo "aucune clé GPG valide en mémoire"
    [ "$ok" -eq 1 ] ;;
  retirer)
    rm -f -- "$F" "$G" "$E"; echo "phrase et clé retirées de la mémoire" ;;
  *) echo "usage : $0 charger [heures] | etat | retirer" >&2; exit 2 ;;
esac

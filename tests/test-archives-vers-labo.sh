#!/usr/bin/env bash
# Test de pra/archives-vers-labo.sh (feuille 5.12b, D24 (1)) : TOUT À SEC.
# Dossier jetable : faux MANIFESTE, faux périmètre, faux labo (un dossier), faux ssh (exécute la commande distante
# dans ce dossier), faux poste-labo.sh, faux gpg pour les pannes (code 2, DECRYPTION_FAILED) ; vrai gpg symétrique
# (GNUPGHOME jetable) sur une toute petite archive de test. Aucune vraie archive, aucun labo, aucun secret réel.
# Critères : recettes/criteres-lot5-D24.md § 5.12b.
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "$d/tests/.tmp-XXXXXX")"; fail=0
trap 'find "$tmp" -delete 2>/dev/null' EXIT
ok() { echo "OK   $1"; }; ko() { echo "FAIL $1"; fail=1; }
S="$d/pra/archives-vers-labo.sh"
if [ ! -f "$S" ]; then ko "script absent : pra/archives-vers-labo.sh"; exit 1; fi

REAL_GPG="$(command -v gpg)"; command -v zstd >/dev/null && command -v tar >/dev/null || { ko "zstd/tar absents du poste"; exit 1; }
export GNUPGHOME="$tmp/gnupg"; mkdir -m 700 "$GNUPGHOME"
DBL="$tmp/dbl"; mkdir -p "$DBL"
LABO="$tmp/labo"; mkdir -p "$LABO"
T="$tmp/tirage/2026-S99"; mkdir -p "$T"
R="$tmp/run"; mkdir -p "$R"; chmod 700 "$R"
J="$tmp/journal"; : > "$J"

# faux ssh : journalise, exécute la commande distante (dernier argument) localement ; STUB_SSH_CORRUPT=1 altère l'écriture
cat > "$DBL/ssh" <<'DBL'
#!/usr/bin/env bash
cmd="${@: -1}"
echo "ssh $cmd" >> "$STUB_J"
[ "${STUB_SSH_NORM:-0}" = 1 ] && case "$cmd" in "rm "*) exit 1 ;; esac
case "$cmd" in
  "cat > "*) if [ "${STUB_SSH_CORRUPT:-0}" = 1 ]; then { cat; printf 'x'; } | bash -c "$cmd"; else bash -c "$cmd"; fi; exit $? ;;
esac
bash -c "$cmd"
DBL
# faux gpg : pannes. STUB_GPG=rc2 (clair complet, OKAY, mais code 2) | failed (DECRYPTION_FAILED, code 0)
cat > "$DBL/gpg" <<'DBL'
#!/usr/bin/env bash
echo "gpg $*" >> "$STUB_J"
f="${@: -1}"
case "${STUB_GPG:-}" in
  rc2) echo "[GNUPG:] DECRYPTION_OKAY" >&4; "$STUB_REAL_GPG" --batch --pinentry-mode loopback --passphrase-fd 3 -d "$f" 2>/dev/null; exit 2 ;;
  nomdc) echo "[GNUPG:] DECRYPTION_OKAY" >&4; head -c 100 /dev/zero; exit 0 ;;
  badmdc) echo "[GNUPG:] GOODMDC" >&4; echo "[GNUPG:] BADMDC" >&4; echo "[GNUPG:] DECRYPTION_OKAY" >&4; head -c 100 /dev/zero; exit 0 ;;
  failed) echo "[GNUPG:] DECRYPTION_FAILED" >&4; head -c 100 /dev/zero; exit 0 ;;
  *) exec "$STUB_REAL_GPG" "$@" ;;
esac
DBL
cat > "$tmp/poste-labo-ok.sh" <<'DBL'
#!/usr/bin/env bash
echo "poste-labo $*" >> "$STUB_J"; exit "${STUB_VERIF_RC:-0}"
DBL
chmod +x "$DBL"/* "$tmp/poste-labo-ok.sh"

# archive de test : tar.zst avec ./etc/vzdump/pct.conf, chiffrée en gpg symétrique AES256 (comme sauvegarde-hebdo.sh)
printf 'phrase-de-test-jetable-0123456789abcdef0123456789\n' | tr -d '\n' > "$tmp/cle"
mk() { # vmid horodatage avec_pctconf
  local id="$1" ts="$2" pc="${3:-1}" w="$tmp/w$1"; [ -d "$w" ] && find "$w" -mindepth 1 -delete; mkdir -p "$w/etc/vzdump" "$w/data"
  [ "$pc" = 1 ] && echo "arch: amd64" > "$w/etc/vzdump/pct.conf" || echo x > "$w/etc/autre"
  head -c 20000 /dev/urandom > "$w/data/blob"
  local n="vzdump-lxc-$id-$ts.tar.zst"
  ( cd "$w" && tar -I zstd -cf "$T/$n" ./etc ./data )
  "$REAL_GPG" --batch --yes --quiet --symmetric --cipher-algo AES256 --compress-algo none --pinentry-mode loopback \
    --passphrase-file "$tmp/cle" -o "$T/$n.gpg" "$T/$n"
  ( cd "$T" && sha256sum "$n.gpg" > "$n.gpg.sha256" ); sha256sum < "$T/$n" | cut -d' ' -f1 > "$tmp/clair-$id.sha"
  find "$T/$n" -delete
}
mk 100 2026_10_18-02_01_23; mk 101 2026_10_18-02_06_20
printf 'Passage   : 2026-S99\n  vzdump-lxc-100-2026_10_18-02_01_23.tar.zst.gpg   1Ko\n  vzdump-lxc-101-2026_10_18-02_06_20.tar.zst.gpg   1Ko\n' > "$T/MANIFESTE-2026_10_18-03_00_00.txt"
cat > "$tmp/perimetre.yaml" <<EOF
passage: 2026-S99
vague1: 100
vague2: 101
dechiffrement_dir: $LABO/
EOF

cle_ok() { cp "$tmp/cle" "$R/cle-gpg"; echo $(( $(date +%s) + 3600 )) > "$R/phrase.expire"; chmod 600 "$R"/*; }
nouveau() { find "$LABO" -mindepth 1 -delete; : > "$J"; cle_ok; unset STUB_GPG STUB_SSH_CORRUPT STUB_VERIF_RC STUB_SSH_NORM EXPIRE_OVERRIDE; }
lance() { # args : sortie dans $tmp/sortie, code dans rc
  env PATH="$DBL:$PATH" HOME="$tmp/home" GNUPGHOME="$GNUPGHOME" STUB_J="$J" STUB_REAL_GPG="$REAL_GPG" \
    STUB_GPG="${STUB_GPG:-}" STUB_SSH_CORRUPT="${STUB_SSH_CORRUPT:-0}" STUB_VERIF_RC="${STUB_VERIF_RC:-0}" STUB_SSH_NORM="${STUB_SSH_NORM:-0}" \
    ${AVEC_TEST:-PRA_TEST=1} \
    PRA_TIRAGE="${TIRAGE_FORCE:-$T}" PRA_PERIMETRE="${PERIM_FORCE:-$tmp/perimetre.yaml}" PRA_POSTE_LABO="$tmp/poste-labo-ok.sh" PRA_CLE_DIR="$R" \
    bash "$S" "$@" > "$tmp/sortie" 2>&1; rc=$?
}
sans_secret() { ! grep -q "$(cat "$tmp/cle")" "$tmp/sortie" "$J" 2>/dev/null; }

# 1. sans --oui : refus, rien lancé
nouveau; lance
[ "$rc" -eq 3 ] && ! grep -qE '^(gpg|ssh|poste-labo)' "$J" && grep -q 'À SEC' "$tmp/sortie" && ok "sans --oui : refus (exit 3), ni gpg, ni ssh, ni garde lancés" || { ko "sans --oui (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }

# 2. VMID absent du MANIFESTE
nouveau; cp "$T/MANIFESTE-2026_10_18-03_00_00.txt" "$tmp/manif.bak"
grep -v 'lxc-101' "$tmp/manif.bak" > "$T/MANIFESTE-2026_10_18-03_00_00.txt"
lance --oui
[ "$rc" -eq 1 ] && grep -q 'VMID 101 absent du MANIFESTE' "$tmp/sortie" && ! grep -q '^gpg' "$J" && ok "VMID absent du MANIFESTE : arrêt avant tout déchiffrement" || { ko "VMID absent du MANIFESTE (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }
cp "$tmp/manif.bak" "$T/MANIFESTE-2026_10_18-03_00_00.txt"

# 2b. .sha256 du .gpg rouge
nouveau; cp "$T/vzdump-lxc-101-2026_10_18-02_06_20.tar.zst.gpg" "$tmp/g101.bak"
printf 'z' >> "$T/vzdump-lxc-101-2026_10_18-02_06_20.tar.zst.gpg"
lance --oui
[ "$rc" -eq 1 ] && grep -q 'sha256 du .gpg NON conforme' "$tmp/sortie" && ! grep -q '^gpg' "$J" && ok ".sha256 du .gpg rouge : arrêt avant déchiffrement" || { ko ".sha256 rouge (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }
cp "$tmp/g101.bak" "$T/vzdump-lxc-101-2026_10_18-02_06_20.tar.zst.gpg"

# 3. clé absente, puis expirée
nouveau; find "$R" -type f -delete; lance --oui
[ "$rc" -eq 2 ] && grep -q 'clé absente : bash phrase-session.sh charger' "$tmp/sortie" && ! grep -qE '^(gpg|ssh)' "$J" && ok "clé absente : exit 2 et message attendu" || { ko "clé absente (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -3; }
nouveau; echo $(( $(date +%s) - 5 )) > "$R/phrase.expire"; lance --oui
[ "$rc" -eq 2 ] && ! grep -qE '^(gpg|ssh)' "$J" && ok "clé expirée : exit 2, rien lancé" || ko "clé expirée (rc=$rc)"

# 4. garde d'isolement rouge
nouveau; STUB_VERIF_RC=4 lance --oui
[ "$rc" -eq 4 ] && ! grep -qE '^(gpg|ssh)' "$J" && ok "poste-labo --verifier rouge : exit 4, rien déchiffré" || ko "garde rouge (rc=$rc)"

# 5. faux gpg en code 2 alors que la suite du tube réussit
nouveau; STUB_GPG=rc2 lance --oui
[ "$rc" -ne 0 ] && grep -q 'tube en défaut (gpg=2' "$tmp/sortie" && [ ! -e "$LABO/vzdump-lxc-100-2026_10_18-02_01_23.tar.zst" ] && ok "gpg en code 2 : arrêt, archive partielle retirée du labo" || { ko "gpg code 2 (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }

# 6. DECRYPTION_FAILED
nouveau; STUB_GPG=failed lance --oui
[ "$rc" -ne 0 ] && grep -q 'GOODMDC' "$tmp/sortie" && ok "DECRYPTION_FAILED : arrêt" || { ko "DECRYPTION_FAILED (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }

# 6b. DECRYPTION_OKAY sans GOODMDC ; BADMDC présent
nouveau; STUB_GPG=nomdc lance --oui
[ "$rc" -ne 0 ] && grep -q 'GOODMDC' "$tmp/sortie" && ok "OKAY sans GOODMDC : arrêt" || { ko "GOODMDC non exigé (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -4; }
nouveau; STUB_GPG=badmdc lance --oui
[ "$rc" -ne 0 ] && grep -q 'BADMDC' "$tmp/sortie" && ok "BADMDC : arrêt" || { ko "BADMDC accepté (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -4; }

# 6c. crochets d'essai : sans PRA_TEST=1, ou hors de tests/ du projet -> exit 3 « crochet »
nouveau; AVEC_TEST=PRA_TEST=0 lance --oui
[ "$rc" -eq 3 ] && grep -q 'crochet' "$tmp/sortie" && ! grep -qE '^(gpg|ssh|poste-labo)' "$J" && ok "crochets PRA_* sans PRA_TEST=1 : refus exit 3" || { ko "crochet sans PRA_TEST (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -3; }
nouveau; mkdir -p /tmp/claude-1000/hors; cp "$tmp/perimetre.yaml" /tmp/claude-1000/hors/p.yaml; PERIM_FORCE=/tmp/claude-1000/hors/p.yaml lance --oui
[ "$rc" -eq 3 ] && grep -q 'crochet' "$tmp/sortie" && ! grep -qE '^(gpg|ssh|poste-labo)' "$J" && ok "crochet hors de tests/ : refus exit 3" || { ko "crochet hors tests/ (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -3; }

# 6d. dechiffrement_dir piégé (apostrophe, espace, ;) -> refus avant tout ssh
for mauvais in "$LABO/a'b/" "$LABO/a b/" "$LABO/a;b/" "$LABO/\$(x)/"; do
  nouveau; printf 'passage: 2026-S99\nvague1: 100\nvague2: 101\ndechiffrement_dir: %s\n' "$mauvais" > "$tmp/p-mauvais.yaml"
  PERIM_FORCE="$tmp/p-mauvais.yaml" lance --oui
  [ "$rc" -eq 1 ] && grep -q 'dechiffrement_dir' "$tmp/sortie" && ! grep -qE '^(gpg|ssh)' "$J" && ok "dechiffrement_dir refusé : $mauvais" || { ko "dechiffrement_dir accepté : $mauvais (rc=$rc)"; }
done

# 6e. phrase.expire non numérique -> clé refusée
nouveau; echo "abc" > "$R/phrase.expire"; lance --oui
[ "$rc" -eq 2 ] && ! grep -qE '^(gpg|ssh)' "$J" && ok "phrase.expire non numérique : clé refusée (exit 2)" || ko "expire non numérique (rc=$rc)"
nouveau; echo "" > "$R/phrase.expire"; lance --oui
[ "$rc" -eq 2 ] && ok "phrase.expire vide : clé refusée" || ko "expire vide (rc=$rc)"

# 6f. tube cassé : jamais de nom final, même si le nettoyage distant échoue ; .sha256 en dernier
nouveau; STUB_GPG=rc2 STUB_SSH_NORM=1 lance --oui
F100="$LABO/vzdump-lxc-100-2026_10_18-02_01_23.tar.zst"
[ "$rc" -ne 0 ] && [ ! -e "$F100" ] && [ ! -e "$F100.sha256" ] && ok "tube cassé + nettoyage en échec : ni nom final ni .sha256 (reste .partiel seulement)" || { ko "nom final présent après tube cassé (rc=$rc)"; ls "$LABO" | sed 's/^/   | /'; }
nouveau; STUB_SSH_CORRUPT=1 lance --oui
[ ! -e "$F100" ] && [ ! -e "$F100.sha256" ] && [ ! -e "$F100.partiel" ] && ok "sha256 différent : ni nom final, ni .sha256, ni .partiel" || ko "restes après sha256 différent"
nouveau; lance --oui
[ "$rc" -eq 0 ] && [ -e "$F100" ] && [ ! -e "$F100.partiel" ] && grep -q "partiel" "$J" && [ "$(grep -n 'mv ' "$J" | head -1 | cut -d: -f1)" -lt "$(grep -n 'printf' "$J" | head -1 | cut -d: -f1)" ] && ok "nominal : écriture sous .partiel, renommage, puis .sha256 en dernier" || { ko "ordre partiel/mv/.sha256 (rc=$rc)"; grep -n 'ssh' "$J" | head -12 | cut -c1-150 | sed 's/^/   | /'; }

# 7. sha256 du clair différent des deux côtés
nouveau; STUB_SSH_CORRUPT=1 lance --oui
[ "$rc" -ne 0 ] && grep -q 'sha256 du clair différent' "$tmp/sortie" && ok "sha256 du clair différent : arrêt" || { ko "sha256 différent (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }

# 8. cas nominal (vrai gpg) : tout vert, sha256 égal, zstd -t, pct.conf, aucun clair sur le poste, bilan = périmètre
nouveau; lance --oui
if [ "$rc" -eq 0 ] && grep -q 'comptage = périmètre : OUI' "$tmp/sortie" && grep -q '2 envoyée' "$tmp/sortie"; then ok "nominal : 2 VMID envoyées, comptage = périmètre"; else ko "nominal (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -8; fi
okc=1
for id in 100 101; do
  f="$LABO/vzdump-lxc-$id-$( [ $id = 100 ] && echo 2026_10_18-02_01_23 || echo 2026_10_18-02_06_20).tar.zst"
  [ "$(sha256sum < "$f" | cut -d' ' -f1)" = "$(cat "$tmp/clair-$id.sha")" ] || okc=0
  zstd -t -q "$f" 2>/dev/null || okc=0
done
[ "$okc" -eq 1 ] && ok "nominal : clair du labo = clair d'origine (sha256) et zstd -t vert" || ko "nominal : contenu du labo"
grep -q -- '--passphrase-fd 3' "$J" && grep -q -- '--status-fd 4' "$J" && ! grep -q -- '--passphrase-file\|--passphrase ' "$J" && ok "gpg appelé avec --passphrase-fd 3 et --status-fd 4, jamais --passphrase" || ko "options gpg"
sans_secret && ok "la phrase n'apparaît ni à l'écran ni dans le journal d'appels" || ko "FUITE de la phrase"
[ -z "$(find "$T" "$R" "$tmp/home" -type f \( -name '*.tar' -o -name '*.tar.zst' \) 2>/dev/null)" ] && ok "aucun clair (.tar/.tar.zst) sur le poste" || ko "clair trouvé sur le poste"

# 9. idempotence : seconde passe = tout sauté, aucune écriture
: > "$J"; lance --oui
if [ "$rc" -eq 0 ] && grep -q '2 sautée' "$tmp/sortie" && ! grep -q '^gpg' "$J" && ! grep -q '^ssh cat >' "$J"; then ok "idempotent : seconde passe, 2 sautées, ni gpg ni écriture"; else ko "idempotence (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -6; fi

# 10. archive sans ./etc/vzdump/pct.conf -> arrêt
nouveau; mk 101 2026_10_18-02_06_20 0
printf 'Passage   : 2026-S99\n  vzdump-lxc-100-2026_10_18-02_01_23.tar.zst.gpg   1Ko\n  vzdump-lxc-101-2026_10_18-02_06_20.tar.zst.gpg   1Ko\n' > "$T/MANIFESTE-2026_10_18-03_00_00.txt"
lance --oui
[ "$rc" -ne 0 ] && grep -q 'pct.conf absent' "$tmp/sortie" && ok "archive sans ./etc/vzdump/pct.conf : arrêt" || { ko "pct.conf absent non détecté (rc=$rc)"; sed 's/^/   | /' "$tmp/sortie" | head -5; }

# 11. discipline : set -euo pipefail, pas de ssh/scp direct, pas de passphrase en argument
grep -q '^set -euo pipefail' "$S" && ok "set -euo pipefail" || ko "set -euo pipefail absent"
! grep -nE '(^|[;&|(`[:space:]])(ssh|scp)[[:space:]]' "$S" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q . && ok "aucun ssh/scp direct dans le script (ssh_labo seul)" || ko "ssh/scp direct dans le script"
! grep -nE -- '--passphrase([ =]|$)|--passphrase-file' "$S" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q . && ok "aucune phrase en argument dans le script" || ko "phrase en argument"

[ "$fail" -eq 0 ] && echo "TOUT VERT" || echo "ROUGE"
exit "$fail"
